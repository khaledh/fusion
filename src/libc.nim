{.used.}

import uefi

type
  const_pointer {.importc: "const void *".} = pointer

proc fwrite*(buf: const_pointer, size: csize_t, count: csize_t, stream: File): csize_t {.exportc.} =
  let msg = newWideCString(cast[cstring](buf), size.int * count.int).toWideCString
  discard conOut.outputString(conOut, addr msg[0])
  return count

proc fflush*(stream: File): cint {.exportc.} =
  return 0.cint

var stdout* {.exportc.}: File
var stderr* {.exportc.}: File

proc exit*(status: cint) {.exportc, asmNoStackFrame.} =
  asm """
  .loop:
    cli
    hlt
    jmp .loop
  """
