#[
  Channel library functions
]#

include syscalldef

proc send*(chid: int, data: int): int {.discardable.} =
  asm """
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    syscall
    : "=a" (`result`)
    : "i" (`SysChannelSend`), "r" (`chid`), "r" (`data`)
    : "rdi", "rsi", "rdx"
  """

proc recv*(chid: int): int =
  asm """
    mov rdi, %1
    mov rsi, %2
    syscall
    : "=a" (`result`)
    : "i" (`SysChannelRecv`), "r" (`chid`)
    : "rdi", "rsi"
  """
