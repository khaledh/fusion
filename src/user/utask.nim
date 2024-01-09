import common/[libc, malloc]

{.used.}

proc NimMain() {.importc.}

let
  msg = "user: Hello from user mode!"
  pmsg = msg.addr

proc UserMain*() {.exportc, stackTrace: off.} =
  NimMain()

  # do a syscall
  asm """
    mov rdi, 5
    mov rsi, %0
    syscall

  .loop1:
    pause
    jmp .loop1
    :
    : "r"(`pmsg`)
    : "rdi", "rsi"
  """
