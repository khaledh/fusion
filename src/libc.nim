{.used.}

import uefi

type
  constPointer {.importc: "const void *".} = pointer
  constCString {.importc: "const char *".} = pointer


proc memset*(p: pointer, value: cint, size: csize_t): pointer {.exportc.} =
  let pp = cast[ptr UncheckedArray[byte]](p)
  let v = cast[byte](value)
  for i in 0..<size:
    pp[i] = v
  return p

proc memcpy*(dest: pointer, src: constPointer, size: csize_t): pointer {.exportc.} =
  let pdest = cast[ptr UncheckedArray[byte]](dest)
  let psrc = cast[ptr UncheckedArray[byte]](src)
  for i in 0 ..< size:
    pdest[i] = psrc[i]
  return dest

proc strlen*(str: constCString): csize_t {.exportc.} =
  let s = cast[ptr UncheckedArray[byte]](str)
  var len = 0
  while s[len] != 0:
    inc len
  result = len.csize_t

proc fwrite*(buf: constPointer, size: csize_t, count: csize_t, stream: File): csize_t {.exportc.} =
  let msg = newWideCString(cast[cstring](buf), size.int * count.int).toWideCString
  discard conOut.outputString(conOut, addr msg[0])
  return count

proc fflush*(stream: File): cint {.exportc.} =
  return 0.cint

proc ferror*(stream: File): cint {.exportc.} =
  return 0.cint

proc strerror(errnum: cint): cstring {.exportc.} =
  return "error".cstring

proc clearerr*(stream: File) {.exportc.} =
  discard

proc errno_location*(): pointer {.exportc, codeGenDecl: "$# __$#$#".} =
  return nil

var stdout* {.exportc.}: File
var stderr* {.exportc.}: File

proc exit*(status: cint) {.exportc, asmNoStackFrame.} =
  asm """
  .loop:
    cli
    hlt
    jmp .loop
  """
