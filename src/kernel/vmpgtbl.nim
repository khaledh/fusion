#[
  Virtual MemoryPage Table Management
]#

import common/pagetables
import pmm
import vmdefs
import vmm  # TODO: remove this

var
  logger = DebugLogger(name: "vmpgtbl")

####################################################################################################
# Page Table Indexing
####################################################################################################

const
  PML44Shift = 39
  PDPShift = 30
  PDShift = 21
  PTShift = 12

type
  PageTableIndex = object
    pml4i: uint64
    pdpi: uint64
    pdi: uint64
    pti: uint64

proc indexToVAddr*(idx: PageTableIndex): VAddr =
  ## Convert a page table index to a virtual address.
  result = VAddr(
    (idx.pml4i shl PML44Shift) or
    (idx.pdpi shl PDPShift) or
    (idx.pdi shl PDShift) or
    (idx.pti shl PTShift)
  )

proc vaddrToIndex*(vaddr: VAddr): PageTableIndex =
  ## Convert a virtual address to a page table index.
  result = PageTableIndex(
    pml4i: (vaddr.uint64 shr PML44Shift) and 0x1ff,
    pdpi: (vaddr.uint64 shr PDPShift) and 0x1ff,
    pdi: (vaddr.uint64 shr PDShift) and 0x1ff,
    pti: (vaddr.uint64 shr PTShift) and 0x1ff
  )

proc nextPML4Entry(idx: var PageTableIndex, vaddr: var VAddr): bool =
  ## Move to the next PML4 entry.
  inc(idx.pml4i)
  if idx.pml4i < 512:
    result = true
  else:
    # end of the PML4 table, stay on the last entry
    idx.pml4i = 511
    result = false

  if result:
    vaddr = indexToVAddr(idx)

proc nextPDPTEntry(idx: var PageTableIndex, vaddr: var VAddr): bool =
  ## Move to the next PDPEntry.
  inc(idx.pdpi)
  if idx.pdpi < 512:
    result = true
  else:
    # end of PDP table, move to next PML4 entry
    idx.pdpi = 0
    result = nextPML4Entry(idx, vaddr)

  if result:
    vaddr = indexToVAddr(idx)

proc nextPDTEntry(idx: var PageTableIndex, vaddr: var VAddr): bool =
  ## Move to the next PDEntry.
  inc(idx.pdi)
  if idx.pdi < 512:
    result = true
  else:
    # end of PD table, move to next PDPEntry
    idx.pdi = 0
    result = nextPDPTEntry(idx, vaddr)

  if result:
    vaddr = indexToVAddr(idx)

proc nextPTEntry(idx: var PageTableIndex, vaddr: var VAddr): bool =
  ## Move to the next PTEntry.
  inc(idx.pti)
  if idx.pti < 512:
    result = true
  else:
    # end of PT table, move to next PDEntry
    idx.pti = 0
    result = nextPDTEntry(idx, vaddr)

  if result:
    vaddr = indexToVAddr(idx)

####################################################################################################
# Page Table Translation
####################################################################################################

proc translate*(vaddr: VAddr, pml4: ptr PML4Table): Option[PAddr] =
  ## Translate a virtual address to a physical address.
  var idx = vaddrToIndex(vaddr)

  let pml4Entry = pml4[idx.pml4i]
  if pml4Entry.present == 0:
    return none(PAddr)

  let pdpt = cast[ptr PDPTable](p2v(pml4Entry.paddr))
  let pdptEntry = pdpt[idx.pdpi]
  if pdptEntry.present == 0:
    return none(PAddr)

  let pd = cast[ptr PDTable](p2v(pdptEntry.paddr))
  let pdEntry = pd[idx.pdi]
  if pdEntry.present == 0:
    return none(PAddr)

  let pt = cast[ptr PTable](p2v(pdEntry.paddr))
  let ptEntry = pt[idx.pti]
  if ptEntry.present == 0:
    return none(PAddr)

  let pageOffset = vaddr.uint64 and 0xfff
  result = some PAddr(ptEntry.paddr +! pageOffset)

####################################################################################################
# Page Table Management
####################################################################################################

proc newPageTable*(): ptr PML4Table =
  ## Create a new page table.
  result = cast[ptr PML4Table](new PML4Table)

