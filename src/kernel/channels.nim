import std/tables

import locks
import queues
import task
import vmdefs, vmmgr

## Channels are used for message passing between tasks.
##   - Each channel has a queue and a buffer.
##   - The queue is used to store messages. Tasks don't have direct access to the queue.
##     They send/receive messages through system calls.
##   - The buffer is used to store data. Each message has a pointer to the data in the buffer.
##   - The buffer is allocated to variable-sized message data in a first-in-first-out manner.
##   - The buffer is circular.
##   - Buffers are shared between tasks communicating through the same channel.
##   - Read/write access to the buffer is enforced through virtual memory page mappings.
##
## User space API:
##   - `alloc` to allocate space for a message in the buffer
##   - `send` to send a message (previously allocated) to a channel
##   - `recv` to receive a message from a channel (returns a pointer to the message in the buffer)
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
  Message* = object
    len*: int
    data*: ptr UncheckedArray[byte]

  ChannelBuffer* = object
    cap*: int
    data*: ptr UncheckedArray[byte]
    allocOffset*: int = 0
    vmMapping: VmMapping

  Channel* = ref object
    id*: int
    queue: BlockingQueue[Message]
    buffer: ChannelBuffer
    writeLock: Lock

  ChannelMode* = enum
    Read
    Write

const
  DefaultMessageCapacity = 512
  NullMessage = Message(len: -1, data: nil)

let
  logger = DebugLogger(name: "chan")

var
  channels = initTable[int, Channel]()
  nextChannelId = 0
  nextChannelIdLock: Lock = newSpinLock()

proc newChannelId(): int =
  withLock(nextChannelIdLock):
    result = nextChannelId
    inc nextChannelId

proc create*(msgSize: int, msgCapacity: int = DefaultMessageCapacity): Channel =
  let buffSize = msgSize * msgCapacity
  let numPages = (buffSize + PageSize - 1) div PageSize
  # Map the buffer in user space.
  let userMapping = uvMap(
    pml4 = getActivePageTable(),
    npages = numPages.uint64,
    perms = {pRead, pWrite},
    flags = {vmShared},
  )
  # Map the buffer in kernel space for shared access.
  let kernelMapping = kvMapShared(
    mapping = userMapping,
    perms = {pRead, pWrite},
    flags = {vmShared},
  )

  let buffStartVirt = cast[VAddr](userMapping.region.start)
  logger.info &"create: mapped channel buffer to {buffStartVirt.uint64:#x}"

  result = Channel(
    id: newChannelId(),
    queue: newBlockingQueue[Message](msgCapacity),
    buffer: ChannelBuffer(
      cap: buffSize,
      data: cast[ptr UncheckedArray[byte]](userMapping.region.start),
      vmMapping: userMapping,
    ),
    writeLock: newSpinLock(),
  )
  channels[result.id] = result
  logger.info &"create: created channel id {result.id} @ {cast[uint64](result.buffer.data):#x}"

proc open*(chid: int, task: Task, mode: ChannelMode): int =
  ## Open a channel for a task in a specific mode. Map the buffer to the task's address space.
  if not channels.hasKey(chid):
    logger.info &"open: channel id {chid} not found"
    return -1

  var ch = channels[chid]
  let buffStart = ch.buffer.data
  let numPages = (ch.buffer.cap + PageSize - 1) div PageSize
  let perms = if mode == ChannelMode.Read: {pRead} else: {pRead, pWrite}

  let buffStartVirt = cast[VAddr](buffStart)
  let mapping = uvMapShared(
    pml4 = task.pml4,
    mapping = ch.buffer.vmMapping,
    perms = perms,
    flags = {vmShared},
  )
  task.vmMappings.add(mapping)
  logger.info &"open: opened channel id {chid} for task {task.id}"

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

proc alloc*(chid: int, len: int): pointer {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"alloc: channel id {chid} not found"
    return nil

#  logger.info &"alloc: allocating message (len: {len}) @ chid={chid}"

  var ch = channels[chid]
  withLock(ch.writeLock):
    if ch.buffer.allocOffset + len > ch.buffer.cap:
      # TODO: wrap around the buffer
      logger.info &"alloc: buffer full @ chid={chid}"
      return nil
    
    let data = ch.buffer.data +! ch.buffer.allocOffset
    inc ch.buffer.allocOffset, len

    logger.info &"alloc: allocated message (len: {len}, addr: {cast[uint64](data):#x}) @ chid={chid}"
    result = data

proc send*(chid: int, msg: Message): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"send: channel id {chid} not found"
    return -1

#  logger.info &"send: sending message @ chid={chid}"

  var ch = channels[chid]
  withLock(ch.writeLock):
    ch.queue.enqueue(msg)
    logger.info &"send: enqueued message (len: {msg.len}, addr: {cast[uint64](msg.data):#x}) @ chid={chid}"

proc recv*(chid: int): Message {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"recv: channel id {chid} not found"
    return NullMessage

#  logger.info &"recv: receiving message @ chid={chid}"

  result = channels[chid].queue.dequeue()
  logger.info &"recv: dequeued message (len: {result.len}, addr: {cast[uint64](result.data):#x}) @ chid={chid}"
