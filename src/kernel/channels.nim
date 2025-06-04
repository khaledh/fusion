import std/[sequtils, tables]

import common/serde
import condvars
import locks
import queues
import task
import vmdefs, vmmgr

## Channels facilitate message passing between tasks.
##
## Core Concepts:
##   - Message Size: Each channel operates with a fixed maximum message payload size (`S`),
##     determined by rounding the user-specified size up to the nearest power-of-two
##     (8, 16, 32, 64, 128, 256, 512, or 1024 bytes).
##   - Internal Queue: Each channel (`Channel[S]`) maintains a `BlockingQueue` of `Message[S]` objects.
##     The `Message[S]` type contains an inline data array (`array[S, byte]`) which holds the
##     actual message payload or a descriptor (e.g., an `FString` for strings).
##   - Channel Buffer (`ChannelBuffer`): A separate, VM-mappable memory region is associated with
##     each channel. This buffer can be used by senders via the `alloc` procedure to obtain
##     shared memory, for instance, to store string content before sending an `FString` descriptor.
##
## Data Handling:
##   - Sending: When a message (e.g., an object of type `T`) is sent, its data (up to `S` bytes)
##     is copied into the `Message[S].data` array of a new message object, which is then enqueued.
##     For strings, the string content is typically placed into the `ChannelBuffer` (using `alloc`),
##     and an `FString` descriptor (containing a pointer to this content and length) is what gets
##     copied into the `Message[S].data` array.
##   - Receiving: When a message is received, its payload is copied from the `Message[S].data`
##     array (in the dequeued message) into the receiver's provided buffer.
##
## Memory Management and Sharing:
##   - The `ChannelBuffer` is mapped into the address space of tasks that open the channel.
##     Read/write access is managed by VM permissions.
##   - Tasks interact with channels via system call wrappers.
##
## User Space API Summary:
##   - `createKernelChannel`, `createUserChannel`: Create a new channel and open it.
##     The channel's buffer is mapped into the creator's (or specified task's) address space.
##   - `openUserChannel`, `openKernelChannel`: Open an existing channel by ID, mapping its
##     `ChannelBuffer` into the task's address space.
##   - `alloc`: (Sender) Allocate a segment of memory from the channel's shared `ChannelBuffer`.
##     This is primarily used for preparing data (like large strings) that will be referenced by
##     a descriptor sent as the message payload.
##   - `send`: (Sender) Enqueue a message. The message data (or a descriptor) is copied into the
##     channel's internal queue.
##   - `recv`, `tryRecv`: (Receiver) Dequeue a message, copying its payload to a user-provided buffer.
##     `tryRecv` is non-blocking.
##   - `recvAny`: (Receiver) Wait for and receive a message from one of several specified channels.
##   - `close`: Close a channel for a specific task, which typically involves unmapping the
##     `ChannelBuffer` from that task's address space.

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

  MessageHandler*[T] = tuple[id: int, handler: proc (data: T)]

const
  DefaultCap* = 1024

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

# Forward declarations
proc createKernelChannel*(mode: ChannelMode, msgSize: int, msgCapacity: int = DefaultCap): int
proc createKernelChannel*[T](mode: ChannelMode, msgCapacity: int = DefaultCap): int
proc createUserChannel*(task: Task, mode: ChannelMode, msgSize: int, msgCapacity: int = DefaultCap): int
proc createUserChannel*[T](task: Task, mode: ChannelMode, msgCapacity: int = DefaultCap): int

proc openUserChannel*(chid: int, task: Task, mode: ChannelMode): int
proc openKernelChannel*(task: Task, chid: int, mode: ChannelMode): int

proc alloc*(chid: int, len: int): pointer

proc send*(chid: int, len: int, data: pointer): int
proc send*[T](chid: int, data: T): int

proc recv*(chid: int, buf: pointer, len: int): int
proc recv*[T](chid: int): Option[T]
proc tryRecv*(chid: int, buf: pointer, len: int): int
proc tryRecv*[T](chid: int): Option[T]

proc recvAny*(chids: openArray[int], buf: pointer, len: int): int
proc recvAny*[T1, T2](h1: MessageHandler[T1], h2: MessageHandler[T2]): int

proc close*(chid: int, task: Task): int


####################################################################################################
# Create Channel
####################################################################################################

