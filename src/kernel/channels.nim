import std/tables

import locks
import queues
import task
import vmdefs, vmmgr

## TODO: Revise the description below (outdated).
##
## Channels are used for message passing between tasks.
##   - Each channel internally has a fixed power-of-two message size which is chosen based on the
##     user-provided message size: 8, 16, 32, 64, 128, 256, 512, 1024
##   - Each channel has a circular queue and a circular buffer.
##   - The queue is used to store message metadata.
##   - The buffer is used to store actual message data.
##   - Each message has a pointer to the data in the buffer.
##   - The buffer is allocated to variable-sized message data.
##   - Tasks don't have direct access to the queue. They send/receive messages through system calls.
##   - Buffers are shared between tasks communicating through the same channel.
##   - Read/write access to the buffer is enforced through virtual memory page mappings.
##   - The buffer is mapped into the task's address space when the channel is opened.
##
## User space API:
##   - `create` to create and open a channel
##   - `open` to open an existing channel
##   - `alloc` to allocate space for a message in the buffer (by sender)
##   - `send` to send a message (previously allocated) to a channel
##   - `recv` to receive a message from a channel (returns a pointer to the message in the buffer)
##   - `free` to free a message (by receiver)
##   - `close` to close a channel
##
## queue
## +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
## | msg1  | msg2  | msg3  |  ...  |  ...  |  ...  |  ...  |  ...  |  ...  |  ...  |
## +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
##     |       |
##     |       +-----------------------+
##     +---------+                     |
##               |                     |
## buffer        v                     v
## +-------------+---------------------+---------------------+---------------------+
## |    ...      |  data1              |  data2              |    ...              |
## +-------------+---------------------+---------------------+---------------------+

type
  MessageBase = object of RootObj
    len: int
  Message*[S: static int] = object of MessageBase
    data: array[S, byte]

  ChannelBuffer* = object
    cap*: int
    data*: ptr UncheckedArray[byte]
    allocOffset*: int = 0
    vmMapping: VmMapping

  ChannelBase = ref object of RootObj
    id*: int
    msgSize*: int
    buffer: ChannelBuffer
    writeLock: Lock
  Channel*[S: static int] = ref object of ChannelBase
    queue: BlockingQueue[Message[S]]

  ChannelMode* = enum
    Read
    Write

const
  DefaultMessageCapacity* = 1024

let
  logger = DebugLogger(name: "channels")

var
  channels = initTable[int, ChannelBase]()
  nextChannelId = 0
  nextChannelIdLock: Lock = newSpinLock()

proc newChannelId(): int =
  withLock(nextChannelIdLock):
    result = nextChannelId
    inc nextChannelId

template msgSizeToChannelSize(msgSize: int): int =
  if msgSize <= 8: 8
  elif msgSize <= 16: 16
  elif msgSize <= 32: 32
  elif msgSize <= 64: 64
  elif msgSize <= 128: 128
  elif msgSize <= 256: 256
  elif msgSize <= 512: 512
  elif msgSize <= 1024: 1024
  else:
    raise newException(ValueError, "Message size too large (max 1024)")

template constructChannel(chMsgSize: static int, msgCapacity, buffSize, mapping: untyped): ChannelBase =
  cast[ChannelBase](Channel[chMsgSize](
    id: newChannelId(),
    msgSize: chMsgSize,
    queue: newBlockingQueue[Message[chMsgSize]](msgCapacity),
    buffer: ChannelBuffer(
      cap: buffSize,
      data: cast[ptr UncheckedArray[byte]](mapping.region.start),
      vmMapping: mapping,
    ),
    writeLock: newSpinLock(),
  ))

template newChannelBySize(chMsgSize: int, msgCapacity, buffSize, mapping: untyped): ChannelBase =
  case chMsgSize:
    of 8: constructChannel(8, msgCapacity, buffSize, mapping)
    of 16: constructChannel(16, msgCapacity, buffSize, mapping)
    of 32: constructChannel(32, msgCapacity, buffSize, mapping)
    of 64: constructChannel(64, msgCapacity, buffSize, mapping)
    of 128: constructChannel(128, msgCapacity, buffSize, mapping)
    of 256: constructChannel(256, msgCapacity, buffSize, mapping)
    of 512: constructChannel(512, msgCapacity, buffSize, mapping)
    of 1024: constructChannel(1024, msgCapacity, buffSize, mapping)
    else: raise newException(ValueError, "Message size too large (max 1024)")

template sendMessageAux(ch: ChannelBase, msgSize: static int, len: int, data: pointer) =
  let chan = cast[Channel[msgSize]](ch)
  var msg = Message[msgSize]()
  msg.len = len
  copyMem(msg.data.addr, data, len)
  chan.queue.enqueue(msg)

template sendMessage(ch: ChannelBase, len: int, data: pointer) =
  case ch.msgSize:
    of 8: sendMessageAux(ch, 8, len, data)
    of 16: sendMessageAux(ch, 16, len, data)
    of 32: sendMessageAux(ch, 32, len, data)
    of 64: sendMessageAux(ch, 64, len, data)
    of 128: sendMessageAux(ch, 128, len, data)
    of 256: sendMessageAux(ch, 256, len, data)
    of 512: sendMessageAux(ch, 512, len, data)
    of 1024: sendMessageAux(ch, 1024, len, data)
    else: raise newException(ValueError, "Message size too large (max 1024)")

