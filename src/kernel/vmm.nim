#[
  Virtual Memory Manager (VMM)

  - The virtual memory manager manages the mapping between virtual and physical memory.
  - Fusion is a single address space kernel. Unlike traditional kernels, it does not have
    a separate address space for each task. Instead, it uses a single address space for
    the entire system.
  - The virtual address space is divided into two halves:
    - the kernel address space (upper half), and
    - the user address space (lower half).
  - Virtual memory for user tasks is allocated from the user address space. Each task
    occupies a disjoint region of the user address space that is protected from other
    tasks. However, tasks can communicate by getting access to shared memory regions
    (usually via the channels IPC).
]#
import std/[algorithm, heapqueue, tables]

import common/[pagetables, segtree]
import pmm

##########################################################################################
# Interface
##########################################################################################

type
  VMRegion* = ref object
    ## A region of virtual memory with a start address and number of pages. A VM region is
    ## contiguous and does not overlap with other regions. VM regions are used to track
    ## allocated virtual memory in an address space.
    start*: VirtAddr
    npages*: uint64

proc cmpRegionSize(a, b: VMRegion): bool {.inline.} =
  a.npages > b.npages

type
  VMAddressSpace* = object
    ## A virtual address space with a minimum (inclusive) and maximum (exclusive) address,
    ## and a list of allocated regions in the address space represented as a segment tree.
    minAddr*: VirtAddr
    maxAddr*: VirtAddr
    # regionTree* = SegmentTree[VMRegion]()
    freeRegions* = initHeapQueue[VMRegion](cmp = cmpRegionSize)

  VMMappedRegion* = object
    ## A mapped region of virtual memory for a specific page table with specific access
    ## flags. Multiple page tables can map the same virtual memory region with different
    ## access flags, but they all share the same memory region.
    start*: VirtAddr
    npages*: uint64
    # paddr*: PhysAddr
    flags*: VMMappedRegionFlags
    pml4*: ptr PML4Table
    swapIn*: SwapIn

  VMMappedRegionFlag* {.size: sizeof(uint32).} = enum
    ## Access flags for a mapped region of virtual memory.
    Execute = (0, "E")
    Write   = (1, "W")
    Read    = (2, "R")
    _       = 31  # make the flags set 32 bits wide instead of 1 byte
  VMMappedRegionFlags* = set[VMMappedRegionFlag]

  CustomPageFlag = enum
    NotMapped = 0
    Mapped = 1

  PhysAlloc* = proc (nframes: Positive): PhysAddr
    ## A proc that allocates physical memory.
  PhysAlias* = proc (paddr: PhysAddr, nframes: Positive)
    ## A proc that aliases a physical memory region (for shared memory).
  SwapIn* = proc (vaddr: VirtAddr): PhysAddr
    ## A proc that swaps in a page from backing storage.

  OutOfMemoryError* = object of CatchableError
    ## Raised when there is not enough virtual memory to allocate a new region in a
    ## specific address space.

proc vmInit*(
  physMemoryVirtualBase: uint64,
  physAlloc: PhysAlloc,
  physAlias: PhysAlias = nil,
  initialRegions: seq[VMRegion] = @[],
) ## Initialize the virtual memory manager.

proc setActivePML4*(pml4: ptr PML4Table)
  ## Changes the active page table to the given one.

proc vmMapRegion*(
  region: VMRegion,
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
  source: Option[VMRegion] = none(VMRegion),
): VMMappedRegion {.discardable.}
  ## Map a range of pages in the given page table structure. The physical memory is
  ## allocated automatically.

proc vmMapRegion*(
  region: VMRegion,
  physAddr: PhysAddr,
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
  source: Option[VMRegion] = none(VMRegion),
): VMMappedRegion {.discardable.} 
  ## Map a range of pages in the given page table structure. The physical memory must be
  ## allocated before calling this function.

proc vmUnmapRegion*(region: VMRegion, pml4: ptr PML4Table)
  ## Unmap a range of pages in the given page table structure.

