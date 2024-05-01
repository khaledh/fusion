#[
  I/O library functions
]#

include syscalldef

proc print*(pstr: ptr string) =
  asm """
    mov rdi, %0
    mov rsi, %1
    syscall
    :
    : "i" (`SysPrint`), "m" (`pstr`)
    : "rdi", "rsi"
  """
