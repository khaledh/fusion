#[
  OS library functions
]#

include syscalldef

proc getTaskId*(): int =
  asm """
    mov rdi, %1
    syscall
    : "=a" (`result`)
    : "i" (`SysGetTaskId`)
    : "rdi"
  """

proc yld*() =
  asm """
    mov rdi, %0
    syscall
    :
    : "i" (`SysYield`)
    : "rdi"
  """

proc suspend*() =
  asm """
    mov rdi, %0
    syscall
    :
    : "i" (`SysSuspend`)
    : "rdi"
  """

proc sleep*(durationMs: uint64) =
  asm """
    mov rdi, %0
    mov rsi, %1
    syscall
    :
    : "i" (`SysSleep`), "r" (`durationMs`)
    : "rdi", "rsi"
  """

proc exit*(code: int) =
  asm """
    mov rdi, %0
    mov rsi, %1
    syscall
    :
    : "i" (`SysExit`), "r" (`code`)
    : "rdi", "rsi"
  """
