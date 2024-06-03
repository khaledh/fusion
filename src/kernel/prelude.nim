#[
  Prelude module that gets imported by all other modules (through the --import flag in nim.cfg)
]#

{.used.}

import std/[options, strformat]
export options, strformat

import debugcon
export debugcon

template orRaise*[T](opt: Option[T], exc: ref Exception): T =
  if opt.isSome:
    opt.get
  else:
    raise exc


# Virtual address, Physical address, pointers, etc.
type
  VirtAddr* = distinct uint64
  PhysAddr* = distinct uint64

const
  PageSize* = 4096

# virtual address operations

template `+!`*(p: VirtAddr, offset: uint64): VirtAddr = VirtAddr(cast[uint64](p) + offset)
template `-!`*(p: VirtAddr, offset: uint64): VirtAddr = VirtAddr(cast[uint64](p) - offset)

template `+!`*(p: VirtAddr, offset: int64): VirtAddr = VirtAddr(cast[uint64](p) + offset)
template `-!`*(p: VirtAddr, offset: int64): VirtAddr =
  if offset < 0:
    VirtAddr(p.uint64 - abs(offset).uint64)
  else:
    p +! offset.uint64

template `-!`*(p1: VirtAddr, p2: VirtAddr): uint64 = p1.uint64 - p2.uint64

template `==`*(a: VirtAddr, b: VirtAddr): bool =  a.uint64 == b.uint64
template `<`*(a: VirtAddr, b: VirtAddr): bool =  a.uint64 < b.uint64
template `<=`*(a: VirtAddr, b: VirtAddr): bool =  a.uint64 <= b.uint64

# physical address operations

template `+!`*(p: PhysAddr, offset: uint64): PhysAddr =
  PhysAddr(cast[uint64](p) + offset)

template `-!`*(p: PhysAddr, offset: uint64): PhysAddr =
  PhysAddr(cast[uint64](p) - offset)

template `-!`*(p1: PhysAddr, p2: PhysAddr): uint64 = p1.uint64 - p2.uint64

template `==`*(p1, p2: PhysAddr): bool = p1.uint64 == p2.uint64
template `<`*(p1, p2: PhysAddr): bool = p1.uint64 < p2.uint64
template `-`*(p1, p2: PhysAddr): uint64 = p1.uint64 - p2.uint64


# pointer operations

template `+!`*[T](p: ptr T, offset: uint64): ptr T =
  cast[ptr T](cast[uint64](p) + offset)

template `-!`*[T](p: ptr T, offset: uint64): ptr T =
  cast[ptr T](cast[uint64](p) - offset)

template `+!`*(p: pointer, offset: uint64): pointer =
  cast[pointer](cast[uint64](p) + offset)

template `-!`*(p: pointer, offset: uint64): pointer =
  cast[pointer](cast[uint64](p) - offset)

template `+!`*[T](p: ptr T, offset: int64): ptr T = cast[ptr T](cast[uint64](p) + offset.uint64)
template `-!`*[T](p: ptr T, offset: int64): ptr T =
  if offset < 0:
    cast[ptr T](cast[uint64](p) - abs(offset).uint64)
  else:
    p +! offset.uint64


# string formatting

proc grouped*(n: SomeInteger): string {.inline.} =
  return $n
  # Format a number with commas using div and mod operations
  # result = $n
  # var i = result.len
  # while i > 3:
  #   result = result[0..i-4] & "," & result[i-3..^1]
  #   i -= 3

proc float2str*(f: float, places: int): string =
  var intPart = int(f)
  var fracPart = f - float(intPart)
  var fracStr = ""
  for i in 0 ..< places:
    fracPart *= 10
    var digit = int(fracPart)
    fracStr.add(chr(digit + ord('0')))
    fracPart -= float(digit)
  result = $intPart & "." & fracStr
