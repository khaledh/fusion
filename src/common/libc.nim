#[
  Minimal C library implementation for Nim's `any` target.
]#

{.used.}
{.compile: "include/stdio.c".}

type
  const_pointer {.importc: "const void *".} = pointer

proc fwrite(buf: const_pointer, size: csize_t, count: csize_t, stream: File): csize_t {.exportc.} =
  return 0.csize_t

proc fflush(stream: File): cint {.exportc.} =
  return 0.cint

proc exit(status: cint) {.exportc, asmNoStackFrame.} =
  asm """
  .loop:
    cli
    hlt
    jmp .loop
  """

proc memcpy(dest: pointer, source: pointer, size: csize_t) {.exportc.} =
  copyMem(dest, source, size)
