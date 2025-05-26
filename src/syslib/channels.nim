#[
  Channel library functions
]#
import std/[options, strformat]

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
    mode*: ChannelMode
    alloc*: Allocator

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

proc channelSend*(cid: int, len: int, data: pointer): int {.discardable.} =
  let dataLen {.codegenDecl: """register $# $# asm("r8")""".} = len

  asm """
    syscall
    : "=a" (`result`)          // rax (return value)
    : "D" (`SysChannelSend`),  // rdi (syscall number)
      "S" (`cid`),             // rsi (channel id)
      "d" (`data`),            // rdx (pointer to buffer)
      "r" (`dataLen`)          // r8  (length of buffer)
    : "rcx", "r11", "memory"
  """

proc channelRecv*[T](cid: int): Option[T] =
  ## Receive data from a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   buf (in): buffer pointer
  ##   len (in): buffer length
  ##
  ## Returns:
  ##   Some(data) on success
  ##   None on error
 
  var
    ret: int
    msg: T
    msgPtr = msg.addr
    msgLen {.codegenDecl: """register $# $# asm("r8")""".} = sizeof(T)

  asm """
    syscall
    : "=a" (`ret`),            // rax (return value)
    : "D" (`SysChannelRecv`),  // rdi (syscall number)
      "S" (`cid`),             // rsi (channel id)
      "d" (`msgPtr`),          // rdx (pointer to buffer)
      "r" (`msgLen`)           // r8  (length of buffer)
    : "rcx", "r11", "memory"
  """

  if ret < 0:
    logger.info &"recv: error receiving data from channel {cid}: {result}"
    result = none(T)
  else:
    result = some(msg)

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

proc create*[T](mode: ChannelMode, msgSize: int): Channel[T] =
  let cid = channelCreate(mode, msgSize)
  if cid < 0:
    raise newException(Exception, &"Failed to create channel in mode {mode} with msgSize {msgSize}")

  result.id = cid
  result.mode = mode
  result.alloc = proc (size: int): pointer = channelAlloc(cid, size)

proc open*[T](cid: int, mode: ChannelMode): Channel[T] =
  if channelOpen(cid, mode) < 0:
    raise newException(Exception, &"Failed to open channel {cid} in mode {mode}")

  result.id = cid
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

  # check if T is a string
  when T is string:
    let fs = buildString(data, ch.alloc)
    let dataPtr = fs.addr
    let dataLen = sizeof(FString)
  else:
    let dataPtr = data.addr
    let dataLen = sizeof(T)

  result = channelSend(ch.id, dataLen, dataPtr)

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
