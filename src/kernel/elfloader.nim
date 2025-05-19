#[
  ELF Loader
]#
import std/[algorithm, sequtils, tables]

import common/pagetables
import elf
import pmm
import vmdefs, vmobject, vmmgr

let
  logger = DebugLogger(name: "elfload")

type
  LoadedElfImage* = object
    base*: VAddr                 ## Base address of the loaded ELF image
    entryPoint*: VAddr           ## Entry point
    reloInfo*: ElfReloInfo       ## Relocation info
    vmMappings*: seq[VmMapping]  ## Mappings of the ELF image segments

  ElfLoadError* = object of CatchableError

# Forward declarations
proc buildReloInfo(elfImage: ElfImage, loadBase: VAddr): ElfReloInfo
proc pageInElfSegment*(vmo: VmObject, offsetInVmo: uint64, npagesToLoad: uint64): PAddr
proc applyReloInPage(vmo: VmObject, offsetInVmo: uint64, paddr: PAddr)

proc convertPermissions(elfFlags: ElfProgramHeaderFlags): VmMappingPermissions =
  if Readable in elfFlags: result.incl pRead
  if Writable in elfFlags: result.incl pWrite
  if Executable in elfFlags: result.incl pExecute

proc loadElfImage*(elfImage: pointer, pml4: ptr PML4Table): LoadedElfImage =
  ## Load an ELF image and return the base address and entry point.
  ##
  ## - Reserves virtual address space for the entire span of loadable segments.
  ## - PT_LOAD segments are mapped into the given page table (marked not present).
  ##   and are loaded lazily on a page-by-page basis when they are accessed (through the
  ##   the page fault handler).

  logger.info &"Loading ELF image (original address: {cast[uint64](elfImage):#x})"

  let elfImage = initElfImage(elfImage)

  # Build a sorted list of loadable segments
  var segs = segments(elfImage).toSeq
    .mapIt(it.ph)
    .filterIt(it.type == ElfProgramHeaderType.Load)
    .sortedByIt(it.vaddr)

  if segs.len == 0:
    raise newException(ElfLoadError, "No loadable segments found in ELF image")

  logger.info &"  Found {segs.len} loadable segments"

  # Prepare a VM mapping layout request containing the segments
  let layoutItems = collect(newSeqOfCap(segs.len)):
    for i, seg in segs:
      let start = roundDownToPage(seg.vaddr)
      let size = roundUpToPage(seg.vaddr + seg.memsz) - start
      let perms = convertPermissions(seg.flags)
      let vmo = newElfSegmentVmObject(
        image = elfImage,
        ph = seg,
        size = size,
        pager = pageInElfSegment,
      )
      VmMappingLayoutItem(
        start: start.VAddr,
        size: size,
        permissions: perms,
        vmo: vmo,
        offset: 0,
      )

  logger.info "  Requesting VM space"
  let layoutRequest = VmMappingLayoutRequest(items: layoutItems)

  # Map the entire layout of segments into the PML4 table
  logger.info "  Mapping segments into page table"
  let mappingResult = uvMapLayout(pml4, layoutRequest)

  if mappingResult.isLeft:
    raise newException(ElfLoadError, &"uvMapLayout failed: {mappingResult.left}")

  let mappings = mappingResult.right

  # Build the relocation table
  let reloInfo = buildReloInfo(elfImage, mappings[0].region.start)

  # Go back and set the reloInfo on the vmo objects
  for mapping in mappings:
    if mapping.vmo.kind == vmObjectElfSegment:
      mapping.vmo.relo = reloInfo

  result = LoadedElfImage(
    base: mappings[0].region.start,
    entryPoint: mappings[0].region.start +! elfImage.header.entry,
    reloInfo: reloInfo,
    vmMappings: mappings
  )

  # logger.info &"  Loaded ELF image at {result.base.uint64:#x}:"
  # logger.info &"     Entry point {result.entryPoint.uint64:#x}"
  # logger.info &"     VM region mappings: {mappings}"

proc buildReloInfo(elfImage: ElfImage, loadBase: VAddr): ElfReloInfo =
  ## Build a relocation table for the ELF image.
  ## The table maps page indices to the relocation entries within the page.
  logger.info &"  Building relocation table"

  result.loadBase = loadBase
  result.pageEntries = newTable[uint64, seq[RelaEntry]]()

  var relaDynOffset: uint64 = 0 # vaddr (offset from image base) of .rela.dyn table
  var relaSize: uint64 = 0
  var relaEntSize: uint64 = 0

  for i, ph in segments(elfImage):
    if ph.type != ElfProgramHeaderType.Dynamic:
      continue
    # Found the dynamic segment
    let dyn = cast[ptr UncheckedArray[DynamicEntry]](elfImage.base +! ph.offset)
    logger.info &"  Found dynamic segment"
    var i = 0
    while dyn[i].tag != 0: # DT_NULL
      case dyn[i].tag
      of DynamicEntryType.Rela.uint64: relaDynOffset = dyn[i].value
      of DynamicEntryType.RelaSize.uint64: relaSize = dyn[i].value
      of DynamicEntryType.RelaEntSize.uint64: relaEntSize = dyn[i].value
      else: discard
      inc i
    break

  if relaDynOffset == 0:
    logger.info "  No relocation section found in ELF image."
    return

  if relaSize == 0 and relaEntSize == 0:
    logger.info "  Relocation section found, but no entries."
    return

  logger.info "  Found relocation section"

  if relaEntSize != sizeof(RelaEntry).uint64:
    # Check in case RelaEntry changes for any reason.
    raise newException(ElfLoadError, &"DT_RELAENT size {relaEntSize} does not match sizeof(RelaEntry) {sizeof(RelaEntry)}.")

  let relaDyn = cast[ptr UncheckedArray[RelaEntry]](elfImage.base +! relaDynOffset)
  let relaCount = relaSize div relaEntSize
  logger.info &"  Found relocation table containing {relaCount} entries."

  for i in 0 ..< relaCount:
    let entry = relaDyn[i]
    if entry.info.type != RelType.Relative: # R_X86_64_RELATIVE
      logger.info &"  Unsupported relocation type {entry.info.type} at entry {i}"
      continue
    # entry.offset is the virtual address of the relocation entry
    # the page index will need to be adjusted during applying the relocation to account for the
    # base load address of the image.
    let pageIndex = roundDownToPage(entry.offset) div PageSize
    # add the entry to the list of relocations for this page
    result.pageEntries.mgetOrPut(pageIndex, newSeq[RelaEntry]()).add(entry)

  # print the relocation entries
  # for pageIndex, entries in result.pageEntries.pairs:
  #   logger.info &"  Relocation entries for page index {pageIndex}:"
  #   for entry in entries:
  #     logger.info &"    {entry}"


