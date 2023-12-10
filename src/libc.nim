{.used.}

import std/strutils
import uefi

type
  const_pointer {.importc: "const void *".} = pointer

var
  stdout {.exportc.}: File
  stderr {.exportc.}: File

proc fwrite(buf: const_pointer, size: csize_t, count: csize_t, stream: File): csize_t {.exportc.} =
  let str = $cast[cstring](buf)
  for line in str.splitLines(keepEOL = true):
    consoleOut(line)
    consoleOut("\r")
  return count

proc fflush(stream: File): cint {.exportc.} =
  return 0.cint

proc exit(status: cint) {.exportc, asmNoStackFrame.} =
  asm """
  .loop:
    cli
    hlt
    jmp .loop
  """

proc memchr(buf: const_pointer, c: cint, n: csize_t): pointer {.exportc.} =
  var p = cast[ptr UncheckedArray[cint]](buf)
  for i in 0 ..< n:
    if p[i] == c:
      return addr p[i]
  return nil


# type
#   constCstringImpl {.importc: "const char *".} = cstring
#   constCstring = distinct constCstringImpl


# proc memset*(p: pointer, value: cint, size: csize_t): pointer {.exportc, codeGenDecl: "$# __$#_chk$#".} =
#   let pp = cast[ptr UncheckedArray[byte]](p)
#   let v = cast[byte](value)
#   for i in 0..<size:
#     pp[i] = v
#   return p

# proc memcpy*(dst {.noalias.}: pointer, src {.noalias.}: constPointer, size: csize_t): pointer {.exportc,
#     codeGenDecl: "$# __$#_chk$#".} =
#   # copy 8 bytes at a time
#   let d = cast[ptr UncheckedArray[uint64]](dst)
#   let s = cast[ptr UncheckedArray[uint64]](src)
#   for i in 0 ..< (size.int div sizeof(uint64)):
#     d[i] = s[i]

proc memcpy*(dst {.noalias.}: pointer, src {.noalias.}: constPointer, size: csize_t): pointer {.exportc.} =
  # copy 8 bytes at a time
  let d = cast[ptr UncheckedArray[uint64]](dst)
  let s = cast[ptr UncheckedArray[uint64]](src)
  for i in 0 ..< (size.int div sizeof(uint64)):
    d[i] = s[i]

#   # copy remaining bytes, if any
#   let rem = size and (sizeof(uint64) - 1)
#   if rem > 0:
#     let d = cast[ptr UncheckedArray[byte]](dst)
#     let s = cast[ptr UncheckedArray[byte]](src)
#     for i in (size - rem) ..< size:
#       d[i] = s[i]

#   return dst

# proc memcmp*(lhs: constPointer, rhs: constPointer, count: csize_t): cint
#     {.exportc.} =
#   let l = cast[ptr UncheckedArray[byte]](lhs)
#   let r = cast[ptr UncheckedArray[byte]](rhs)
#   for i in 0..<count:
#     if l[i] != r[i]:
#       return cint(l[i] - r[i])
#   return 0

# proc strlen*(str: constCstring): cint {.exportc.} =
#   let s = cast[ptr UncheckedArray[byte]](str)
#   var len = 0
#   while s[len] != 0:
#     inc(len)
#   result = len.cint

# proc strstr*(str: constCstring, substr: constCstring): cstring
#     {.exportc.} =
#   let s = cast[ptr UncheckedArray[byte]](str)
#   let ss = cast[ptr UncheckedArray[byte]](substr)
#   var i = 0
#   while s[i] != 0:
#     var j = 0
#     while ss[j] != 0 and s[i + j] != 0 and ss[j] == s[i + j]:
#       inc(j)
#     if ss[j] == 0:
#       return cast[cstring](addr s[i])
#     inc(i)
#   return nil

proc chkstk() {.exportc, codeGenDecl: "$# __$#$#".} =
  discard
