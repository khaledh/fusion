import std/[algorithm, options, strformat]

import common/pagetables
import pmm
import debugcon

{.experimental: "codeReordering".}

type
  VirtAddr* = distinct uint64
  PhysAlloc* = proc (nframes: uint64): Option[PhysAddr]

  VMRegion* = object
    start*: VirtAddr
    npages*: uint64

  VMAddressSpace* = object
    minAddress*: VirtAddr
    maxAddress*: VirtAddr
    regions*: seq[VMRegion]

  # VMAllocType* = enum
  #   AnyAddress
  #   MaxAddress
  #   ExactAddress

const
  KernelSpaceMinAddress* = 0xffff800000000000'u64.VirtAddr
  KernelSpaceMaxAddress* = 0xffffffffffffffff'u64.VirtAddr
  UserSpaceMinAddress* = 0x0000000000001000'u64.VirtAddr
  UserSpaceMaxAddress* = 0x00007fffffffffff'u64.VirtAddr

var
  physicalMemoryVirtualBase: uint64
  pmalloc: PhysAlloc
  kspace* = VMAddressSpace(
    minAddress: KernelSpaceMinAddress,
    maxAddress: KernelSpaceMaxAddress,
    regions: @[],
  )
  uspace* = VMAddressSpace(
    minAddress: UserSpaceMinAddress,
    maxAddress: UserSpaceMaxAddress,
    regions: @[],
  )


template `+!`*(p: VirtAddr, offset: uint64): VirtAddr =
  VirtAddr(cast[uint64](p) + offset)

template `-!`*(p: VirtAddr, offset: uint64): VirtAddr =
  VirtAddr(cast[uint64](p) - offset)

proc `==`*(a: VirtAddr, b: VirtAddr): bool =  cast[uint64](a) == cast[uint64](b)
proc `<`*(a: VirtAddr, b: VirtAddr): bool =  cast[uint64](a) < cast[uint64](b)
proc `<=`*(a: VirtAddr, b: VirtAddr): bool =  cast[uint64](a) <= cast[uint64](b)

proc vmInit*(physMemoryVirtualBase: uint64, physAlloc: PhysAlloc) =
  physicalMemoryVirtualBase = physMemoryVirtualBase
  pmalloc = physAlloc

proc vmAddRegion*(space: var VMAddressSpace, start: VirtAddr, npages: uint64) =
  space.regions.add VMRegion(start: start, npages: npages)

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
    result = none(PhysAddr)
    return
  let pdptPhysAddr = PhysAddr(pml4[pml4Index].physAddress shl 12)
  let pdpt = cast[ptr PDPTable](p2v(pdptPhysAddr))
  if pdpt[pdptIndex].present == 0:
    result = none(PhysAddr)
    return
  let pdPhysAddr = PhysAddr(pdpt[pdptIndex].physAddress shl 12)
  let pd = cast[ptr PDTable](p2v(pdPhysAddr))
  if pd[pdIndex].present == 0:
    result = none(PhysAddr)
    return
  let ptPhysAddr = PhysAddr(pd[pdIndex].physAddress shl 12)
  let pt = cast[ptr PTable](p2v(ptPhysAddr))
  if pt[ptIndex].present == 0:
    result = none(PhysAddr)
    return
  result = some PhysAddr(pt[ptIndex].physAddress shl 12)

proc v2p(virt: VirtAddr): Option[PhysAddr] =
  v2p(virt, getActivePML4())


####################################################################################################
# Active PML4 utilities
####################################################################################################

proc getActivePML4*(): ptr PML4Table =
  var cr3: uint64
  asm """
    mov %0, cr3
    : "=r"(`cr3`)
  """
  result = cast[ptr PML4Table](p2v(cr3.PhysAddr))

proc setActivePML4*(pml4: ptr PML4Table) =
  var cr3 = v2p(cast[VirtAddr](pml4)).get
  asm """
    mov cr3, %0
    :
    : "r"(`cr3`)
  """

####################################################################################################
# Map a single page
####################################################################################################

proc getOrCreateEntry[P, C](parent: ptr P, index: uint64): ptr C =
  var physAddr: PhysAddr
  if parent[index].present == 1:
    physAddr = PhysAddr(parent[index].physAddress shl 12)
  else:
    physAddr = pmalloc(1).get # TODO: handle allocation failure
    parent[index].physAddress = physAddr.uint64 shr 12
    parent[index].present = 1
  result = cast[ptr C](p2v(physAddr))

