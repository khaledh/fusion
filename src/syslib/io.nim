#[
  I/O library functions
]#

include syscalldef

proc print*(str: string) =
  let pstr = str.addr
  asm """
    mov rdi, %0
    mov rsi, %1
    syscall
    :
    : "i" (`SysPrint`), "m" (`pstr`)
    : "rdi", "rsi"
  """
