import debugcon
import common/libc
import common/malloc

proc halt() {.inline, asmNoStackFrame.} =
  asm """
  .loop:
    cli
    hlt
    jmp .loop
  """

proc NimMain() {.importc.}

proc KernelMain() {.cdecl, exportc, noreturn.} =
  debugln "kernel: KernelMain"
  NimMain()

  halt()
