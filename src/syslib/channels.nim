#[
  Channel library functions
]#
import std/[options, sequtils, strformat]

import common/[debugcon, serde]
include syscalldef

let
  logger = DebugLogger(name: "sys:chan")

type
  ChannelMode* = enum
    Read
    Write

  Channel*[T] = object
    id*: int
    msgSize*: int
    mode*: ChannelMode
    alloc*: Allocator

template `+!`(p: pointer, i: int): pointer =
  cast[pointer](cast[uint64](p) + i.uint64)

template `+!`[T](p: ptr T, i: int): ptr T =
  cast[ptr T](cast[uint64](p) + i.uint64)

################################# System Calls #################################

proc channelCreate*(mode: ChannelMode, msgSize: int): int =
  let modeVal = mode.int
  asm """
    syscall
    : "=a" (`result`)
    : "D" (`SysChannelCreate`),
      "S" (`modeVal`),
      "d" (`msgSize`)
    : "rcx", "r11", "memory"
  """

proc channelOpen*(cid: int, mode: ChannelMode): int =
  ## Open a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   mode (in): channel open mode
  ## 
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ##
  # logger.info "open: opening channel"
  let modeVal = mode.int
  asm """
    syscall
    : "=a" (`result`)
    : "D" (`SysChannelOpen`),
      "S" (`cid`),
      "d" (`modeVal`)
    : "rcx", "r11", "memory"
  """

proc channelAlloc*(cid: int, len: int): pointer =
  ## Allocate memory in a channel buffer
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   len (in): size to allocate
  ##   pdata (out): pointer to the allocated memory
  ## 
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ##

  var
    pdata {.codegenDecl: """register $# $# asm("r8")""".}: pointer
    ret: int

  asm """
    syscall
    : "=a" (`ret`),
      "=r" (`pdata`)
    : "D" (`SysChannelAlloc`),
      "S" (`cid`),
      "d" (`len`)
    : "rcx", "r11", "memory"
  """

  if ret < 0:
    return nil

  return pdata

proc channelSend*(cid: int, msg: Message, isBatch: bool = false): int {.discardable.} =
  let syscall = if isBatch: SysChannelSendBatch else: SysChannelSend
  let dataPtr = msg.data
  let dataLen {.codegenDecl: """register $# $# asm("r8")""".} = msg.len

  asm """
    syscall
    : "=a" (`result`)          // rax (return value)
    : "D" (`syscall`),         // rdi (syscall number)
      "S" (`cid`),             // rsi (channel id)
      "d" (`dataPtr`),         // rdx (pointer to buffer)
      "r" (`dataLen`)          // r8  (length of buffer)
    : "rcx", "r11", "memory"
  """

proc channelSendBatch*(cid: int, msgs: openArray[Message]): int {.discardable.} =
  # allocate enough space to hold the batch message itself
  let batchLen = sizeof(int) + msgs.len * sizeof(Message)  # int for count, then messages
  let batchPtr = channelAlloc(cid, batchLen)
  if batchPtr == nil:
    return -1

  # copy the messages metadata to the allocated space
  let batch = cast[ptr MessageBatch](batchPtr)
  batch.count = msgs.len
  for i in 0 ..< msgs.len:
    batch.messages[i].len = msgs[i].len
    batch.messages[i].data = msgs[i].data

  # send the batch message itself
  let msg = Message(len: batchLen, data: batchPtr)
  channelSend(cid, msg, isBatch = true)

proc channelRecv*(cid: int, buf: pointer, len: int): int =
  ## Receive data from a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   buf (in): buffer pointer
  ##   len (in): buffer length
  ##
  ## Returns:
  ##   0 on success
  ##   -1 on error
 
  let bufLen {.codegenDecl: """register $# $# asm("r8")""".} = len

  asm """
    syscall
    : "=a" (`result`)          // rax (return value)
    : "D" (`SysChannelRecv`),   // rdi (syscall number)
      "S" (`cid`),              // rsi (channel id)
      "d" (`buf`),              // rdx (pointer to buffer to store data)
      "r" (`bufLen`)            // r8  (length of buffer)
    : "rcx", "r11", "memory"
  """

  if result < 0:
    logger.info &"recv: error receiving data from channel {cid}: {result}"
    return -1