proc mapPage(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
  physAddr: PhysAddr,
  pageAccess: PageAccess,
  pageMode: PageMode,
) =
  let pml4Index = (virtAddr.uint64 shr 39) and 0x1FF
  let pdptIndex = (virtAddr.uint64 shr 30) and 0x1FF
  let pdIndex = (virtAddr.uint64 shr 21) and 0x1FF
  let ptIndex = (virtAddr.uint64 shr 12) and 0x1FF

  let access = cast[uint64](pageAccess)
  let mode = cast[uint64](pageMode)

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
) =
  for i in 0 ..< pageCount:
    mapPage(pml4, virtAddr +! i * PageSize, physAddr +! i * PageSize, pageAccess, pageMode)

proc identityMapRegion*(
  pml4: ptr PML4Table,
  physAddr: PhysAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
) =
  mapRegion(pml4, physAddr.VirtAddr, physAddr, pageCount, pageAccess, pageMode)


####################################################################################################
# Allocate a range of virtual addresses
####################################################################################################

proc vmalloc*(space: var VMAddressSpace, pageCount: uint64): Option[VMRegion] =
  # find a free region
  var virtAddr: VirtAddr = space.minAddress
  for region in space.regions:
    if virtAddr +! pageCount * PageSize <= region.start:
      break
    virtAddr = region.start +! region.npages * PageSize

  # add the region to the address space, and sort the regions by start address
  let vmRegion = VMRegion(start: virtAddr, npages: pageCount)
  space.regions.add(vmRegion)
  space.regions = space.regions.sortedByIt(it.start)

  result = some vmRegion

proc vmmap*(
  region: VMRegion,
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode
): PhysAddr {.discardable.} =
  let  physAddr = pmalloc(region.npages).get # TODO: handle allocation failure
  mapRegion(pml4, region.start, physAddr, region.npages, pageAccess, pageMode)
  result = physAddr


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
      debugln &"  [{pml4Index:>03}] [{pml4mapped:#018x}]    PDPT: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pml4.entries[pml4Index].user} write={pml4.entries[pml4Index].write}"
      let pdpt = cast[ptr PDPTable](virt)
      for pdptIndex in 0 ..< 512:
        if pdpt.entries[pdptIndex].present == 1:
          phys = PhysAddr(pdpt.entries[pdptIndex].physAddress shl 12)
          virt = p2v(phys)
          let pdptmapped = pml4mapped or (pdptIndex.uint64 shl 30)
          debugln &"    [{pdptIndex:>03}] [{pdptmapped:#018x}]    PD: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pdpt.entries[pdptIndex].user} write={pdpt.entries[pdptIndex].write}"
          let pd = cast[ptr PDTable](virt)
          for pdIndex in 0 ..< 512:
            if pd.entries[pdIndex].present == 1:
              phys = PhysAddr(pd.entries[pdIndex].physAddress shl 12)
              # debugln &"  ptPhys = {phys.uint64:#010x}"
              virt = p2v(phys)
              # debugln &"  ptVirt = {virt.uint64:#018x}"
              let pdmapped = pdptmapped or (pdIndex.uint64 shl 21)
              debugln &"      [{pdIndex:>03}] [{pdmapped:#018x}]  PT: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pd.entries[pdIndex].user} write={pd.entries[pdIndex].write}"
              let pt = cast[ptr PTable](virt)
              for ptIndex in 0 ..< 512:
                var first = false
                if pt.entries[ptIndex].present == 1:
                  if ptIndex == 0 or ptIndex == 511 or (pt.entries[ptIndex-1].present == 0) or (pt.entries[
                      ptIndex+1].present == 0):
                    phys = PhysAddr(pt.entries[ptIndex].physAddress shl 12)
                    # debugln &"  pagePhys = {phys.uint64:#010x}"
                    virt = p2v(phys)
                    # debugln &"  pageVirt = {virt.uint64:#018x}"
                    let ptmapped = pdmapped or (ptIndex.uint64 shl 12)
                    debugln &"        \x1b[1;31m[{ptIndex:>03}] [{ptmapped:#018x}] P: phys = {phys.uint64:#018x}                              user={pt.entries[ptIndex].user} write={pt.entries[ptIndex].write}\x1b[1;0m"
                    if ptIndex == 0 or (pt.entries[ptIndex-1].present == 0):
                      first = true
                  if first and ptIndex < 511 and pt.entries[ptIndex+1].present == 1:
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