## Helper templates/functions

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

proc createChannel(
  msgSize: int,
  msgCapacity: int = DefaultCap,
  vmMapper: proc (npages: uint64): VmMapping,
): int =
  let chMsgSize = msgSizeToChannelSize(msgSize)
  let chBuffSize = chMsgSize * msgCapacity
  let numPages = (chBuffSize + PageSize - 1) div PageSize

  let mapping = vmMapper(numPages.uint64)

  let buffStart = cast[VAddr](mapping.region.start)
  logger.info &"create: mapped channel buffer to {buffStart.uint64:#x}"

  let ch = newChannelBySize(chMsgSize, msgCapacity, chBuffSize, mapping)
  channels[ch.id] = ch
  result = ch.id
  logger.info &"create: created channel id {ch.id} @ {cast[uint64](ch.buffer.data):#x}"

## Kernel channel

proc createKernelChannel*(
  mode: ChannelMode, msgSize: int, msgCapacity: int = DefaultCap
): int =
  createChannel(msgSize, msgCapacity, proc (npages: uint64): VmMapping =
    kvMap(
      npages = npages,
      perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite},
      flags = {vmShared},
    )
  )

proc createKernelChannel*[T](mode: ChannelMode, msgCapacity: int = DefaultCap): int =
  createKernelChannel(mode, sizeof(T), msgCapacity)

## User channel

proc createUserChannel*(
  task: Task, mode: ChannelMode, msgSize: int, msgCapacity: int = DefaultCap
): int =
  createChannel(msgSize, msgCapacity, proc (npages: uint64): VmMapping =
    let mapping = uvMap(
      pml4 = task.pml4,
      npages = npages,
      perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite},
      flags = {vmShared},
    )
    task.vmMappings.add(mapping)
    mapping
  )

proc createUserChannel*[T](task: Task, mode: ChannelMode, msgCapacity: int = DefaultCap): int =
  createUserChannel(task, mode, sizeof(T), msgCapacity)

####################################################################################################
# Open Channel
####################################################################################################

proc openChannel*(
  chid: int,
  mode: ChannelMode,
  vmMapper: proc (ch: ChannelBase): VmMapping,
): int =
  ## Open a channel for a task in a specific mode. Map the buffer to the task's address space.
  if not channels.hasKey(chid):
    logger.info &"open: channel id {chid} not found"
    return -1

  var ch = channels[chid]
  let mapping = vmMapper(ch)

proc openUserChannel*(chid: int, task: Task, mode: ChannelMode): int =
  ## Open a user channel for a task in a specific mode. Map the buffer to the task's address space.
  ##
  ## Arguments:
  ##   - `chid`: the channel id
  ##   - `task`: the task to open the channel for
  ##   - `mode`: the mode to open the channel in
  ##
  ## Returns:
  ##   - 0 on success, -1 on failure
  result = openChannel(chid, mode) do (ch: ChannelBase) -> VmMapping:
    let mapping = uvMapShared(
      pml4 = task.pml4,
      mapping = ch.buffer.vmMapping,
      perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite},
      flags = {vmShared},
    )
    task.vmMappings.add(mapping)
    mapping

  logger.info &"open: opened channel id {result} for task {task.id} in mode {mode}"

proc openKernelChannel*(task: Task, chid: int, mode: ChannelMode): int =
  ## Open a kernel channel in a specific mode. Map the buffer to the kernel's address space.
  ##
  ## Arguments:
  ##   - `chid`: the channel id
  ##   - `mode`: the mode to open the channel in
  ##
  ## Returns:
  ##   - 0 on success, -1 on failure
  result = openChannel(chid, mode) do (ch: ChannelBase) -> VmMapping:
    let mapping = kvMapShared(
      mapping = ch.buffer.vmMapping,
      perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite},
      flags = {vmShared},
    )
    task.vmMappings.add(mapping)
    mapping

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

####################################################################################################
# Close Channel
####################################################################################################

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

####################################################################################################
# Send Message
####################################################################################################

template sendMessageAux[S: static int](ch: ChannelBase, len: int, data: pointer) =
  let chan = cast[Channel[S]](ch)
  var msg = Message[S]()
  msg.len = len
  copyMem(msg.data[0].addr, data, len)
  chan.queue.enqueue(msg)

