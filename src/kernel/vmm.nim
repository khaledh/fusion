#[
  Virtual memory managemer (VMM)
]#

import std/algorithm

import common/pagetables
import pmm

type
  PhysAlloc* = proc (nframes: uint64): PAddr

  VMRegion* = object
    start*: VAddr
    npages*: uint64
    flags*: VMRegionFlags

  VMRegionFlag* {.size: sizeof(uint32).} = enum
    Execute = (0, "X")
    Write   = (1, "W")
    Read    = (2, "R")
    _       = 31  # make the flags set 32 bits wide instead of 1 byte
  VMRegionFlags* = set[VMRegionFlag]

  VMAddressSpace* = object
    minAddress*: VAddr
    maxAddress*: VAddr
    regions*: seq[VMRegion]

  OutOfMemoryError* = object of CatchableError

const
  KernelSpaceMinAddress* = 0xffff800000000000'u64.VAddr
  KernelSpaceMaxAddress* = 0xffffffffffffffff'u64.VAddr
  UserSpaceMinAddress* = 0x0000000000001000'u64.VAddr
  UserSpaceMaxAddress* = 0x00007fffffffffff'u64.VAddr

let
  logger = DebugLogger(name: "vmm")

var
  physicalMemoryVirtualBase: uint64
  pmalloc: PhysAlloc
  kspace*: VMAddressSpace
  uspace*: VMAddressSpace
  oldkpml4*: ptr PML4Table

template `end`*(region: VMRegion): VAddr =
  region.start +! region.npages * PageSize

proc getActivePML4*(): ptr PML4Table

proc vmInit*(physMemoryVirtualBase: uint64, physAlloc: PhysAlloc) =
  physicalMemoryVirtualBase = physMemoryVirtualBase
  pmalloc = physAlloc
  kspace = VMAddressSpace(
    minAddress: KernelSpaceMinAddress,
    maxAddress: KernelSpaceMaxAddress,
    regions: @[],
  )
  uspace = VMAddressSpace(
    minAddress: UserSpaceMinAddress,
    maxAddress: UserSpaceMaxAddress,
    regions: @[],
  )
  oldkpml4 = getActivePML4()

proc vmAddRegion*(space: var VMAddressSpace, start: VAddr, npages: uint64) =
  space.regions.add VMRegion(start: start, npages: npages)

####################################################################################################
# Active PML4 utilities
####################################################################################################

proc p2v*(phys: PAddr): VAddr
proc getActivePML4*(): ptr PML4Table =
  let cr3 = getCR3()
  result = cast[ptr PML4Table](p2v(cr3.pml4addr))

proc v2p*(virt: VAddr): Option[PAddr]
proc setActivePML4*(pml4: ptr PML4Table) =
  let cr3 = newCR3(pml4addr = v2p(cast[VAddr](pml4)).get)
  setCR3(cr3)

####################################################################################################
# Mapping between virtual and physical addresses
####################################################################################################

proc p2v*(phys: PAddr): VAddr =
  result = cast[VAddr](phys +! physicalMemoryVirtualBase)

proc v2p*(virt: VAddr, pml4: ptr PML4Table): Option[PAddr] =
  if physicalMemoryVirtualBase == 0:
    # identity mapped
    return some PAddr(cast[uint64](virt))

  var pml4Index = (virt.uint64 shr 39) and 0x1FF
  var pdptIndex = (virt.uint64 shr 30) and 0x1FF
  var pdIndex = (virt.uint64 shr 21) and 0x1FF
  var ptIndex = (virt.uint64 shr 12) and 0x1FF

  if pml4[pml4Index].present == 0:
    return none(PAddr)

  let pdptPhysAddr = PAddr(pml4[pml4Index].physAddress shl 12)
  let pdpt = cast[ptr PDPTable](p2v(pdptPhysAddr))
  if pdpt[pdptIndex].present == 0:
    return none(PAddr)

  let pdPhysAddr = PAddr(pdpt[pdptIndex].physAddress shl 12)
  let pd = cast[ptr PDTable](p2v(pdPhysAddr))
  if pd[pdIndex].present == 0:
    return none(PAddr)

  let ptPhysAddr = PAddr(pd[pdIndex].physAddress shl 12)
  let pt = cast[ptr PTable](p2v(ptPhysAddr))
  if pt[ptIndex].present == 0:
    return none(PAddr)

  let pageOffset = virt.uint64 and 0xfff
  result = some PAddr((pt[ptIndex].physAddress shl 12) + pageOffset)

proc v2p*(virt: VAddr): Option[PAddr] =
  v2p(virt, getActivePML4())

####################################################################################################
# Map a single page
####################################################################################################

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

proc unmapPage*(pml4: ptr PML4Table, virtAddr: VAddr) =
  let pml4Index = (virtAddr.uint64 shr 39) and 0x1FF
  let pdptIndex = (virtAddr.uint64 shr 30) and 0x1FF
  let pdIndex = (virtAddr.uint64 shr 21) and 0x1FF
  let ptIndex = (virtAddr.uint64 shr 12) and 0x1FF

  let pml4Entry = pml4[pml4Index]
  if pml4Entry.present == 0:
    return
  let pdpt = cast[ptr PDPTable](p2v(PAddr(pml4Entry.physAddress shl 12)))

  let pdptEntry = pdpt[pdptIndex]
  if pdptEntry.present == 0:
    return
  let pd = cast[ptr PDTable](p2v(PAddr(pdptEntry.physAddress shl 12)))

  let pdEntry = pd[pdIndex]
  if pdEntry.present == 0:
    return
  let pt = cast[ptr PTable](p2v(PAddr(pdEntry.physAddress shl 12)))

  var ptEntry = pt[ptIndex]
  if ptEntry.present == 0:
    return

  ptEntry.present = 0

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

proc mapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  let physAddr = pmalloc(pageCount)
  mapRegion(pml4, virtAddr, physAddr, pageCount, pageAccess, pageMode, noExec)

proc identityMapRegion*(
  pml4: ptr PML4Table,
  physAddr: PAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  mapRegion(pml4, physAddr.VAddr, physAddr, pageCount, pageAccess, pageMode, noExec)

proc unmapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VAddr,
  pageCount: uint64,
) =
  for i in 0 ..< pageCount:
    unmapPage(pml4, virtAddr +! i * PageSize)

####################################################################################################
# Allocate a range of virtual addresses
####################################################################################################

proc vmalloc*(space: var VMAddressSpace, pageCount: uint64): VMRegion =
  # find a free region
  var minAddr = space.minAddress
  for region in space.regions:
    if minAddr +! pageCount * PageSize <= region.start:
      break
    minAddr = region.end

  if minAddr +! pageCount * PageSize > space.maxAddress:
    raise newException(OutOfMemoryError, "Out of virtual memory")

  # add the region to the address space, and sort the regions by start address
  result = VMRegion(start: minAddr, npages: pageCount)
  space.regions.add(result)
  space.regions = space.regions.sortedByIt(it.start)

proc vmmap*(
  region: VMRegion,
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
): PAddr {.discardable.} =
  result = pmalloc(region.npages)
  mapRegion(pml4, region.start, result, region.npages, pageAccess, pageMode, noExec)
