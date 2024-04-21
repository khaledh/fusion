#[
  Fusion kernel OS library functions
]#

include syscalldef

proc yld*() =
  asm """
    mov rdi, %0
    syscall
    :
    : "i" (`SysYield`)
    : "rdi"
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

proc getTaskId*(): int =
  asm """
    mov rdi, %1
    syscall
    : "=a" (`result`)
    : "i" (`SysGetTaskId`)
    : "rdi"
  """