template sendMessage(ch: ChannelBase, len: int, data: pointer) =
  case ch.msgSize:
    of 8: sendMessageAux[8](ch, len, data)
    of 16: sendMessageAux[16](ch, len, data)
    of 32: sendMessageAux[32](ch, len, data)
    of 64: sendMessageAux[64](ch, len, data)
    of 128: sendMessageAux[128](ch, len, data)
    of 256: sendMessageAux[256](ch, len, data)
    of 512: sendMessageAux[512](ch, len, data)
    of 1024: sendMessageAux[1024](ch, len, data)
    else: raise newException(ValueError, "Message size too large (max 1024)")

proc send*(chid: int, len: int, data: pointer): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"send: channel id {chid} not found"
    return -1

  logger.info &"send: chid={chid}, len={len}, data @ {cast[uint64](data):#x}"

  let ch = channels[chid]
  withLock(ch.writeLock):
    sendMessage(ch, len, data)
    # logger.info &"send: enqueued message (len: {len} @ chid={chid}"

proc send*[T](chid: int, data: T): int {.stackTrace:off.} =
  # check if T is a string
  when T is string:
    let fs = buildString(data, proc (size: int): pointer = alloc(chid, size))
    let dataPtr = fs.addr
    let dataLen = sizeof(FString)
  else:
    let dataPtr = data.addr
    let dataLen = sizeof(T)

  send(chid, dataLen, dataPtr)

####################################################################################################
# Receive Message
####################################################################################################

proc recvMessageAux[S: static int](
  ch: ChannelBase,
  buf: pointer,
  len: int,
  noWait: bool = false,
): int =
  let chan = cast[Channel[S]](ch)
  var msg: Message[S]
  if noWait:
    let msgOpt = chan.queue.dequeueNoWait()
    if msgOpt.isSome:
      msg = msgOpt.get()
    else:
      return -1
  else:
    msg = chan.queue.dequeue()

  if len < msg.len:
    logger.info &"recv: buffer too small (len: {len}, msg.len: {msg.len})"
    return -1

  copyMem(buf, msg.data[0].addr, len)

proc recvMessage(ch: ChannelBase, buf: pointer, len: int, noWait: bool = false): int =
  case ch.msgSize:
    of 8: recvMessageAux[8](ch, buf, len, noWait)
    of 16: recvMessageAux[16](ch, buf, len, noWait)
    of 32: recvMessageAux[32](ch, buf, len, noWait)
    of 64: recvMessageAux[64](ch, buf, len, noWait)
    of 128: recvMessageAux[128](ch, buf, len, noWait)
    of 256: recvMessageAux[256](ch, buf, len, noWait)
    of 512: recvMessageAux[512](ch, buf, len, noWait)
    of 1024: recvMessageAux[1024](ch, buf, len, noWait)
    else: raise newException(ValueError, "Message size too large (max 1024)")

proc recv*(chid: int, buf: pointer, len: int): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"recv: channel id {chid} not found"
    return -1

  let ch = channels[chid]
  result = recvMessage(ch, buf, len, noWait = false)
  # logger.info &"recv: dequeued message (len: {len}) @ chid={chid}"

proc recv*[T](chid: int): Option[T] {.stackTrace:off.} =
  var t: T
  let ret = recv(chid, t.addr, sizeof(T))
  result = if ret < 0: none(T) else: some(t)

proc tryRecv*(chid: int, buf: pointer, len: int): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"tryRecv: channel id {chid} not found"
    return -1

  let ch = channels[chid]
  result = recvMessage(ch, buf, len, noWait = true)

proc tryRecv*[T](chid: int): Option[T] {.stackTrace:off.} =
  var t: T
  let ret = tryRecv(chid, t.addr, sizeof(T))
  result = if ret < 0: none(T) else: some(t)

####################################################################################################
# Receive from multiple channels
####################################################################################################

template addNotEmptyListenerAux[S: static int](ch: ChannelBase, listener: QueueListener) =
  let chan = cast[Channel[S]](ch)
  chan.queue.addNotEmptyListener(listener)

