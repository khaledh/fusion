#[
  Virtual Memory Manager

  Manages the mapping of virtual memory to physical memory through kernel and task page tables.
]#
import std/strutils

import common/pagetables
import pmm
import vmdefs, vmpageflt, vmpagetbl, vmobject, vmspace

let
  logger = DebugLogger(name: "vmmgr")

var
  pmBase = 0.Vaddr  ## Base virtual address of physical memory direct map

####################################################################################################
# Active Page Table Utilities
####################################################################################################

proc getActivePageTable*(): ptr PML4Table =
  ## Get the current active page table.
  let cr3 = getCR3()
  result = cast[ptr PML4Table](p2v(cr3.pml4addr))

proc setActivePageTable*(pml4: ptr PML4Table) =
  ## Set the current active page table.
  let cr3 = newCR3(pml4addr = v2p(cast[VAddr](pml4)).get)
  setCR3(cr3)

####################################################################################################
# Mapping between virtual and physical addresses
####################################################################################################

proc tV2P(vaddr: VAddr, pml4: ptr PML4Table): Option[PAddr] =
  # Convert a virtual address to a physical address using the given page table.
  if pmBase.uint64 == 0:
    # identity mapped
    return some PAddr(cast[uint64](vaddr))

  return translate(vaddr, pml4)

proc kV2P(vaddr: VAddr): Option[PAddr] =
  # Convert a kernel virtual address to a physical address.
  tV2P(vaddr, getActivePageTable())

proc kP2V(paddr: PAddr): VAddr =
  # Convert a physical address to a kernel virtual address.
  result = cast[VAddr](pmBase +! paddr.uint64)

####################################################################################################
# Map a new region of memory into a task's address space
####################################################################################################

### Kernel mappings

