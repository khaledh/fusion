#[
  Channel library functions
]#
import common/serde

include syscalldef

type
  ChannelMode* = enum
    Read
    Write

proc open*(cid: int, mode: ChannelMode): int {.stackTrace: off.} =
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
  let modeVal = mode.int
  asm """
    syscall
    : "=a" (`result`)
    : "D" (`SysChannelOpen`), "S" (`cid`), "d" (`modeVal`)
    : "rcx", "r11", "memory"
  """

proc close*(cid: int): int {.discardable.} =
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

proc alloc*(cid: int, len: int): pointer {.stackTrace: off.} =
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

proc send*[T](cid: int, data: T): int {.discardable.} =
  ## Send data to a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   len (in): data length
  ##   data (in): pointer to data
  ##
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ##

  proc sendAlloc(size: int): pointer =
    result = alloc(cid, size)

  let packedObj {.codegenDecl: """register $# $# asm("r8")""".} = serialize(data, sendAlloc)
  let size = sizeof(packedObj.len) + packedObj.len

  asm """
    syscall
    : "=a" (`result`)         // rax (return value)
    : "D" (`SysChannelSend`), // rdi (syscall number)
      "S" (`cid`),            // rsi (channel id)
      "d" (`size`),           // rdx (size of packed object)
      "r" (`packedObj`)       // r8  (pointer to packed object)
    : "rcx", "r11", "memory"
  """

proc recv*[T](cid: int, data: var T): int =
  ## Receive data from a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ## 
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ## 

  var
    len: int
    packedObj {.codegenDecl: """register $# $# asm("r8")""".}: ptr PackedObj

  asm """
    syscall
    : "=a" (`result`),         // rax (return value)
      "=d" (`len`),            // rdx (length of packed object)
      "=r" (`packedObj`)       // r8  (pointer to packed object)
    : "D" (`SysChannelRecv`),  // rdi (syscall number)
      "S" (`cid`)              // rsi (channel id)
    : "rcx", "r11", "memory"
  """

  if result < 0:
    return

  data = deserialize(packedObj)
