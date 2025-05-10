#[
  Virtual memory managemer (VMM)
]#

import std/algorithm

import common/pagetables
import pmm

type
  PhysAlloc* = proc (nframes: uint64): PhysAddr

  VMRegion* = object
    start*: VirtAddr
    npages*: uint64
    flags*: VMRegionFlags

  VMRegionFlag* {.size: sizeof(uint32).} = enum
    Execute = (0, "X")
    Write   = (1, "W")
    Read    = (2, "R")
    _       = 31  # make the flags set 32 bits wide instead of 1 byte
  VMRegionFlags* = set[VMRegionFlag]

  VMAddressSpace* = object
    minAddress*: VirtAddr
    maxAddress*: VirtAddr
    regions*: seq[VMRegion]

  OutOfMemoryError* = object of CatchableError

const
  KernelSpaceMinAddress* = 0xffff800000000000'u64.VirtAddr
  KernelSpaceMaxAddress* = 0xffffffffffffffff'u64.VirtAddr
  UserSpaceMinAddress* = 0x0000000000001000'u64.VirtAddr
  UserSpaceMaxAddress* = 0x00007fffffffffff'u64.VirtAddr

let
  logger = DebugLogger(name: "vmm")

var
  physicalMemoryVirtualBase: uint64
  pmalloc: PhysAlloc
  kspace*: VMAddressSpace
  uspace*: VMAddressSpace
  kpml4*: ptr PML4Table

template `end`*(region: VMRegion): VirtAddr =
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
  kpml4 = getActivePML4()

proc vmAddRegion*(space: var VMAddressSpace, start: VirtAddr, npages: uint64) =
  space.regions.add VMRegion(start: start, npages: npages)

####################################################################################################
# Active PML4 utilities
####################################################################################################

proc p2v*(phys: PhysAddr): VirtAddr
proc getActivePML4*(): ptr PML4Table =
  let cr3 = getCR3()
  result = cast[ptr PML4Table](p2v(cr3.pml4addr))

proc v2p*(virt: VirtAddr): Option[PhysAddr]
proc setActivePML4*(pml4: ptr PML4Table) =
  let cr3 = newCR3(pml4addr = v2p(cast[VirtAddr](pml4)).get)
  setCR3(cr3)

####################################################################################################
# Mapping between virtual and physical addresses
####################################################################################################

proc p2v*(phys: PhysAddr): VirtAddr =
  result = cast[VirtAddr](phys +! physicalMemoryVirtualBase)

proc v2p*(virt: VirtAddr, pml4: ptr PML4Table): Option[PhysAddr] =
  if physicalMemoryVirtualBase == 0:
    # identity mapped
    return some PhysAddr(cast[uint64](virt))

  var pml4Index = (virt.uint64 shr 39) and 0x1FF
  var pdptIndex = (virt.uint64 shr 30) and 0x1FF
  var pdIndex = (virt.uint64 shr 21) and 0x1FF
  var ptIndex = (virt.uint64 shr 12) and 0x1FF

  if pml4[pml4Index].present == 0:
    return none(PhysAddr)

  let pdptPhysAddr = PhysAddr(pml4[pml4Index].physAddress shl 12)
  let pdpt = cast[ptr PDPTable](p2v(pdptPhysAddr))
  if pdpt[pdptIndex].present == 0:
    return none(PhysAddr)

  let pdPhysAddr = PhysAddr(pdpt[pdptIndex].physAddress shl 12)
  let pd = cast[ptr PDTable](p2v(pdPhysAddr))
  if pd[pdIndex].present == 0:
    return none(PhysAddr)

  let ptPhysAddr = PhysAddr(pd[pdIndex].physAddress shl 12)
  let pt = cast[ptr PTable](p2v(ptPhysAddr))
  if pt[ptIndex].present == 0:
    return none(PhysAddr)

  result = some PhysAddr(pt[ptIndex].physAddress shl 12)

proc v2p*(virt: VirtAddr): Option[PhysAddr] =
  v2p(virt, getActivePML4())

####################################################################################################
# Map a single page
####################################################################################################

proc getOrCreateEntry[P, C](parent: ptr P, index: uint64): ptr C =
  var physAddr: PhysAddr
  if parent[index].present == 1:
    physAddr = PhysAddr(parent[index].physAddress shl 12)
  else:
    physAddr = pmalloc(1)
    parent[index].physAddress = physAddr.uint64 shr 12
    parent[index].present = 1
  result = cast[ptr C](p2v(physAddr))

proc mapPage(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
  physAddr: PhysAddr,
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

proc unmapPage*(pml4: ptr PML4Table, virtAddr: VirtAddr) =
  let pml4Index = (virtAddr.uint64 shr 39) and 0x1FF
  let pdptIndex = (virtAddr.uint64 shr 30) and 0x1FF
  let pdIndex = (virtAddr.uint64 shr 21) and 0x1FF
  let ptIndex = (virtAddr.uint64 shr 12) and 0x1FF

  let pml4Entry = pml4[pml4Index]
  if pml4Entry.present == 0:
    return
  let pdpt = cast[ptr PDPTable](p2v(PhysAddr(pml4Entry.physAddress shl 12)))

  let pdptEntry = pdpt[pdptIndex]
  if pdptEntry.present == 0:
    return
  let pd = cast[ptr PDTable](p2v(PhysAddr(pdptEntry.physAddress shl 12)))

  let pdEntry = pd[pdIndex]
  if pdEntry.present == 0:
    return
  let pt = cast[ptr PTable](p2v(PhysAddr(pdEntry.physAddress shl 12)))

  var ptEntry = pt[ptIndex]
  if ptEntry.present == 0:
    return

  ptEntry.present = 0

####################################################################################################
# Map a range of pages
####################################################################################################

proc mapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
  physAddr: PhysAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  for i in 0 ..< pageCount:
    mapPage(pml4, virtAddr +! i * PageSize, physAddr +! i * PageSize, pageAccess, pageMode, noExec)

proc mapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  let physAddr = pmalloc(pageCount)
  mapRegion(pml4, virtAddr, physAddr, pageCount, pageAccess, pageMode, noExec)

proc identityMapRegion*(
  pml4: ptr PML4Table,
  physAddr: PhysAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
) =
  mapRegion(pml4, physAddr.VirtAddr, physAddr, pageCount, pageAccess, pageMode, noExec)

proc unmapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
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
): PhysAddr {.discardable.} =
  result = pmalloc(region.npages)
  mapRegion(pml4, region.start, result, region.npages, pageAccess, pageMode, noExec)


