import debug
import libc
import malloc

proc halt() {.inline, asmNoStackFrame.} =
  asm """
  .loop:
    mov rax, 0x5050505050505050
    cli
    hlt
    jmp .loop
  """

proc NimMain() {.importc.}

proc KernelMain() {.cdecl, exportc, noreturn.} =
  debugln "kernel: KernelMain"
  NimMain()

  halt()
