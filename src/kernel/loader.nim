import std/strformat

import debugcon
import vmm

# Format of user binary image
#   offset       section
#        0       .dynamic
#        x       .data.rel.ro
#        y       .rela.dyn
#        z       .text
#        w       .rodata
#        v       .data

type
  DynamicEntry {.packed.} = object
    tag: uint64
    value: uint64

  DynmaicEntryType = enum
    Rela = 7
    RelaSize = 8
    RelaEntSize = 9
    RelaCount = 0x6ffffff9
  
  RelaEntry {.packed.} = object
    offset: uint64
    info: uint64
    addend: int64

  RelaEntryType = enum
    Relative = 8

proc applyRelocations*(
  image: ptr UncheckedArray[byte],
  dynOffset: uint64
) =
  # debugln &"applyRelo: image at {cast[uint64](image):#x}, dynOffset = {dynOffset:#x}"
  ## Apply relocations to the image. Return the entry point address.
  var
    dyn = cast[ptr UncheckedArray[DynamicEntry]](cast[uint64](image) + dynOffset)
    reloffset = 0'u64
    relsize = 0'u64
    relentsize = 0'u64
    relcount = 0'u64

  var i = 0
  # debugln &"dyn[i].tag = {dyn[i].tag:#x}"
  while dyn[i].tag != 0:
    case dyn[i].tag
    of DynmaicEntryType.Rela.uint64:
      reloffset = dyn[i].value
      # debugln &"reloffset = {reloffset:#x}"
    of DynmaicEntryType.RelaSize.uint64:
      relsize = dyn[i].value
      # debugln &"relsize = {relsize:#x}"
    of DynmaicEntryType.RelaEntSize.uint64:
      relentsize = dyn[i].value
      # debugln &"relentsize = {relentsize:#x}"
    of DynmaicEntryType.RelaCount.uint64:
      relcount = dyn[i].value
      # debugln &"relcount = {relcount:#x}"
    else:
      discard

    inc i

  if reloffset == 0 or relsize == 0 or relentsize == 0 or relcount == 0:
    raise newException(Exception, "Invalid dynamic section. Missing .dynamic information.")

  if relsize != relentsize * relcount:
    raise newException(Exception, "Invalid dynamic section. .rela.dyn size mismatch.")

  # rela points to the first relocation entry
  let rela = cast[ptr UncheckedArray[RelaEntry]](cast[uint64](image) + reloffset.uint64)
  # debugln &"rela = {cast[uint64](rela):#x}"

  for i in 0 ..< relcount:
    let relent = rela[i]
    # debugln &"relent = (.offset = {relent.offset:#x}, .info = {relent.info:#x}, .addend = {relent.addend:#x})"
    if relent.info != RelaEntryType.Relative.uint64:
      # raise newException(Exception, "Only relative relocations are supported.")
      debugln "loader: [WARNING] Only relative relocations are supported."
      continue
    # apply relocation
    let target = cast[ptr uint64](cast[uint64](image) + relent.offset)
    let value = cast[uint64](cast[int64](image) + relent.addend)
    # debugln &"target = {cast[uint64](target):#x}, value = {value:#x}"
    target[] = value