####################################################################################################
# Dump page tables
####################################################################################################

proc sar*(x: uint64, y: int): uint64 {.inline.} =
  asm """
    mov rcx, %1
    sar %0, cl
    : "+r"(`x`)
    : "r"(`y`)
    : "rcx"
  """
  result = x

proc dumpPageTable*(pml4: ptr PML4Table) =
  var virt: VirtAddr
  var phys: PhysAddr

  virt = cast[VirtAddr](pml4.entries.addr)
  debugln &"PML4: virt = {virt.uint64:#018x}"
  phys = v2p(virt).get
  debugln &"PML4: phys = {phys.uint64:#010x} (virt = {virt.uint64:#018x})"
  for pml4Index in 0 ..< 512.uint64:
    if pml4.entries[pml4Index].present == 1:
      phys = PhysAddr(pml4.entries[pml4Index].physAddress shl 12)
      virt = p2v(phys)
      var pml4mapped = pml4Index.uint64 shl (39 + 16)
      pml4mapped = sar(pml4mapped, 16)
      debugln &"  [{pml4Index:>03}] [{pml4mapped:#018x}]    PDPT: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pml4.entries[pml4Index].user} write={pml4.entries[pml4Index].write} nx={pml4.entries[pml4Index].xd}"
      let pdpt = cast[ptr PDPTable](virt)
      for pdptIndex in 0 ..< 512:
        if pdpt.entries[pdptIndex].present == 1:
          phys = PhysAddr(pdpt.entries[pdptIndex].physAddress shl 12)
          virt = p2v(phys)
          let pdptmapped = pml4mapped or (pdptIndex.uint64 shl 30)
          debugln &"    [{pdptIndex:>03}] [{pdptmapped:#018x}]    PD: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pdpt.entries[pdptIndex].user} write={pdpt.entries[pdptIndex].write} nx={pdpt.entries[pdptIndex].xd}"
          let pd = cast[ptr PDTable](virt)
          for pdIndex in 0 ..< 512:
            if pd.entries[pdIndex].present == 1:
              phys = PhysAddr(pd.entries[pdIndex].physAddress shl 12)
              # debugln &"  ptPhys = {phys.uint64:#010x}"
              virt = p2v(phys)
              # debugln &"  ptVirt = {virt.uint64:#018x}"
              let pdmapped = pdptmapped or (pdIndex.uint64 shl 21)
              debugln &"      [{pdIndex:>03}] [{pdmapped:#018x}]  PT: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pd.entries[pdIndex].user} write={pd.entries[pdIndex].write} nx={pd.entries[pdIndex].xd}"
              let pt = cast[ptr PTable](virt)
              for ptIndex in 0 ..< 512:
                var first = false
                if pt.entries[ptIndex].present == 1:
                  if (ptIndex == 0 or ptIndex == 511 or (pt.entries[ptIndex-1].present == 0) or
                     (pt.entries[ptIndex+1].present == 0) or
                     (pt.entries[ptIndex-1].xd != pt.entries[ptIndex].xd) or
                     (pt.entries[ptIndex+1].xd != pt.entries[ptIndex].xd)
                  ):
                    phys = PhysAddr(pt.entries[ptIndex].physAddress shl 12)
                    # debugln &"  pagePhys = {phys.uint64:#010x}"
                    virt = p2v(phys)
                    # debugln &"  pageVirt = {virt.uint64:#018x}"
                    let ptmapped = pdmapped or (ptIndex.uint64 shl 12)
                    debugln &"        \x1b[1;31m[{ptIndex:>03}] [{ptmapped:#018x}] P: phys = {phys.uint64:#018x}                              user={pt.entries[ptIndex].user} write={pt.entries[ptIndex].write} nx={pt.entries[ptIndex].xd}\x1b[1;0m"
                    if ptIndex == 0 or (pt.entries[ptIndex-1].present == 0) or pt.entries[ptIndex-1].xd != pt.entries[ptIndex].xd:
                      first = true
                  if first and ptIndex < 511 and pt.entries[ptIndex+1].present == 1 and pt.entries[ptIndex+1].xd == pt.entries[ptIndex].xd:
                    debugln "        ..."
                    first = false

# proc printVMRegions*(memoryMap: MemoryMap) =
#   debug &"""   {"Start":>20}"""
#   debug &"""   {"Type":12}"""
#   debug &"""   {"VM Size (KB)":>12}"""
#   debug &"""   {"#Pages":>9}"""
#   debugln ""
#   for i in 0 ..< memoryMap.len:
#     let entry = memoryMap.entries[i]
#     debug &"   {entry.start:>#20x}"
#     debug &"   {entry.type:#12}"
#     debug &"   {entry.nframes * 4:>#12}"
#     debug &"   {entry.nframes:>#9}"
#     debugln ""
