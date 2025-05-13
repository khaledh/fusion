#[
  Virtual Memory Manager

  Manages the mapping of virtual memory to physical memory through task page tables.
]#

import common/pagetables
import vmdefs, vmpgtbl, vmobject, vmspace, vmm
import task

let
  logger = DebugLogger(name: "vmmgr")

var
  pmBase = 0.Vaddr  ## Base virtual address of physical memory direct map
  kpml4: ptr PML4Table

# Forward declarations
proc kvMapAt*(
  vaddr: VAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
)

proc kvMapAt*(
  vaddr: VAddr,
  paddr: PAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
)

proc vmmgrInit*(
  kernelImageVirtualBase: VAddr,
  kernelImagePhysicalBase: PAddr,
  kernelImagePages: uint64,
  kernelStackVirtualBase: VAddr,
  kernelStackPhysicalBase: PAddr,
  kernelStackPages: uint64,
) =
  # Create the kernel page table
  logger.info "  creating kernel page table"
  kpml4 = newPageTable()
  
  # Map the kernel image
  logger.info "  mapping kernel image"
  kvMapAt(
    vaddr = kernelImageVirtualBase,
    paddr = kernelImagePhysicalBase,
    npages = kernelImagePages,
    perms = {pRead, pWrite, pExecute},
    flags = {vmPinned, vmPrivate},
  )
  # Map the kernel stack
  logger.info "  mapping kernel stack"
  kvMapAt(
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
  kvMapAt(
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

proc kvMapAt*(
  vaddr: VAddr,
  paddr: PAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
) =
  let size = npages * PageSize
  discard vmspace.kvreserve(vaddr, size)  # TODO: store the region
  let vmo = newPinnedVmObject(paddr, size)
  let mapping = VmMapping(
    vaddr: vaddr,
    paddr: some paddr,
    size: size,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pSupervisor,
    flags: flags,
  )
  mapIntoPageTable(kpml4, mapping)

proc kvMapAt*(
  vaddr: VAddr,
  npages: uint64,
  perms: VmPermissions,
  flags: VmMappingFlags,
) =
  let size = npages * PageSize
  discard vmspace.kvreserve(vaddr, size)  # TODO: store the region
  let vmo = newAnonymousVmObject(size)
  mapIntoPageTable(
    kpml4,
    VmMapping(
      vaddr: vaddr,
      size: size,
      vmo: vmo,
      offset: 0,
      permissions: perms,
      privilege: pSupervisor,
      flags: flags,
    )
  )

proc vMap*(task: Task, npages: uint64, perms: VmPermissions) =
  ## Map a new region of memory into a task's address space.
  let size = npages * PageSize
  let vmr = vmspace.uvalloc(npages)
  let vmo = newAnonymousVmObject(size)
  let mapping = VmMapping(
    vaddr: vmr.base,
    size: size,
    vmo: vmo,
    offset: 0,
    permissions: perms,
    privilege: pUser,
    flags: {vmPrivate}
  )
  mapIntoPageTable(task.pml4, mapping)
  task.vmMappings.add(mapping)


proc pageFaultHandler*(task: Task, vaddr: uint64) =
  let pml4 = task.pml4
  # TODO