proc vmAllocRegion*(space: var VMAddressSpace, pageCount: uint64): VMRegion
  ## Allocate a range of virtual memory pages in the given address space.

proc vmFreeRegion*(space: var VMAddressSpace, region: VMMappedRegion, pml4: ptr PML4Table)
  ## Unmap a VM region in the given page table structure.


##########################################################################################
# Implementation
##########################################################################################

type
  UserSpaceRange* = range[0x0000000000001000'u64..0x00007fffffffffff'u64]
  KernelSpaceRange* = range[0xffff800000000000'u64..0xffffffffffffffff'u64]

const
  UserSpaceMinAddr* = UserSpaceRange.low.VirtAddr
  UserSpaceMaxAddr* = UserSpaceRange.high.VirtAddr
  KernelSpaceMinAddr* = KernelSpaceRange.low.VirtAddr
  KernelSpaceMaxAddr* = KernelSpaceRange.high.VirtAddr

let
  logger = DebugLogger(name: "vmm")

template `end`*(region: VMRegion): VirtAddr =
  region.start +! region.npages * PageSize

template left*(region: VMRegion): uint64 =
  region.start.uint64

template right*(region: VMRegion): uint64 =
  region.end.uint64

var
  physicalMemoryVirtualBase: uint64 
    ## The virtual address where physical memory is mapped
  pmalloc: PhysAlloc       ## Allocates physical memory
  pmalias: PhysAlias       ## Aliases a physical memory region
  kspace*: VMAddressSpace  ## The kernel address space (upper half)
  uspace*: VMAddressSpace  ## The user address space (lower half)
  kpml4*: ptr PML4Table    ## The kernel PML4 table

proc getActivePML4*(): ptr PML4Table
proc vmInit*(
  physMemoryVirtualBase: uint64,
  physAlloc: PhysAlloc,
  physAlias: PhysAlias = nil,
  initialRegions: seq[VMRegion] = @[],
) =
  ## Initialize the virtual memory manager.
  physicalMemoryVirtualBase = physMemoryVirtualBase
  pmalloc = physAlloc
  pmalias = physAlias
  kpml4 = getActivePML4()

  kspace = VMAddressSpace(
    minAddr: KernelSpaceMinAddr,
    maxAddr: KernelSpaceMaxAddr,
  )
  # add the initial vm regions to the kernel address space
  for region in initialRegions:
    kspace.regionTree.insert(region)

  uspace = VMAddressSpace(
    minAddr: UserSpaceMinAddr,
    maxAddr: UserSpaceMaxAddr,
  )

  let (uspaceMin, uspaceMax) = (uspace.minAddr.uint64, uspace.maxAddr.uint64)
  let (kspaceMin, kspaceMax) = (kspace.minAddr.uint64, kspace.maxAddr.uint64)
  logger.info &"    user space: {uspaceMin:#018x} - {uspaceMax:#018x}"
  logger.info &"  kernel space: {kspaceMin:#018x} - {kspaceMax:#018x}"
  logger.info &"  physical mem: {physicalMemoryVirtualBase:#018x}"

proc getAddressSpace(vaddr: VirtAddr): var VMAddressSpace =
  ## Returns the address space for the given virtual address.
  if vaddr.uint64 in UserSpaceRange.low..UserSpaceRange.high:
    result = uspace
  elif vaddr.uint64 in KernelSpaceRange.low..KernelSpaceRange.high:
    result = kspace
  else:
    raise newException(ValueError, "Invalid virtual address")

##########################################################################################
# Active PML4 utilities
##########################################################################################

proc p2v*(phys: PhysAddr): VirtAddr
proc getActivePML4*(): ptr PML4Table =
  ## Returns the currently active page table.
  var cr3: uint64
  asm """
    mov %0, cr3
    : "=r"(`cr3`)
  """
  result = cast[ptr PML4Table](p2v(cr3.PhysAddr))