proc pageInElfSegment*(vmo: VmObject, offsetInVmo: uint64, npagesToLoad: uint64): PAddr =
  ## Page in a page of the ELF image.
  assert vmo.kind == vmObjectElfSegment, "vmo must be of kind vmObjectElfSegment"
  assert offsetInVmo mod PageSize == 0, "offsetInVmo must be page-aligned"
  assert npagesToLoad == 1, "npagesToLoad > 1 is not supported yet"

  # Note: offsetInVmo is relative to segment start offset rounded down to a page start
  # logger.info &"  offsetInVmo: {offsetInVmo:#x}"

  # Calculate the file offset
  let offsetInFile = roundDownToPage(vmo.ph.offset) + offsetInVmo
  # logger.info &"  offsetInFile: {offsetInFile:#x}"

  # Intersect the page range with the actual page contents on file
  let intersection = intersect(
    (offsetInFile, offsetInFile + PageSize),
    (vmo.ph.offset, vmo.ph.offset + vmo.ph.filesz)
  )
  # logger.info &"  intersecting ranges:"
  # logger.info &"    offsetInFile: {offsetInFile:#x} - {offsetInFile + PageSize:#x}"
  # logger.info &"    vmo.ph.offset: {vmo.ph.offset:#x} - {vmo.ph.offset + vmo.ph.filesz:#x}"
  # logger.info &"  intersection: {intersection.left:#x} - {intersection.right:#x}"

  # The intersection is the range of bytes to copy from the ELF image
  let bytesToCopy = intersection.right - intersection.left

  # Allocate a physical page (the page is zero-filled by default)
  # logger.info &"  Allocating physical page"
  let paddr = pmAlloc(1)

  # Copy the data from the ELF image to the physical page (if needed)
  if bytesToCopy > 0:
    let vaddr = p2v(paddr)  # kernel virtual address of physical page
    let src = cast[VAddr](vmo.image.base) +! intersection.left
    let dst = vaddr +! offsetInPage(intersection.left.VAddr)
    # logger.info &"  Copying {bytesToCopy} bytes from {src.uint64:#x} offset {intersection.left.uint64:#x} to {dst.uint64:#x}"
    copyMem(cast[pointer](dst), cast[pointer](src), bytesToCopy)
    # Apply relocations if needed
    applyReloInPage(vmo, offsetInVmo, paddr)
  else:
    # logger.info &"  No data to copy"
    discard

  result = paddr

proc applyReloInPage(vmo: VmObject, offsetInVmo: uint64, paddr: PAddr) =
  ## Apply relocations in the page.
  assert vmo.kind == vmObjectElfSegment, "vmo must be of kind vmObjectElfSegment"
  assert offsetInVmo mod PageSize == 0, "offsetInVmo must be page-aligned"
  assert vmo.relo.pageEntries != nil, "vmo.reloInfo.pageEntries must be set"

  # logger.info &"  [relo] load base: {vmo.relo.loadBase.uint64:#x}"

  # Get the page index
  let segmentStart = roundDownToPage(vmo.ph.vaddr)
  # logger.info &"  [relo] segmentStart: {segmentStart:#x}"
  let pageVAddr = segmentStart + offsetInVmo
  # logger.info &"  [relo] pageVAddr: {pageVAddr:#x}"
  let pageIndex = pageVAddr div PageSize

  if vmo.relo.pageEntries.hasKey(pageIndex):
    let reloEntries = vmo.relo.pageEntries[pageIndex]
    # logger.info &"  [relo] Applying {reloEntries.len} relocations for page index {pageIndex}"
    for entry in reloEntries:
      let target = vmo.relo.loadBase +! entry.offset
      let targetOffsetInPage = offsetInPage(target)
      # convert to kernel virtual address
      let ktarget = cast[ptr uint64](p2v(paddr +! targetOffsetInPage))
      let relocatedValue = cast[uint64](vmo.relo.loadBase +! entry.addend)
      ktarget[] = relocatedValue

    # logger.info &"  [relo] Finished applying relocations for page index {pageIndex}"
