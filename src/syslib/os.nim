include syscalldefs

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