proc v2p*(virt: VirtAddr): Option[PhysAddr]
proc setActivePML4*(pml4: ptr PML4Table) =
  ## Changes the active page table to the given one.
  var cr3 = v2p(cast[VirtAddr](pml4)).get
  asm """
    mov rcx, cr3
    cmp rcx, %0
    jz .done
    mov cr3, %0
  .done:
    :
    : "r"(`cr3`)
    : "rcx"
  """

##########################################################################################
# Mapping between virtual and physical addresses
##########################################################################################

proc getPTEntry(vaddr: VirtAddr, pml4: ptr PML4Table): ptr PTEntry =
  ## Traverses the given page table structure to find the page table entry corresponding
  ## to the given virtual address. Returns `nil` if the virtual address is not mapped.

  var pml4Index = (vaddr.uint64 shr 39) and 0x1FF
  var pdptIndex = (vaddr.uint64 shr 30) and 0x1FF
  var pdIndex = (vaddr.uint64 shr 21) and 0x1FF
  var ptIndex = (vaddr.uint64 shr 12) and 0x1FF

  if pml4[pml4Index].present == 0:
    return nil

  let pdptPhysAddr = PhysAddr(pml4[pml4Index].physAddress shl 12)
  let pdpt = cast[ptr PDPTable](p2v(pdptPhysAddr))
  if pdpt[pdptIndex].present == 0:
    return nil

  let pdPhysAddr = PhysAddr(pdpt[pdptIndex].physAddress shl 12)
  let pd = cast[ptr PDTable](p2v(pdPhysAddr))
  if pd[pdIndex].present == 0:
    return nil

  let ptPhysAddr = PhysAddr(pd[pdIndex].physAddress shl 12)
  let pt = cast[ptr PTable](p2v(ptPhysAddr))
  if pt[ptIndex].kflags != ord(CustomPageFlag.Mapped):
    return nil

  result = addr pt[ptIndex]

proc p2v*(phys: PhysAddr): VirtAddr =
  ## Convert a physical address to a virtual address.
  ##
  ## Note that the same physical address may have multiple virtual addresses mapped to it
  ## by different page tables. This function relies on the fact that the physical memory
  ## is mapped to a known range of virtual memory in the kernel's address space. It is
  ## mainly used by the kernel to manipulate page tables in physical memory.
  result = cast[VirtAddr](phys +! physicalMemoryVirtualBase)

proc v2p*(virt: VirtAddr, pml4: ptr PML4Table): Option[PhysAddr] =
  ## Convert a virtual address to a physical address.
  ##
  if physicalMemoryVirtualBase == 0:
    # identity mapped
    return some PhysAddr(cast[uint64](virt))

  let ptEntry = getPTEntry(virt, pml4)
  if ptEntry.isNil:
    # address is not mapped
    return none(PhysAddr)

  if ptEntry.present == 0:
    # page is not present
    return none(PhysAddr)

  result = some PhysAddr(ptEntry.physAddress shl 12)

proc v2p*(virt: VirtAddr): Option[PhysAddr] =
  ## Convert a virtual address to a physical address using the currently active page
  ## table.
  v2p(virt, getActivePML4())

##########################################################################################
# Map / unmap VM regions
##########################################################################################

proc getOrCreateEntry[P, C](
  parent: ptr P,
  index: uint64
): tuple[p: ptr C, created: bool] =
  var physAddr: PhysAddr

  if parent[index].present == 1:
    physAddr = PhysAddr(parent[index].physAddress shl 12)
    result.created = true
  else:
    physAddr = pmalloc(1)
    parent[index].physAddress = physAddr.uint64 shr 12
    parent[index].present = 1

  result.p = cast[ptr C](p2v(physAddr))

