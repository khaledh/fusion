#[
  Virtual Memory Manager

  Manages the mapping of virtual memory to physical memory through kernel and task page tables.
]#

import common/pagetables
import vmdefs, vmpagetbl, vmobject, vmspace
import task

let
  logger = DebugLogger(name: "vmmgr")

var
  pmBase = 0.Vaddr  ## Base virtual address of physical memory direct map
  newkpml4*: ptr PML4Table

####################################################################################################
# Forward declarations
####################################################################################################

proc kvMap*(
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping

proc kvMapAt*(
  vaddr: VAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping

proc kvMapAt*(
  vaddr: VAddr,
  paddr: PAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping

proc uvMap*(
  pml4: ptr PML4Table,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping

####################################################################################################
# Initialization
####################################################################################################

proc vmmgrInit*(
  kernelImageVirtualBase: VAddr,
  kernelImagePhysicalBase: PAddr,
  kernelImagePages: uint64,
  kernelStackVirtualBase: VAddr,
  kernelStackPhysicalBase: PAddr,
  kernelStackPages: uint64,
) =
  # Create the kernel page table
  newkpml4 = newPageTable()
  
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

proc createDirectMapping*(
  physMemoryVirtualBase: VAddr,  ## Base address to create the direct map at
  physMemoryPages: uint64,       ## physical memory size in number of pages
) =
  ## Creates a direct mapping of the physical memory at the given virtual address.
  pmBase = physMemoryVirtualBase
  logger.info "  mapping physical memory"
  discard kvMapAt(
    vaddr = physMemoryVirtualBase,
    paddr = 0.PAddr,
    npages = physMemoryPages,
    perms = {pRead, pWrite},
    flags = {vmPinned, vmPrivate},
  )

####################################################################################################
# Active Page Table Utilities
####################################################################################################

proc p2v*(paddr: PAddr): VAddr
proc getActivePageTable*(): ptr PML4Table =
  let cr3 = getCR3()
  result = cast[ptr PML4Table](p2v(cr3.pml4addr))

proc v2p*(vaddr: VAddr): Option[PAddr]
proc setActivePageTable*(pml4: ptr PML4Table) =
  let cr3 = newCR3(pml4addr = v2p(cast[VAddr](pml4)).get)
  setCR3(cr3)

####################################################################################################
# Mapping between virtual and physical addresses
####################################################################################################

proc p2v*(paddr: PAddr): VAddr =
  result = cast[VAddr](pmBase +! paddr.uint64)

proc v2p*(vaddr: VAddr, pml4: ptr PML4Table): Option[PAddr] =
  if pmBase.uint64 == 0:
    # identity mapped
    return some PAddr(cast[uint64](vaddr))

  return translate(vaddr, pml4)

proc v2p*(vaddr: VAddr): Option[PAddr] =
  v2p(vaddr, getActivePageTable())

####################################################################################################
# Map a new region of memory into a task's address space
####################################################################################################

### Kernel mappings

proc kvMap*(
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into the kernel's address space.
  let size = npages * PageSize
  let region = ksAlloc(npages)  # TODO: store the region
  let vmo = newAnonymousVmObject(size)
  let mapping = VmMapping(
    region: region,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(newkpml4, mapping)
  result = mapping

proc kvMapAt*(
  vaddr: VAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into the kernel's address space at the given virtual address.
  let size = npages * PageSize
  let region = ksAllocAt(vaddr, npages)  # TODO: store the region
  let vmo = newAnonymousVmObject(size)
  let mapping = VmMapping(
    region: region,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(newkpml4, mapping)
  result = mapping

proc kvMapAt*(
  vaddr: VAddr,
  paddr: PAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
): VmMapping =
  ## Map a new region of memory into the kernel's address space at the given virtual address to
  ## the given physical address.
  let size = npages * PageSize
  let region = ksAllocAt(vaddr, npages)  # TODO: store the region
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
  mapIntoPageTable(newkpml4, mapping)

### User mappings

proc uvMap*(
  pml4: ptr PML4Table,
  npages: uint64,
  perms: VmPermissions,
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

proc pageFaultHandler*(task: Task, vaddr: uint64) =
  let pml4 = task.pml4
  # TODO
