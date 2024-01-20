import common/[libc, malloc]

proc NimMain() {.importc.}

let
  msg = "Hello from user mode!"
  pmsg = msg.addr

proc UserMain*() {.exportc.} =
  NimMain()

  asm """
    # call print
    mov rdi, 2
    mov rsi, %0
    syscall

    # call exit
    mov rdi, 1
    mov rsi, 0
    syscall
    :
    : "r"(`pmsg`)
    : "rdi", "rsi"
  """