proc channelRecvAny*(chids: openArray[int], buf: pointer, len: int): int =
  ## Receive data from any channel. The buffer must be large enough to hold
  ## the largest message across all the channels.
  ## 
  ## Arguments:
  ##   chids (in): array of channel ids
  ##   buf (in): buffer pointer
  ##   len (in): buffer length
  ##
  ## Returns:
  ##   0 on success
  ##   -1 on error

  let arrPtr = cast[uint64](chids[0].addr)
  let arrLen = chids.len
  let bufPtr {.codegenDecl: """register $# $# asm("r8")""".} = buf
  let bufLen {.codegenDecl: """register $# $# asm("r9")""".} = len

  asm """
    syscall
    : "=a" (`result`)          // rax (return value)
    : "D" (`SysChannelRecvAny`), // rdi (syscall number)
      "S" (`arrPtr`),            // rsi (pointer to array of channel ids)
      "d" (`arrLen`),            // rdx (number of channel ids)
      "r" (`bufPtr`),            // r8  (pointer to buffer to store data)
      "r" (`bufLen`)             // r9  (length of buffer)
    : "rcx", "r11", "memory"
  """

  if result < 0:
    logger.info &"recvAny: error receiving data from channels {chids}: {result}"
    return -1

proc channelClose*(cid: int): int {.discardable.} =
  ## Close a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ## 
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ##

  asm """
    syscall
    : "=a" (`result`)
    : "D" (`SysChannelClose`), "S" (`cid`)
    : "rcx", "r11", "memory"
  """

################################# Channel API ##################################

proc create*[T](mode: ChannelMode): Channel[T] =
  let cid = channelCreate(mode, sizeof(T))
  if cid < 0:
    raise newException(Exception, &"Failed to create channel in mode {mode}")

  result.id = cid
  result.msgSize = sizeof(T)
  result.mode = mode
  result.alloc = proc (size: int): pointer = channelAlloc(cid, size)

proc open*[T](cid: int, mode: ChannelMode): Channel[T] =
  if channelOpen(cid, mode) < 0:
    raise newException(Exception, &"Failed to open channel {cid} in mode {mode}")

  result.id = cid
  result.msgSize = sizeof(T)
  result.mode = mode
  result.alloc = proc (size: int): pointer = channelAlloc(cid, size)

proc send*[T](ch: Channel[T], data: T): int {.discardable.} =
  ## Send data to a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   data (in): data to send
  ##
  ## Returns:
  ##   0 on success
  ##  -1 on error

  if ch.mode != ChannelMode.Write:
    return -1

  when T is string:
    let fs = buildString(data, ch.alloc)
    let msg = Message(len: sizeof(FString), data: fs.addr)
  else:
    let msg = Message(len: sizeof(T), data: data.addr)

  result = channelSend(ch.id, msg)

proc sendBatch*[T](ch: Channel[T], items: openArray[T]): int {.discardable.} =
  ## Send a batch of messages to a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   msgs (in): messages to send
  ##
  ## Returns:
  ##   0 on success
  ##  -1 on error

  if ch.mode != ChannelMode.Write:
    return -1
    
  var msgs: seq[Message]
  var fstrings: seq[FString]
  when T is string:
    for item in items:
      let fs = buildString(item, ch.alloc)
      fstrings.add(fs)
    msgs = fstrings.mapIt(Message(len: sizeof(FString), data: it.addr))
  else:
    for item in items:
      msgs.add(Message(len: sizeof(T), data: item.addr)) 

  result = channelSendBatch(ch.id, msgs)

proc recv*[T](ch: Channel[T]): Option[T] =
  ## Receive data from a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##
  ## Returns:
  ##   data on success

  if ch.mode != ChannelMode.Read:
    logger.info &"recv: channel {ch.id} is not in read mode"
    return none(T)

  var t: T
  if channelRecv(ch.id, t.addr, sizeof(T)) < 0:
    return none(T)

  when T is string:
    let fs = cast[FString](t)
    return some($fs.str)
  else:
    return some(t)

proc recvAny*[T1, T2](
  ch1: Channel[T1],
  ch2: Channel[T2],
  handler1: proc (data: T1),
  handler2: proc (data: T2),
): int =
  ## Receive data from any channel. The buffer must be large enough to hold
  ## the largest message across all the channels.
  ## 
  ## Arguments:
  ##   ch1 (in): first channel
  ##   ch2 (in): second channel
  ##   handler1 (in): handler for first channel
  ##   handler2 (in): handler for second channel
  ##
  ## Returns:
  ##   data on success

  let maxSize = max(ch1.msgSize, ch2.msgSize)
  var buf: alloc0(maxSize)
  defer: dealloc(buf)

  let chid = channelRecvAny([ch1.id, ch2.id], buf, maxSize)

  if chid < 0:
    return -1

  if chid == ch1.id:
    handler1(cast[ptr T1](buf)[])
  else:
    handler2(cast[ptr T2](buf)[])

  return chid

proc close*[T](ch: Channel[T]) =
  ## Close a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ## 
  ## Returns:
  ##   0 on success
  ##  -1 on error

  channelClose(ch.id)