proc vmMapRegionImpl(
  region: VMRegion,
  physAddrOpt: Option[PhysAddr],
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
): VMMappedRegion {.discardable.} =
  ## Map a range of pages in the given page table structure. The physical memory must be
  ## allocated before calling this function.
  let
    access = cast[uint64](pageAccess)
    mode = cast[uint64](pageMode)
    xd = cast[uint64](noExec)

  var vaddr = region.start
  var paddr = physAddrOpt.get(0'u64.PhysAddr)

  # logger.info (
  #   &"mapping {region.npages} pages at {vaddr.uint64:#x} to {paddr.uint64:#x}, " &
  #   &"write={access}, user={mode}, xd={xd}, alias={alias}"
  # )

  var pml4Index, pdptIndex, pdIndex, ptIndex: uint64
  var pdpt: ptr PDPTable
  var pd: ptr PDTable
  var pt: ptr PTable
  var created = false

  for i in 0 ..< region.npages:
    pml4Index = (vaddr.uint64 shr 39) and 0x1FF
    pdptIndex = (vaddr.uint64 shr 30) and 0x1FF
    pdIndex = (vaddr.uint64 shr 21) and 0x1FF
    ptIndex = (vaddr.uint64 shr 12) and 0x1FF

    # Page Map Level 4 Table
    pml4[pml4Index].write = access
    pml4[pml4Index].user = mode

    # Page Directory Pointer Table
    (pdpt, created) = getOrCreateEntry[PML4Table, PDPTable](pml4, pml4Index)
    pdpt[pdptIndex].write = access
    pdpt[pdptIndex].user = mode
    if created:
      # use the ignored bits of the parent to keep track of child entries count
      if pml4[pml4Index].ignored3 < 512:
        inc pml4[pml4Index].ignored3

    # Page Directory
    (pd, created) = getOrCreateEntry[PDPTable, PDTable](pdpt, pdptIndex)
    pd[pdIndex].write = access
    pd[pdIndex].user = mode
    if created:
      # use the ignored bits of the parent to keep track of child entries count
      if pdpt[pdptIndex].ignored3 < 512:
        inc pdpt[pdptIndex].ignored3

    # Page Table
    (pt, created) = getOrCreateEntry[PDTable, PTable](pd, pdIndex)
    pt[ptIndex].write = access
    pt[ptIndex].user = mode
    pt[ptIndex].xd = xd
    pt[ptIndex].kflags = ord(CustomPageFlag.Mapped)
    if created:
      # use the ignored bits of the parent to keep track of child entries count
      if pd[pdIndex].ignored3 < 512:
        inc pd[pdIndex].ignored3
    
    # if we're given a physical address, mark the page as present
    if physAddrOpt.isSome:
      pt[ptIndex].physAddress = paddr.uint64 shr 12
      pt[ptIndex].present = 1
      inc paddr, PageSize

    inc vaddr, PageSize
  
  # map the flags and return the mapped region
  var flags = { VMMappedRegionFlag.Read }
  if pageAccess == paReadWrite:
    flags.incl(VMMappedRegionFlag.Write)
  if not noExec:
    flags.incl(VMMappedRegionFlag.Execute)

  result = VMMappedRegion(
    start: region.start,
    npages: region.npages,
    # paddr: physAddr,
    flags: flags,
    pml4: pml4,
  )

proc vmMapRegion*(
  region: VMRegion,
  physAddr: PhysAddr,
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
  source: Option[VMRegion] = none(VMRegion),
): VMMappedRegion {.discardable.} =
  ## Map a VM region at a specific physical address in the given page table structure.
  ## The physical memory must be allocated before calling this function.
  result = vmMapRegionImpl(
    region, some(physAddr), pml4, pageAccess, pageMode, noExec, source
  )

proc vmMapRegion*(
  region: VMRegion,
  pml4: ptr PML4Table,
  pageAccess: PageAccess,
  pageMode: PageMode,
  noExec: bool = false,
  source: Option[VMRegion] = none(VMRegion),
): VMMappedRegion {.discardable.} =
  ## Map a range of pages in the given page table structure. The physical memory is
  ## allocated automatically.
  # let physAddr = pmalloc(region.npages)
  result = vmMapRegionImpl(
    region, none(PhysAddr), pml4, pageAccess, pageMode, noExec, source
  )

proc vmUnmapRegion*(region: VMRegion, pml4: ptr PML4Table) =
  var virtAddr = region.start

  # logger.info &"unmapping {region.npages} pages at {virtAddr.uint64:#x}"

  var pml4Index, pdptIndex, pdIndex, ptIndex: uint64

  for i in 0 ..< region.npages:
    pml4Index = (virtAddr.uint64 shr 39) and 0x1FF
    pdptIndex = (virtAddr.uint64 shr 30) and 0x1FF
    pdIndex = (virtAddr.uint64 shr 21) and 0x1FF
    ptIndex = (virtAddr.uint64 shr 12) and 0x1FF

    var pml4Entry = pml4[pml4Index]
    if pml4Entry.present == 0:
      continue

    let pdpt = cast[ptr PDPTable](p2v(PhysAddr(pml4Entry.physAddress shl 12)))
    var pdptEntry = pdpt[pdptIndex]
    if pdptEntry.present == 0:
      continue

    let pd = cast[ptr PDTable](p2v(PhysAddr(pdptEntry.physAddress shl 12)))
    var pdEntry = pd[pdIndex]
    if pdEntry.present == 0:
      continue

    let pt = cast[ptr PTable](p2v(PhysAddr(pdEntry.physAddress shl 12)))
    var ptEntry = pt[ptIndex]
    if ptEntry.present == 0:
      continue

    # free the physical page if this is the last mapping
    ptEntry.present = 0
    # pmFree(PhysAddr(ptEntry.physAddress shl 12), 1)

    # walk up the page tables and free the parent if all children are gone

    if pdEntry.ignored3 > 0:
      dec pdEntry.ignored3
      if pdEntry.ignored3 == 0:
        # free the PD entry
        pdEntry.present = 0
        pmFree(PhysAddr(pdEntry.physAddress shl 12), 1)

        if pdptEntry.ignored3 > 0:
          dec pdptEntry.ignored3
          if pdptEntry.ignored3 == 0:
            # free the PDPT entry
            pdptEntry.present = 0
            pmFree(PhysAddr(pdptEntry.physAddress shl 12), 1)

            if pml4Entry.ignored3 > 0:
              dec pml4Entry.ignored3
              if pml4Entry.ignored3 == 0:
                # free the PML4 entry
                pml4Entry.present = 0
                pmFree(PhysAddr(pml4Entry.physAddress shl 12), 1)

    inc virtAddr, PageSize

##########################################################################################
# Allocate and free virtual memory regions
##########################################################################################

proc vmAllocRegion*(space: var VMAddressSpace, pageCount: uint64): VMRegion =
  ## Allocate a range of virtual memory pages in the given address space.

  # find a free region
  var size = pageCount * PageSize
  var minAddr = space.minAddr
  for region in space.regions:
    if minAddr +! size <= region.start:
      break
    minAddr = region.end

  if minAddr +! size > space.maxAddr:
    raise newException(OutOfMemoryError, "Out of virtual memory")


  # insert the region into the address space's region segment tree
  space.regionTree.insert(region)

# proc vmmap*(
#   region: VMRegion,
#   physAddr: PhysAddr,
#   pml4: ptr PML4Table,
#   pageAccess: PageAccess,
#   pageMode: PageMode,
#   noExec: bool = false,
#   alias: bool = true,
# ): VMMappedRegion {.discardable.} =
#   ## Map a VM region at a specific physical address in the given page table structure.

#   # allocate physical memory and map the region
#   vmMapRegion(region, physAddr, pml4, pageAccess, pageMode, noExec, alias = alias)

#   # map the flags and return the mapped region
#   var flags = { VMMappedRegionFlag.Read }
#   if pageAccess == paReadWrite:
#     flags.incl(VMMappedRegionFlag.Write)
#   if not noExec:
#     flags.incl(VMMappedRegionFlag.Execute)

#   result = VMMappedRegion(
#     start: region.start,
#     npages: region.npages,
#     paddr: physAddr,
#     flags: flags,
#     pml4: pml4,
#   )

# proc vmmap*(
#   region: VMRegion,
#   pml4: ptr PML4Table,
#   pageAccess: PageAccess,
#   pageMode: PageMode,
#   noExec: bool = false,
# ): VMMappedRegion {.discardable.} =
#   ## Map a VM region in the given page table structure. Allocates physical memory
#   ## automatically.
#   let paddr = pmalloc(region.npages)
#   result = vmmap(region, paddr, pml4, pageAccess, pageMode, noExec, alias = false)

proc vmFreeRegion*(
  space: var VMAddressSpace,
  region: VMMappedRegion,
  pml4: ptr PML4Table
) =
  ## Unmap a VM region in the given page table structure.
  # logger.info &"freeing {region.npages} pages at {region.start.uint64:#x}"
  
  # delete the region from the address space
  for i in 0 ..< space.regions.len:
    if space.regions[i].start == region.start:
      space.regions.delete(i)
      break

  # unmap the region and free the physical memory
  vmUnmapRegion(VMRegion(start: region.start, npages: region.npages), pml4)
  # pmFree(region.paddr, region.npages)

##########################################################################################
# Page fault handler
##########################################################################################

type
  PFPresent = enum
    NotPresent = 0
    ProtectionViolation = 1
  PFWrite = enum
    Read = 0
    Write = 1
  PFUser = enum
    Kernel = 0
    User = 1
  PFReservedBit = enum
    NotReserved = 0
    Reserved = 1
  PFInstructionFetch = enum
    NotInstruction = 0
    Instruction = 1
  PFProtectionKeyViolation = enum
    PKNoViolation = 0
    PKViolation = 1
  PFShadowStackViolation = enum
    SSNoViolation = 0
    SSViolation = 1
  PFHlat = enum
    HlatNoViolation = 0
    HlatViolation = 1
  PFSgx = enum
    SgxNoViolation = 0
    SgxViolation = 1

  PageFaultErrorCode {.packed.} = object
    present {.bitsize: 1}: PFPresent
    write {.bitsize: 1}: PFWrite
    user {.bitsize: 1}: PFUser
    rsvd {.bitsize: 1}: PFReservedBit
    inst  {.bitsize: 1}: PFInstructionFetch
    pk {.bitsize: 1}: PFProtectionKeyViolation
    ss {.bitsize: 1}: PFShadowStackViolation
    hlat {.bitsize: 1}: PFHlat
    reserved0 {.bitsize: 7}: uint8
    sgx {.bitsize: 1}: PFSgx
    reserved1: uint16

proc handlePageFault*(virtAddr: uint64, errorCode: uint64, pml4: ptr PML4Table): bool =
  ## Handle a page fault. The faulting address is in `virtAddr`, and the error code is in
  ## `errorCode`.
  let pfErrorCode = cast[PageFaultErrorCode](errorCode)
  
  # check if the faulting address is mapped in the current task's page table
  let ptEntry = getPTEntry(cast[VirtAddr](virtAddr), pml4)
  if ptEntry.isNil:
    logger.info &"page fault at {virtAddr.uint64:#x} (error code = {pfErrorCode})"
    logger.info &"page at {virtAddr.uint64:#x} is not mapped"
    return

  # page is mapped but not present; allocate a new page
  # logger.info &"page at {virtAddr.uint64:#x} is not present; allocating a new page"
  let paddr = pmalloc(1)
  ptEntry.physAddress = paddr.uint64 shr 12
  ptEntry.present = 1

  result = true


##########################################################################################
# Dump page tables
##########################################################################################

proc sar(x: uint64, y: int): uint64 {.inline.} =
  ## Perform an arithmetic right shift.
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
