#[
  Minimal virtual memory manager for the boot loader.
]#

import common/pagetables

let
  logger = DebugLogger(name: "vmm")

type
  PhysAlloc* = proc (nframes: uint64): PAddr

var
  physicalMemoryVirtualBase: uint64
  pmalloc: PhysAlloc

proc vmInit*(physMemoryVirtualBase: uint64, physAlloc: PhysAlloc) =
  physicalMemoryVirtualBase = physMemoryVirtualBase
  pmalloc = physAlloc

####################################################################################################
# Map a single page
####################################################################################################

proc p2v*(phys: PAddr): VAddr =
  result = cast[VAddr](phys +! physicalMemoryVirtualBase)

proc getOrCreateEntry[P, C](parent: ptr P, index: uint64): ptr C =
  var physAddr: PAddr
  if parent[index].present == 1:
    physAddr = PAddr(parent[index].physAddress shl 12)
  else:
    physAddr = pmalloc(1)
    parent[index].physAddress = physAddr.uint64 shr 12
    parent[index].present = 1
  result = cast[ptr C](p2v(physAddr))

proc mapPage(
  pml4: ptr PML4Table,
  virtAddr: VAddr,
  physAddr: PAddr,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  let pml4Index = (virtAddr.uint64 shr 39) and 0x1FF
  let pdptIndex = (virtAddr.uint64 shr 30) and 0x1FF
  let pdIndex = (virtAddr.uint64 shr 21) and 0x1FF
  let ptIndex = (virtAddr.uint64 shr 12) and 0x1FF

  let
    access = cast[uint64](pageAccess)
    mode = cast[uint64](pageMode)
    noExec = cast[uint64](noExec)

  # Page Map Level 4 Table
  pml4[pml4Index].write = access
  pml4[pml4Index].user = mode
  var pdpt = getOrCreateEntry[PML4Table, PDPTable](pml4, pml4Index)

  # Page Directory Pointer Table
  pdpt[pdptIndex].write = access
  pdpt[pdptIndex].user = mode
  var pd = getOrCreateEntry[PDPTable, PDTable](pdpt, pdptIndex)

  # Page Directory
  pd[pdIndex].write = access
  pd[pdIndex].user = mode
  var pt = getOrCreateEntry[PDTable, PTable](pd, pdIndex)

  # Page Table
  pt[ptIndex].physAddress = physAddr.uint64 shr 12
  pt[ptIndex].present = 1
  pt[ptIndex].write = access
  pt[ptIndex].user = mode
  pt[ptIndex].xd = noExec

####################################################################################################
# Map a range of pages
####################################################################################################

proc mapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VAddr,
  physAddr: PAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  for i in 0 ..< pageCount:
    mapPage(pml4, virtAddr +! i * PageSize, physAddr +! i * PageSize, pageAccess, pageMode, noExec)

proc identityMapRegion*(
  pml4: ptr PML4Table,
  physAddr: PAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  mapRegion(pml4, physAddr.VAddr, physAddr, pageCount, pageAccess, pageMode, noExec)