proc getOrCreateEntry[T, E](table: ptr T, index: uint64): ptr E =
  ## Lookup an entry in the page table. If the entry is not present, it will be created.
  var paddr: PAddr
  if table[index].present == 1:
    paddr = table[index].paddr
  else:
    paddr = pmAlloc(1)
    table[index].paddr = paddr
    table[index].present = 1
  result = cast[ptr E](p2v(paddr))

proc mapIntoPageTable*(pml4: ptr PML4Table, mapping: VmMapping) =
  ## Update the page table for a given mapping.
  var paddrCurr = mapping.paddr
  var vaddrCurr = mapping.vaddr
  var vaddrEnd = vaddrCurr +! mapping.size

  let
    present: uint64 = if mapping.paddr.isSome: 1 else: 0
    write: uint64 = if pWrite in mapping.permissions: 1 else: 0
    noExec: uint64 = if pExecute in mapping.permissions: 0 else: 1
    user: uint64 = if mapping.privilege == pUser: 1 else: 0
    mapped = VmOsData(mapped: 1)

  # Initialize previous index to an invalid value
  var prevIndex = PageTableIndex(
    pml4i: uint64.high,
    pdpi: uint64.high,
    pdi: uint64.high,
    pti: uint64.high
  )
  var pdpt: ptr PDPTable
  var pd: ptr PDTable
  var pt: ptr PTable

  while vaddrCurr < vaddrEnd:
    let index = vaddrToIndex(vaddrCurr)

    # PML4Entry
    if index.pml4i != prevIndex.pml4i:
      pml4[index.pml4i].write = write
      pml4[index.pml4i].user = user
      pml4[index.pml4i].osdata = mapped.value
      prevIndex.pml4i = index.pml4i

      pdpt = getOrCreateEntry[PML4Table, PDPTable](pml4, index.pml4i)

    # Page Directory Pointer Table
    if index.pdpi != prevIndex.pdpi:
      pdpt[index.pdpi].write = write
      pdpt[index.pdpi].user = user
      pdpt[index.pdpi].osdata = mapped.value
      prevIndex.pdpi = index.pdpi

      pd = getOrCreateEntry[PDPTable, PDTable](pdpt, index.pdpi)

    # Page Directory
    if index.pdi != prevIndex.pdi:
      pd[index.pdi].write = write
      pd[index.pdi].user = user
      pd[index.pdi].osdata = mapped.value
      prevIndex.pdi = index.pdi

      pt = getOrCreateEntry[PDTable, PTable](pd, index.pdi)

    # Page Table
    if index.pti != prevIndex.pti:
      pt[index.pti].present = present
      pt[index.pti].write = write
      pt[index.pti].user = user
      pt[index.pti].xd = noExec
      pt[index.pti].osdata = mapped.value
      prevIndex.pti = index.pti

      if paddrCurr.isSome:
        pt[index.pti].paddr = paddrCurr.get
        inc(paddrCurr.get, PageSize)

    inc(vaddrCurr, PageSize)


proc unmapFromPageTable*(pml4: ptr PML4Table, mapping: VmMapping) =
  ## Remove a mapping from the page table.
  var vaddrCurr = mapping.vaddr
  var vaddrEnd = vaddrCurr +! mapping.size

  while vaddrCurr < vaddrEnd:
    var idx = vaddrToIndex(vaddrCurr)

    # PML4Entry
    let pml4Entry = pml4[idx.pml4i]
    if pml4Entry.present == 0:
      if not nextPML4Entry(idx, vaddrCurr):
        # no more entries, exit early
        break
      else:
        continue

    # PDPT
    let pdpt = cast[ptr PDPTable](p2v(pml4Entry.paddr))
    let pdptEntry = pdpt[idx.pdpi]
    if pdptEntry.present == 0:
      if not nextPDPTEntry(idx, vaddrCurr):
        # no more entries, exit early
        break
      else:
        continue

    # PD
    let pd = cast[ptr PDTable](p2v(pdptEntry.paddr))
    let pdEntry = pd[idx.pdi]
    if pdEntry.present == 0:
      if not nextPDTEntry(idx, vaddrCurr):
        # no more entries, exit early
        break
      else:
        continue

    # PT
    let pt = cast[ptr PTable](p2v(pdEntry.paddr))
    let ptEntry = pt[idx.pti]
    if ptEntry.present == 0:
      if not nextPTEntry(idx, vaddrCurr):
        # no more entries, exit early
        break
      else:
        continue

    # entry is present, unmap it
    zeroMem(ptEntry.addr, sizeof(PTEntry))

    # move to next page
    inc(vaddrCurr, PageSize)
