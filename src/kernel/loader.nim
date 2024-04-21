#[
  Task loader for ELF binaries
]#

import std/algorithm

import common/pagetables
import debugcon
import vmm

include elf

type
  LoadedElfImage* = object
    vmRegion*: VMRegion
    entryPoint*: pointer


proc applyRelocations(image: ptr UncheckedArray[byte], dynOffset: uint64)

proc load*(imagePhysAddr: PhysAddr, pml4: ptr PML4Table): LoadedElfImage =
  let imagePtr = cast[ptr byte](p2v(imagePhysAddr))
  let image = initElfImage(imagePtr)

  var dynOffset: int = -1
  for (_, sh) in sections(image):
    if sh.type == ElfSectionType.Dynamic:
      # debugln &"  Dynamic section found at {sh.offset:#x}"
      dynOffset = cast[int](sh.vaddr)

  if dynOffset == -1:
    raise newException(Exception, "No dynamic section found")

  debugln "loader: Program Headers:"
  debugln "  #  type           offset     vaddr    filesz     memsz   flags     align"
  var vmRegions: seq[VMRegion] = @[]
  for (i, ph) in segments(image):
    debug &"  {i}: {ph.type:11}"
    debug &"  {ph.offset:>#8x}"
    debug &"  {ph.vaddr:>#8x}"
    debug &"  {ph.filesz:>#8x}"
    debug &"  {ph.memsz:>#8x}"
    debug &"  {cast[ElfProgramHeaderFlags](ph.flags):>8}"
    debug &"  {ph.align:>#6x}"
    debugln ""
    if ph.type == ElfProgramHeaderType.Load:
      # region in pages
      let region = VMRegion(
        start: VirtAddr(ph.vaddr - (ph.vaddr mod PageSize)),
        npages: (ph.memsz + PageSize - 1) div PageSize,
        flags: cast[VMRegionFlags](ph.flags),
      )
      vmRegions.add(region)

  if vmRegions.len == 0:
    raise newException(Exception, "No loadable segments found")

  if vmRegions[0].start.uint64 != 0:
    raise newException(Exception, "Expecting a PIE binary with a base address of 0")

  # sort regions by start address and calculate total memory size
  vmRegions = vmRegions.sortedByIt(it.start)
  let memSize = vmRegions[^1].end -! vmRegions[0].start
  let pageCount = (memSize + PageSize - 1) div PageSize

  let vmRegion = vmalloc(uspace, pageCount).orRaise(
    newException(Exception, "Failed to allocate memory for the user image")
  )
  debugln &"loader: Allocated {vmRegion.npages} pages at {vmRegion.start.uint64:#x}"

  # adjust regions' start addresses based on vmRegion.start
  for region in vmRegions.mitems:
    region.start = vmRegion.start +! region.start.uint64

  # map each region into the page tables
  var kpml4 = getActivePML4()
  for region in vmRegions:
    let access = if region.flags.contains(Write): paReadWrite else: paRead
    let noExec = not region.flags.contains(Execute)
    let physAddr = vmmap(region, pml4, access, pmUser, noExec)
    debugln &"loader: Mapped {region.npages} pages at vaddr {region.start.uint64:#x}"
    # temporarily map the user image in kernel space so that we can copy the segments and apply relocations
    mapRegion(
      pml4 = kpml4,
      virtAddr = region.start,
      physAddr = physAddr,
      pageCount = region.npages,
      pageAccess = paReadWrite,
      pageMode = pmSupervisor,
      noExec = true,
    )

  # copy loadable segments from the image to the user memory
  for (i, ph) in segments(image):
    if ph.type != ElfProgramHeaderType.Load:
      continue
    let dest = cast[pointer](vmRegion.start +! ph.vaddr)
    let src = cast[pointer](imagePtr +! ph.offset)
    debugln &"loader: Copying segment from offset {ph.offset:#x} to vaddr {cast[uint64](dest):#x} (filesz = {ph.filesz:#x}, memsz = {ph.memsz:#x})"
    copyMem(dest, src, ph.filesz)
    if ph.filesz < ph.memsz:
      zeroMem(cast[pointer](cast[uint64](dest) + ph.filesz), ph.memsz - ph.filesz)

  debugln "loader: Applying relocations to user image"
  applyRelocations(
    image = cast[ptr UncheckedArray[byte]](vmRegion.start),
    dynOffset = cast[uint64](dynOffset),
  )

  # unmap the user image from kernel space
  debugln "loader: Unmapping user image from kernel space"
  for region in vmRegions:
    unmapRegion(kpml4, region.start, region.npages)

  result.vmRegion = vmRegion
  result.entryPoint = cast[pointer](vmRegion.start +! image.header.entry)
  debugln &"loader: Entry point: {cast[uint64](result.entryPoint):#x}"

####################################################################################################
## Relocation
####################################################################################################

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

proc applyRelocations(image: ptr UncheckedArray[byte], dynOffset: uint64) =
  # debugln &"applyRelo: image at {cast[uint64](image):#x}, dynOffset = {dynOffset:#x}"
  ## Apply relocations to the image. Return the entry point address.
  var
    dyn = cast[ptr UncheckedArray[DynamicEntry]](image +! dynOffset)
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
  let rela = cast[ptr UncheckedArray[RelaEntry]](image +! reloffset)
  # debugln &"rela = {cast[uint64](rela):#x}"

  var appliedCount = 0
  for i in 0 ..< relcount:
    let relent = rela[i]
    # debugln &"relent = (.offset = {relent.offset:#x}, .info = {relent.info:#x}, .addend = {relent.addend:#x})"
    if relent.info != RelaEntryType.Relative.uint64:
      # raise newException(Exception, "Only relative relocations are supported.")
      debugln "loader: [WARNING] Only relative relocations are supported."
      continue
    # apply relocation
    let target = cast[ptr uint64](image +! relent.offset)
    let value = cast[uint64](image +! relent.addend)
    # debugln &"target = {cast[uint64](target):#x}, value = {value:#x}"
    target[] = value
    inc appliedCount

  debugln &"loader: Applied {appliedCount} relocations"
