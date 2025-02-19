#[
  Task loader for ELF binaries
]#

import std/algorithm

import common/pagetables
import vmm

include elf

type
  LoadedElfImage* = object
    vmRegion*: VMRegion
    entryPoint*: pointer
  
  LoadableSegment = object
    vaddr: VirtAddr
    npages: uint64
    flags: ElfProgramHeaderFlags

  LoaderError* = object of CatchableError


proc applyRelocations(image: ptr UncheckedArray[byte], dynOffset: uint64)

proc load*(imagePtr: pointer, pml4: ptr PML4Table): LoadedElfImage =
  let image = initElfImage(imagePtr)

  var dynOffset: int = -1

  # get a list of page-aligned memory regions to be mapped
  var segs: seq[LoadableSegment] = @[]
  for (i, ph) in segments(image):
    if ph.type == ElfProgramHeaderType.Load:
      if ph.align != PageSize:
        raise newException(LoaderError, &"Unsupported alignment {ph.align:#x} for segment {i}")
      let startOffset = ph.vaddr mod PageSize
      let startPage = ph.vaddr - startOffset
      let numPages = (startOffset + ph.memsz + PageSize - 1) div PageSize
      let seg = LoadableSegment(
        vaddr: startPage.VirtAddr,
        npages: numPages,
        flags: ph.flags,
      )
      segs.add(seg)
    elif ph.type == ElfProgramHeaderType.Dynamic:
      # debugln &"  Dynamic segment found at {ph.offset:#x}"
      dynOffset = cast[int](ph.vaddr)

  if segs.len == 0:
    raise newException(LoaderError, "No loadable segments found")

  if segs[0].vaddr.uint64 != 0:
    raise newException(LoaderError, "Expecting a PIE binary with a base address of 0")

  if dynOffset == -1:
    raise newException(LoaderError, "No dynamic section found")

  # calculate total memory size
  segs = segs.sortedByIt(it.vaddr)
  let memSize = (segs[^1].vaddr +! segs[^1].npages * PageSize) -! segs[0].vaddr
  let pageCount = (memSize + PageSize - 1) div PageSize

  # allocate a single contiguous region for the user image
  let taskRegion = vmalloc(uspace, pageCount)
  # debugln &"loader: Allocated {taskRegion.npages} pages at {taskRegion.start.uint64:#x}"

  # adjust the individual regions' start addresses based on taskRegion.start
  for seg in segs.mitems:
    seg.vaddr = taskRegion.start +! seg.vaddr.uint64

  # map each region into the page tables, making sure to set the R/W and NX flags as needed
  # debugln "loader: Mapping user image"
  for seg in segs:
    let region = VMRegion(start: seg.vaddr, npages: seg.npages)
    let access = if Writable in seg.flags: paReadWrite else: paRead
    let noExec = Executable notin seg.flags
    let mappedRegion = vmmap(region, pml4, access, pmUser, noExec)
    # temporarily map the region in kernel space so that we can copy the segments and
    # apply relocations
    mapRegion(
      region = VMRegion(start: seg.vaddr, npages: seg.npages),
      physAddr = mappedRegion.paddr,
      pml4 = kpml4,
      pageAccess = paReadWrite,
      pageMode = pmSupervisor,
      noExec = true,
    )
  defer:
    # unmap the user image from kernel space on exit
    for seg in segs:
      unmapRegion(
        region = VMRegion(start: seg.vaddr, npages: seg.npages),
        pml4 = kpml4,
      )

  # copy loadable segments from the image to the user memory
  # debugln "loader: Copying segments"
  for (i, ph) in segments(image):
    if ph.type != ElfProgramHeaderType.Load:
      continue
    let dest = cast[pointer](taskRegion.start +! ph.vaddr)
    let src = cast[pointer](imagePtr +! ph.offset)
    # debugln &"  Segment {i}: copying {ph.filesz} bytes from {ph.offset:#x} to {ph.vaddr:#x}"
    copyMem(dest, src, ph.filesz)
    if ph.filesz < ph.memsz:
      # debugln &"  Segment {i}: zeroing {ph.memsz - ph.filesz} bytes"
      zeroMem(cast[pointer](cast[uint64](dest) + ph.filesz), ph.memsz - ph.filesz)

  # apply relocations
  # debugln "loader: Applying relocations"
  applyRelocations(
    image = cast[ptr UncheckedArray[byte]](taskRegion.start),
    dynOffset = cast[uint64](dynOffset),
  )

  result = LoadedElfImage(
    vmRegion: taskRegion,
    entryPoint: cast[pointer](taskRegion.start +! image.header.entry)
  )
  # debugln &"loader: Entry point: {cast[uint64](result.entryPoint):#x}"

####################################################################################################
## Relocation
####################################################################################################

type
  DynamicEntry {.packed.} = object
    tag: uint64
    value: uint64

  DynamicEntryType = enum
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
    of DynamicEntryType.Rela.uint64:
      reloffset = dyn[i].value
      # debugln &"reloffset = {reloffset:#x}"
    of DynamicEntryType.RelaSize.uint64:
      relsize = dyn[i].value
      # debugln &"relsize = {relsize:#x}"
    of DynamicEntryType.RelaEntSize.uint64:
      relentsize = dyn[i].value
      # debugln &"relentsize = {relentsize:#x}"
    of DynamicEntryType.RelaCount.uint64:
      relcount = dyn[i].value
      # debugln &"relcount = {relcount:#x}"
    else:
      discard

    inc i

  if reloffset == 0 or relsize == 0 or relentsize == 0 or relcount == 0:
    raise newException(LoaderError, "Invalid dynamic section. Missing .dynamic information.")

  if relsize != relentsize * relcount:
    raise newException(LoaderError, "Invalid dynamic section. .rela.dyn size mismatch.")

  # rela points to the first relocation entry
  let rela = cast[ptr UncheckedArray[RelaEntry]](image +! reloffset)
  # debugln &"rela = {cast[uint64](rela):#x}"

  var appliedCount = 0
  for i in 0 ..< relcount:
    let relent = rela[i]
    # debugln &"relent = (.offset = {relent.offset:#x}, .info = {relent.info:#x}, .addend = {relent.addend:#x})"
    if relent.info != RelaEntryType.Relative.uint64:
      raise newException(
        LoaderError,
        &"Unsupported relocation type {relent.info:#x}. Only R_X86_64_RELATIVE is supported."
      )
    # apply relocation
    let target = cast[ptr uint64](image +! relent.offset)
    let value = cast[uint64](image +! relent.addend)
    # debugln &"target = {cast[uint64](target):#x}, value = {value:#x}"
    target[] = value
    inc appliedCount

  # debugln &"loader: Applied {appliedCount} relocations"
