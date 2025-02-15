import std/tables

import common/pagetables
import debugcon
import locks
import queues
import taskdef
import vmm

## Channels are used for message passing between tasks.
##   - Each channel has a queue and a buffer.
##   - The queue is used to store messages. Tasks don't have direct access to the queue.
##     They send/receive messages through system calls.
##   - The buffer is used to store data. Each message has a pointer to the data in the buffer.
##   - The buffer is divided into equal sized slots. Each slot is used to store a message.
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

  Channel* = ref object
    id*: int
    queue: BlockingQueue[Message]
    buffer: ChannelBuffer
    nextSlot: int = 0
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

proc advanceSlot(ch: Channel) =
  ch.nextSlot = (ch.nextSlot + 1) mod ch.queue.cap

proc newChannel*(msgSize: int, msgCapacity: int = DefaultMessageCapacity): Channel =
  let buffSize = msgSize * msgCapacity
  let numPages = (buffSize + PageSize - 1) div PageSize
  let buffRegion = vmalloc(uspace, numPages.uint64)
  mapRegion(
    pml4 = getActivePML4(),
    virtAddr = buffRegion.start,
    pageCount = numPages.uint64,
    pageAccess = paReadWrite,
    pageMode = pmUser,
    noExec = true
  )
  let buffStartVirt = cast[VirtAddr](buffRegion.start)
  let buffStartPhys = v2p(buffStartVirt).get

  result = Channel(
    id: newChannelId(),
    queue: newBlockingQueue[Message](msgCapacity),
    buffer: ChannelBuffer(
      cap: buffSize,
      data: cast[ptr UncheckedArray[byte]](buffRegion.start)
    ),
    writeLock: newSpinLock(),
  )
  channels[result.id] = result

proc open*(chid: int, task: Task, mode: ChannelMode): int =
  ## Open a channel for a task in a specific mode. Map the buffer to the task's address space.
  if not channels.hasKey(chid):
    logger.info &"open: channel id {chid} not found"
    return -1

  var ch = channels[chid]
  let buffStart = ch.buffer.data
  let numPages = (ch.buffer.cap + PageSize - 1) div PageSize
  let pageAccess = if mode == ChannelMode.Read: paRead else: paReadWrite

  let buffStartVirt = cast[VirtAddr](buffStart)
  let buffStartPhys = v2p(buffStartVirt, kpml4).get
  mapRegion(
    pml4 = task.pml4,
    virtAddr = buffStartVirt,
    physAddr = buffStartPhys,
    pageCount = numPages.uint64,
    pageAccess = pageAccess,
    pageMode = pmUser,
    noExec = true
  )
  logger.info &"open: opened channel id {chid} for task {task.id}"

proc close*(chid: int, task: Task): int =
  ## Close a channel for a task. Unmap the buffer from the task's address space.
  if not channels.hasKey(chid):
    logger.info &"close: channel id {chid} not found"
    return -1

  var ch = channels[chid]
  let buffStart = ch.buffer.data
  let numPages = (ch.buffer.cap + PageSize - 1) div PageSize
  unmapRegion(
    pml4 = task.pml4,
    virtAddr = cast[VirtAddr](buffStart),
    pageCount = numPages.uint64
  )
  logger.info &"close: closed channel id {chid} for task {task.id}"

proc send*(chid: int, msg: Message): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"send: channel id {chid} not found"
    return -1

  logger.info &"send: sending message @ chid={chid}"

  var ch = channels[chid]
  withLock(ch.writeLock):
    # copy message data to the buffer
    let offset = ch.nextSlot * msg.len
    let data = ch.buffer.data +! offset
    copyMem(data, msg.data, msg.len)
    ch.advanceSlot()

    ch.queue.enqueue(Message(len: msg.len, data: data))
    logger.info &"send: enqueued message (len: {msg.len}, addr: {cast[uint64](data):#x}) @ chid={chid}"

proc recv*(chid: int): Message {.stackTrace:off.} =
  if not channels.hasKey(chid):
    logger.info &"recv: channel id {chid} not found"
    return NullMessage

  logger.info &"recv: receiving message @ chid={chid}"

  result = channels[chid].queue.dequeue()
  logger.info &"recv: dequeued message (len: {result.len}, addr: {cast[uint64](result.data):#x}) @ chid={chid}"