proc kvMap*(
  npages: uint64,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into the kernel's address space.
  let size = npages * PageSize
  let region = ksAlloc(npages)
  let paddr = pmAlloc(npages)
  let vmo = newPinnedVmObject(paddr, size)
  let mapping = VmMapping(
    region: region,
    paddr: some paddr,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(kpml4, mapping)
  kvmMappings.add(mapping)
  result = mapping

proc kvMapAt*(
  vaddr: VAddr,
  npages: uint64,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a specific region of virtual memory.
  let size = npages * PageSize
  var region: vmdefs.VmRegion
  if vaddr >= vmspace.kSpace.base:
    region = ksAllocAt(vaddr, npages)
  else:
    region = usAllocAt(vaddr, npages)
  let paddr = pmAlloc(npages)
  let vmo = newPinnedVmObject(paddr, size)
  let mapping = VmMapping(
    region: region,
    paddr: some paddr,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(kpml4, mapping)
  kvmMappings.add(mapping)
  result = mapping

proc kvMapAt*(
  vaddr: VAddr,
  paddr: PAddr,
  npages: uint64,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a specific regin of virtual memory to a specific region of physical memory.
  let size = npages * PageSize
  var region: vmdefs.VmRegion
  if vaddr >= vmspace.kSpace.base:
    region = ksAllocAt(vaddr, npages)
  else:
    region = usAllocAt(vaddr, npages)
  let vmo = newPinnedVmObject(paddr, size)
  let mapping = VmMapping(
    region: region,
    paddr: some paddr,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(kpml4, mapping)
  kvmMappings.add(mapping)
  result = mapping

proc kvMapAt*(
  paddr: PAddr,
  npages: uint64,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a specific region of physical memory into the kernel's address space.
  let size = npages * PageSize
  let region = ksAlloc(npages)
  let vmo = newPinnedVmObject(paddr, size)
  let mapping = VmMapping(
    region: region,
    paddr: some paddr,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(kpml4, mapping)
  kvmMappings.add(mapping)
  result = mapping

proc kvMapShared*(
  mapping: VmMapping,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a shared region of memory into the kernel's address space.
  let mapping = VmMapping(
    region: mapping.region,
    vmo: mapping.vmo,
    offset: mapping.offset,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(kpml4, mapping)
  kvmMappings.add(mapping)
  result = mapping

### User mappings

proc uvMap*(
  pml4: ptr PML4Table,
  npages: uint64,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into a task's address space.
  let size = npages * PageSize
  let vmregion = usAlloc(npages)
  let vmo = newAnonymousVmObject(size)
  let mapping = VmMapping(
    region: vmregion,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pUser,
    flags: flags,
  )
  mapIntoPageTable(pml4, mapping)
  result = mapping

proc uvMapAt*(
    pml4: ptr PML4Table,
    vaddr: VAddr,
    npages: uint64,
    perms: VmMappingPermissions,
    flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into a task's address space at the given virtual address.
  let size = npages * PageSize
  let vmregion = usAllocAt(vaddr, npages)
  let vmo = newAnonymousVmObject(size)
  let mapping = VmMapping(
    region: vmregion,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pUser,
    flags: flags,
  )
  mapIntoPageTable(pml4, mapping)
  result = mapping

proc uvMapAt*(
  pml4: ptr PML4Table,
  vaddr: VAddr,
  paddr: PAddr,
  npages: uint64,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into a task's address space at the given virtual address to
  ## the given physical address.
  let size = npages * PageSize
  let vmregion = usAllocAt(vaddr, npages)
  let vmo = newPinnedVmObject(paddr, size)
  let mapping = VmMapping(
    region: vmregion,
    paddr: some paddr,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pUser,
    flags: flags,
  )
  mapIntoPageTable(pml4, mapping)
  result = mapping

proc uvMapShared*(
  pml4: ptr PML4Table,
  mapping: VmMapping,
  perms: VmMappingPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a shared region of memory into a task's address space.
  inc(mapping.vmo.rc)
  let mapping = VmMapping(
    region: mapping.region,
    vmo: mapping.vmo,
    offset: mapping.offset,
    permissions: perms,
    privilege: pUser,
    flags: flags,
  )
  mapIntoPageTable(pml4, mapping)
  result = mapping

proc uvMapLayout*(pml4: ptr PML4Table, request: VmMappingLayoutRequest): VmMappingLayoutResult =
  ## Map multiple regions of memory into a task's address space.
  # logger.info "  map layout request:"
  # for item in request.items:
  #   logger.info &"    {item.start.uint64:#>016x} - {uint64(item.start +! item.size):#>016x} ({item.size})"

  # Translate the map layout request into a space layout request.
  var spaceLayoutItems = newSeq[VmSpaceLayoutItem](request.items.len)
  for i, item in request.items:
    spaceLayoutItems[i] = VmSpaceLayoutItem(start: item.start, size: item.size)
  let spaceLayoutRequest = VmSpaceLayoutRequest(items: spaceLayoutItems)

  # Allocate the space layout.
  let spaceLayoutResult = usAllocLayout(spaceLayoutRequest)
  if spaceLayoutResult.kind == eLeft:
    return VmMappingLayoutResult(kind: eLeft, left: spaceLayoutResult.left)
  # logger.info "  vm space layout result:"
  # for region in spaceLayoutResult.right:
  #   logger.info &"    {region.start.uint64:#>016x} - {region.end.uint64:#>016x} ({region.size})"

  # Map the individual regions into the page table.
  var mappings = newSeq[VmMapping](request.items.len)
  for i, (item, region) in zip(request.items, spaceLayoutResult.right):
    mappings[i] = VmMapping(
      region: region,
      vmo: item.vmo,
      offset: item.offset,
      permissions: item.permissions,
      privilege: pUser,
      flags: {vmPrivate},
    )
    mapIntoPageTable(pml4, mappings[i])

  # dumpPageTable(pml4, maxVaddr = 0x00007f0000000000'u64.VAddr)
  # Return the layout mapping result.
  result = VmMappingLayoutResult(kind: eRight, right: mappings)

proc uvUnmap*(
  pml4: ptr PML4Table,
  vaddr: VAddr,
  npages: uint64,
): int =
  ## Unmap a region of memory from a task's address space.
  let mapping = VmMapping(
    region: usAllocAt(vaddr, npages),
    vmo: newAnonymousVmObject(npages * PageSize),
    offset: 0,
    permissions: {pRead, pWrite},
    privilege: pUser,
  )
  unmapFromPageTable(pml4, mapping)
  result = 0

####################################################################################################
# Initialization
####################################################################################################

proc createDirectMapping(
  physicalMemoryVirtualBase: VAddr,  ## Base address to create the direct map at
  physicalMemoryPages: uint64,       ## physical memory size in number of pages
) =
  ## Creates a direct mapping of the physical memory at the given virtual address.
  pmBase = physicalMemoryVirtualBase
  logger.info "  mapping physical memory"
  discard kvMapAt(
    vaddr = physicalMemoryVirtualBase,
    paddr = 0.PAddr,
    npages = physicalMemoryPages,
    perms = {pRead, pWrite},
    flags = {vmPinned, vmPrivate},
  )
  # allocate an unmapped buffer above the direct map
  discard ksAlloc(1)

proc vmmgrInit*(
  kernelImageVirtualBase: VAddr,
  kernelImagePhysicalBase: PAddr,
  kernelImagePages: uint64,
  kernelStackVirtualBase: VAddr,
  kernelStackPhysicalBase: PAddr,
  kernelStackPages: uint64,
  physicalMemoryVirtualBase: VAddr,
  physicalMemoryPages: uint64,
) =
  # Initialize v2p/p2v procs
  p2v = kP2V  # physical to kernel virtual
  v2p = kV2P  # virtual to physical (using the active page table)

  # Initialize VmObjects system
  initVmObjects()

  # Create the kernel page table
  kpml4 = newPageTable()

  # Map physical memory
  createDirectMapping(
    physicalMemoryVirtualBase,
    physicalMemoryPages,
  )

  # Map the kernel image
  logger.info "  mapping kernel image and stack"
  discard kvMapAt(
    vaddr = kernelImageVirtualBase,
    paddr = kernelImagePhysicalBase,
    npages = kernelImagePages,
    perms = {pRead, pWrite, pExecute},
    flags = {vmPinned, vmPrivate},
  )

  # Map the kernel stack
  discard kvMapAt(
    vaddr = kernelStackVirtualBase,
    paddr = kernelStackPhysicalBase,
    npages = kernelStackPages,
    perms = {pRead, pWrite},
    flags = {vmPinned, vmPrivate},
  )

  initPageFaultHandler()

  # switch to the new page table
  setActivePageTable(kpml4)


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

const
  BytesPerPTEntry = PageSize
  BytesPerPDEntry = BytesPerPTEntry * 512
  BytesPerPDPTEntry = BytesPerPDEntry * 512
  BytesPerPML4Entry = BytesPerPDPTEntry * 512

template presentOrMapped(entry: PTEntry): bool =
  entry.present == 1 or cast[VmMappingOsData](entry.osdata).mapped == 1

proc dumpPageTable*(
  pml4: ptr PML4Table,
  minVaddr: VAddr = 0x0'u64.VAddr,
  maxVaddr: VAddr = 0x0ffffffffffffffff'u64.VAddr
) =
  var virt: VAddr
  var phys: PAddr

  virt = cast[VAddr](pml4.entries.addr)
  debugln &"PML4: virt = {virt.uint64:#018x}"
  phys = v2p(virt).get
  debugln &"PML4: phys = {phys.uint64:#010x} (virt = {virt.uint64:#018x})"
  for pml4Index in 0 ..< 512.uint64:
    if VAddr(pml4Index * BytesPerPML4Entry) < minVaddr or VAddr(pml4Index * BytesPerPML4Entry) > maxVaddr:
      break
    if pml4.entries[pml4Index].present == 1:
      phys = PAddr(pml4.entries[pml4Index].physAddress shl 12)
      virt = p2v(phys)
      var pml4mapped = pml4Index.uint64 shl (39 + 16)
      pml4mapped = sar(pml4mapped, 16)
      debugln &"  [{pml4Index:>03}] [{pml4mapped:#018x}]    PDPT: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pml4.entries[pml4Index].user} write={pml4.entries[pml4Index].write} nx={pml4.entries[pml4Index].xd} present={pml4.entries[pml4Index].present}"
      let pdpt = cast[ptr PDPTable](virt)
      for pdptIndex in 0 ..< 512:
        if VAddr(pdptIndex * BytesPerPDPTEntry) < minVaddr or VAddr(pdptIndex * BytesPerPDPTEntry) > maxVaddr:
          break
        if pdpt.entries[pdptIndex].present == 1:
          phys = PAddr(pdpt.entries[pdptIndex].physAddress shl 12)
          virt = p2v(phys)
          let pdptmapped = pml4mapped or (pdptIndex.uint64 shl 30)
          debugln &"    [{pdptIndex:>03}] [{pdptmapped:#018x}]    PD: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pdpt.entries[pdptIndex].user} write={pdpt.entries[pdptIndex].write} nx={pdpt.entries[pdptIndex].xd} present={pdpt.entries[pdptIndex].present}"
          let pd = cast[ptr PDTable](virt)
          for pdIndex in 0 ..< 512:
            if VAddr(pdIndex * BytesPerPDEntry) < minVaddr or VAddr(pdIndex * BytesPerPDEntry) > maxVaddr:
              break
            if pd.entries[pdIndex].present == 1:
              phys = PAddr(pd.entries[pdIndex].physAddress shl 12)
              # debugln &"  ptPhys = {phys.uint64:#010x}"
              virt = p2v(phys)
              # debugln &"  ptVirt = {virt.uint64:#018x}"
              let pdmapped = pdptmapped or (pdIndex.uint64 shl 21)
              debugln &"      [{pdIndex:>03}] [{pdmapped:#018x}]  PT: phys = {phys.uint64:#018x} (virt = {virt.uint64:#018x})  user={pd.entries[pdIndex].user} write={pd.entries[pdIndex].write} nx={pd.entries[pdIndex].xd} present={pd.entries[pdIndex].present}"
              let pt = cast[ptr PTable](virt)
              for ptIndex in 0 ..< 512:
                if VAddr(ptIndex * BytesPerPTEntry) < minVaddr or VAddr(ptIndex * BytesPerPTEntry) > maxVaddr:
                  break
                var first = false
                if presentOrMapped(pt.entries[ptIndex]):
                  if (ptIndex == 0 or ptIndex == 511 or (not presentOrMapped(pt.entries[ptIndex])) or
                     (not presentOrMapped(pt.entries[ptIndex+1])) or
                     (pt.entries[ptIndex-1].xd != pt.entries[ptIndex].xd) or
                     (pt.entries[ptIndex+1].xd != pt.entries[ptIndex].xd) or
                     (pt.entries[ptIndex-1].write != pt.entries[ptIndex].write) or
                     (pt.entries[ptIndex+1].write != pt.entries[ptIndex].write)
                  ):
                    phys = PAddr(pt.entries[ptIndex].physAddress shl 12)
                    # debugln &"  pagePhys = {phys.uint64:#010x}"
                    virt = p2v(phys)
                    # debugln &"  pageVirt = {virt.uint64:#018x}"
                    let ptmapped = pdmapped or (ptIndex.uint64 shl 12)
                    debugln &"        \x1b[1;31m[{ptIndex:>03}] [{ptmapped:#018x}] P: phys = {phys.uint64:#018x}                              user={pt.entries[ptIndex].user} write={pt.entries[ptIndex].write} nx={pt.entries[ptIndex].xd} present={pt.entries[ptIndex].present}\x1b[1;0m"
                    if ptIndex == 0 or (not presentOrMapped(pt.entries[ptIndex-1])) or pt.entries[ptIndex-1].xd != pt.entries[ptIndex].xd or
                       pt.entries[ptIndex-1].write != pt.entries[ptIndex].write:
                      first = true
                  if first and ptIndex < 511 and presentOrMapped(pt.entries[ptIndex+1]) and pt.entries[ptIndex+1].xd == pt.entries[ptIndex].xd and
                      pt.entries[ptIndex+1].write == pt.entries[ptIndex].write:
                    debugln "        ..."
                    first = false
