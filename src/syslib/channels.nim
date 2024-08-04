#[
  Channel library functions
]#
import std/options

include syscalldef
import syslib/io


proc open*(cid: int, mode: int): int {.stackTrace: off.} =
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

  asm """
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    syscall
    : "=a" (`result`)
    : "r" (`SysChannelOpen`), "r" (`cid`), "r" (`mode`)
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
  """

proc send*[T: ptr](cid: int, data: T): int {.discardable.} =
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

  # convert T to len and data
  let len = sizeof(T)

  asm """
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    mov r8, %4
    syscall
    : "=a" (`result`)
    : "r" (`SysChannelSend`), "r" (`cid`), "r" (`len`), "m" (`data`)
  """

proc recv*[T: ptr](cid: int): T =
  ## Receive data from a channel
  ## 
  ## Arguments:
  ##   chid (in): channel id
  ##   len (out): data length
  ##   data (out): pointer to data
  ## 
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ## 

  var
    len: int
    pdata: ptr T
    ret: int

  asm """
    mov rdi, %3
    mov rsi, %4
    syscall
    mov %1, rdx
    mov %2, r8
    : "=a" (`ret`),
      "=r" (`len`), "=r" (`pdata`)
    : "r" (`SysChannelRecv`), "r" (`cid`)
  """

  if ret < 0:
    return nil

  # check if the data length matches the size of T
  if len != sizeof(T):
    return nil

  # convert to T
  result = cast[T](pdata)