template recvMessageAux(ch: ChannelBase, msgSize: static int, buf: pointer, len: int) =
  let chan = cast[Channel[msgSize]](ch)
  let msg = chan.queue.dequeue()
  if len < msg.len:
    logger.info &"recv: buffer too small (buffer len: {len}, msg len: " & $msg.len & ") @ chid={ch.id}"
    result = -1
  else:
    copyMem(buf, msg.data.addr, len)

proc recvMessage(ch: ChannelBase, buf: pointer, len: int): int =
  case ch.msgSize:
    of 8: recvMessageAux(ch, 8, buf, len)
    of 16: recvMessageAux(ch, 16, buf, len)
    of 32: recvMessageAux(ch, 32, buf, len)
    of 64: recvMessageAux(ch, 64, buf, len)
    of 128: recvMessageAux(ch, 128, buf, len)
    of 256: recvMessageAux(ch, 256, buf, len)
    of 512: recvMessageAux(ch, 512, buf, len)
    of 1024: recvMessageAux(ch, 1024, buf, len)
    else: raise newException(ValueError, "Message size too large (max 1024)")

proc create*(
  task: Task, mode: ChannelMode, msgSize: int, msgCapacity: int = DefaultMessageCapacity
): int =
  let chMsgSize = msgSizeToChannelSize(msgSize)
  let chBuffSize = chMsgSize * msgCapacity
  let numPages = (chBuffSize + PageSize - 1) div PageSize
  # Map the buffer in user space.
  let mapping = uvMap(
    pml4 = task.pml4,
    npages = numPages.uint64,
    perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite},
    flags = {vmShared},
  )
  task.vmMappings.add(mapping)

  let buffStart = cast[VAddr](mapping.region.start)
  logger.info &"create: mapped channel buffer to {buffStart.uint64:#x}"

  let ch = newChannelBySize(chMsgSize, msgCapacity, chBuffSize, mapping)
  channels[ch.id] = ch
  result = ch.id
  logger.info &"create: created channel id {ch.id} @ {cast[uint64](ch.buffer.data):#x}"

proc create*[T](task: Task, mode: ChannelMode, msgCapacity: int = DefaultMessageCapacity): int =
  create(task, mode, sizeof(T), msgCapacity)

proc open*(chid: int, task: Task, mode: ChannelMode): int =
  ## Open a channel for a task in a specific mode. Map the buffer to the task's address space.
  if not channels.hasKey(chid):
    logger.info &"open: channel id {chid} not found"
    return -1

  var ch = channels[chid]
  let perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite}

  let mapping = uvMapShared(
    pml4 = task.pml4,
    mapping = ch.buffer.vmMapping,
    perms = perms,
    flags = {vmShared},
  )
  task.vmMappings.add(mapping)

  logger.info &"open: opened channel id {chid} for task {task.id} in mode {mode}"

proc alloc*(chid: int, len: int): pointer {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"alloc: channel id {chid} not found"
    return nil

  var ch = channels[chid]
  withLock(ch.writeLock):
    if ch.buffer.allocOffset + len > ch.buffer.cap:
      # TODO: wrap around the buffer
      logger.info &"alloc: buffer full @ chid={chid}"
      return nil
    
    result = ch.buffer.data +! ch.buffer.allocOffset
    inc ch.buffer.allocOffset, len

    logger.info &"alloc: allocated message (len: {len}, addr: {cast[uint64](result):#x}) @ chid={chid}"

proc send*(chid: int, len: int, data: pointer): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"send: channel id {chid} not found"
    return -1

  # logger.info &"send: sending message (len: {len}) @ chid={chid}"

  let ch = channels[chid]
  withLock(ch.writeLock):
    sendMessage(ch, len, data)
    # logger.info &"send: enqueued message (len: {len} @ chid={chid}"

proc send*[T](chid: int, data: T): int {.stackTrace:off.} =
  send(chid, sizeof(T), data.addr)

proc recv*(chid: int, buf: pointer, len: int): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"recv: channel id {chid} not found"
    return -1

  let ch = channels[chid]

  result = recvMessage(ch, buf, len)
  # logger.info &"recv: dequeued message (len: {len}) @ chid={chid}"

proc recv*[T](chid: int): Option[T] {.stackTrace:off.} =
  var data: T
  let ret = recv(chid, data.addr, sizeof(T))
  result = if ret < 0: none(T) else: some(data)

proc close*(chid: int, task: Task): int =
  ## Close a channel for a task. Unmap the buffer from the task's address space.
  if not channels.hasKey(chid):
    logger.info &"close: channel id {chid} not found"
    return -1

  var ch = channels[chid]
  let buffStart = ch.buffer.data
  let numPages = (ch.buffer.cap + PageSize - 1) div PageSize
  # discard uvUnmap(
  #   pml4 = task.pml4,
  #   vaddr = cast[VAddr](buffStart),
  #   npages = numPages.uint64
  # )
  logger.info &"close: closed channel id {chid} for task {task.id}"
