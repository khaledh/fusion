#[
  Prelude module that gets imported by all other modules (through the --import flag in nim.cfg)
]#

{.used.}

import std/[options, strformat, sequtils, sugar]
export options, strformat, sequtils, sugar

import common/debugcon
export debugcon

template orRaise*[T](opt: Option[T], exc: ref Exception): T =
  if opt.isSome:
    opt.get
  else:
    raise exc


# Virtual address, Physical address, pointers, etc.
type
  VAddr* = distinct uint64
  PAddr* = distinct uint64

const
  KiB* = 1024'u64
  MiB* = KiB * KiB
  GiB* = KiB * MiB

  PageSize* = 4096

# virtual address operations

template `+!`*(p: VAddr, offset: uint64): VAddr = VAddr(cast[uint64](p) + offset)
template `-!`*(p: VAddr, offset: uint64): VAddr = VAddr(cast[uint64](p) - offset)

template `+!`*(p: VAddr, offset: int64): VAddr =
  if offset >= 0:
    VAddr(cast[uint64](p) + offset.uint64)
  else:
    VAddr(cast[uint64](p) - abs(offset).uint64)

template `-!`*(p: VAddr, offset: int64): VAddr =
  if offset < 0:
    VAddr(p.uint64 - abs(offset).uint64)
  else:
    p +! offset.uint64

template `-!`*(p1: VAddr, p2: VAddr): uint64 = p1.uint64 - p2.uint64

template `==`*(a: VAddr, b: VAddr): bool =  a.uint64 == b.uint64
template `<`*(a: VAddr, b: VAddr): bool =  a.uint64 < b.uint64
template `<=`*(a: VAddr, b: VAddr): bool =  a.uint64 <= b.uint64

template `inc`*(v: var VAddr, offset: uint64) = v = v +! offset.uint64
template `dec`*(v: var VAddr, offset: uint64) = v = v -! offset.uint64

# physical address operations

template `+!`*(p: PAddr, offset: uint64): PAddr =
  PAddr(cast[uint64](p) + offset)

template `-!`*(p: PAddr, offset: uint64): PAddr =
  PAddr(cast[uint64](p) - offset)

template `-!`*(p1: PAddr, p2: PAddr): uint64 = p1.uint64 - p2.uint64

template `==`*(p1, p2: PAddr): bool = p1.uint64 == p2.uint64
template `<`*(p1, p2: PAddr): bool = p1.uint64 < p2.uint64
template `-`*(p1, p2: PAddr): uint64 = p1.uint64 - p2.uint64

proc roundDownToPage*(vaddr: uint64): uint64 {.inline.} =
  vaddr and not (PageSize.uint64 - 1)

proc roundUpToPage*(vaddr: uint64): uint64 {.inline.} =
  (vaddr + PageSize.uint64 - 1) and not (PageSize.uint64 - 1)

proc roundDownToPage*(vaddr: VAddr): VAddr {.inline.} =
  roundDownToPage(vaddr.uint64).VAddr

proc roundUpToPage*(vaddr: VAddr): VAddr {.inline.} =
  roundUpToPage(vaddr.uint64).VAddr

proc offsetInPage*(vaddr: VAddr): uint64 {.inline.} =
  vaddr.uint64 and (PageSize.uint64 - 1)


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


# Either type

type
  EitherKind* = enum 
    eLeft
    eRight

  Either*[L, R] = object
    case kind*: EitherKind
    of eLeft: left*: L
    of eRight: right*: R

proc left*[L, R](e: Either[L, R]): L =
  e.left

proc right*[L, R](e: Either[L, R]): R =
  e.right

proc isLeft*[L, R](e: Either[L, R]): bool =
  e.kind == eLeft

proc isRight*[L, R](e: Either[L, R]): bool =
  e.kind == eRight

proc newLeft*[L, R](value: L): Either[L, R] =
  Either[L, R](kind: eLeft, left: value)

proc newRight*[L, R](value: R): Either[L, R] =
  Either[L, R](kind: eRight, right: value)


# Utilities

type
  Span* = tuple[left: uint64, right: uint64]  # closed-open interval

proc intersect*(a, b: Span): Span =
  ## Return the intersection of two spans.
  if a.left > b.right or b.left > a.right:
    return (0, 0)
  else:
    return (max(a.left, b.left), min(a.right, b.right))
