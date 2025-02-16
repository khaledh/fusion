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
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    syscall
    : "=a" (`result`)
    : "r" (`SysChannelOpen`), "r" (`cid`), "r" (`modeVal`)
    : "rdi", "rsi", "rdx"
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
    mov rdi, %1
    mov rsi, %2
    syscall
    : "=a" (`result`)
    : "r" (`SysChannelClose`), "r" (`cid`)
    : "rdi", "rsi"
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
    pdata: pointer
    ret: int

  asm """
    mov rdi, %2
    mov rsi, %3
    mov rdx, %4
    syscall
    mov %1, r8
    : "=a" (`ret`),
      "=r" (`pdata`)
    : "r" (`SysChannelAlloc`), "r" (`cid`), "r" (`len`)
    : "rdi", "rsi", "rdx"
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

  let packedObj = serialize(data, sendAlloc)
  let size = sizeof(packedObj.len) + packedObj.len

  asm """
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    mov r8, %4
    syscall
    : "=a" (`result`)
    : "r" (`SysChannelSend`), "r" (`cid`), "r" (`size`), "m" (`packedObj`)
    : "rdi", "rsi", "rdx", "r8"
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
    packedObj: ptr PackedObj

  asm """
    mov rdi, %3
    mov rsi, %4
    syscall
    mov %1, rdx
    mov %2, r8
    : "=a" (`result`),
      "=r" (`len`), "=r" (`packedObj`)
    : "r" (`SysChannelRecv`), "r" (`cid`)
    : "rdi", "rsi", "rdx", "r8"
  """

  if result < 0:
    return

  data = deserialize(packedObj)
