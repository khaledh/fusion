#[
  I/O library functions
]#

include syscalldef

proc print*(str: string) =
  let pstr = str.addr
  asm """
    syscall
    :
    : "D" (`SysPrint`),
      "S" (`pstr`)
    : "rcx", "r11", "memory"
  """