template addNotEmptyListener(ch: ChannelBase, listener: QueueListener) =
  case ch.msgSize:
    of 8: addNotEmptyListenerAux[8](ch, listener)
    of 16: addNotEmptyListenerAux[16](ch, listener)
    of 32: addNotEmptyListenerAux[32](ch, listener)
    of 64: addNotEmptyListenerAux[64](ch, listener)
    of 128: addNotEmptyListenerAux[128](ch, listener)
    of 256: addNotEmptyListenerAux[256](ch, listener)
    of 512: addNotEmptyListenerAux[512](ch, listener)
    of 1024: addNotEmptyListenerAux[1024](ch, listener)
    else: raise newException(ValueError, "Message size too large (max 1024)")

template removeNotEmptyListenerAux[S: static int](ch: ChannelBase, listener: QueueListener) =
  let chan = cast[Channel[S]](ch)
  chan.queue.removeNotEmptyListener(listener)

template removeNotEmptyListener(ch: ChannelBase, listener: QueueListener) =
  case ch.msgSize:
    of 8: removeNotEmptyListenerAux[8](ch, listener)
    of 16: removeNotEmptyListenerAux[16](ch, listener)
    of 32: removeNotEmptyListenerAux[32](ch, listener)
    of 64: removeNotEmptyListenerAux[64](ch, listener)
    of 128: removeNotEmptyListenerAux[128](ch, listener)
    of 256: removeNotEmptyListenerAux[256](ch, listener)
    of 512: removeNotEmptyListenerAux[512](ch, listener)
    of 1024: removeNotEmptyListenerAux[1024](ch, listener)
    else: raise newException(ValueError, "Message size too large (max 1024)")

proc recvAny*(chids: openArray[int], buf: pointer, len: int): int {.stackTrace:off.} =
  ## Receive from multiple channels, returning the first channel that has a message.
  ##
  ## Arguments:
  ##   - `chids`: array of channel IDs
  ##   - `buf`: pointer to buffer to store the message
  ##   - `len`: length of the buffer
  ##
  ## Returns:
  ##   - channel id on success
  ##   - -1 on error
  ##
  ## Side effects:
  ##   - If no channel has a message, the task will be blocked until a message arrives.
  ##
  let nonExistent = chids.filter(chid => not channels.hasKey(chid))
  if nonExistent.len > 0:
    logger.info &"recvAny: channel ids {nonExistent} not found"
    return -1

  var chs = chids.map(chid => channels[chid])

  # First, check if any of the channels has a message
  for ch in chs:
    result = recvMessage(ch, buf, len, noWait = true)
    if result >= 0:
      # message received from this channel
      return ch.id

  # none of the channels has a message; wait/listen for a message on any of the channels
  var listener = newQueueListener()
  try:
    # add the listener to all channels
    for ch in chs:
      ch.addNotEmptyListener(listener)

    result = -1
    while result < 0:
      # wait for a message to arrive on any of the channels
      logger.info &"waiting for a message on channels {chids}..."
      listener.cv.wait(listener.lock)

      # find the channel that has a message
      for ch in chs:
        result = recvMessage(ch, buf, len, noWait = true)
        if result >= 0:
          # message received from this channel
          logger.info &"message received from channel {ch.id}"
          result = ch.id
          break
      
      # message was grabbed by another task, try again

  finally:
    # remove the listener from all channels
    for ch in chs:
      ch.removeNotEmptyListener(listener)

proc recvAny*[T1, T2](
  h1: MessageHandler[T1],
  h2: MessageHandler[T2],
): int =
  if not channels.hasKey(h1.id):
    logger.info &"recvAny[T1, T2]: channel id {h1.id} not found"
    return -1

  if not channels.hasKey(h2.id):
    logger.info &"recvAny[T1, T2]: channel id {h2.id} not found"
    return -1

  let ch1 = channels[h1.id]
  let ch2 = channels[h2.id]

  let maxSize = max(ch1.msgSize, ch2.msgSize)
  let buf = alloc0(maxSize)
  defer: dealloc(buf)

  result = recvAny([h1.id, h2.id], buf, maxSize)

  if result < 0:
    return -1

  if result == h1.id and h1.handler != nil:
    h1.handler(cast[ptr T1](buf)[])
  elif result == h2.id and h2.handler != nil:
    h2.handler(cast[ptr T2](buf)[])
  else:
    raise newException(ValueError, "recvAny[T1, T2]: returned channel id is not in the list of channels!")
