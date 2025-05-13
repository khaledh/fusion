import std/tables

type
  ######################## VmObject Definitions ########################

  VmObject* = ref object of RootObj
    ## A virtual memory object that can be mapped into a region of virtual memory.
    id*: int                        ## Unique identifier
    size*: uint64                   ## Memory size of the object (page aligned)

  PinnedVmObject* = ref object of VmObject
    ## A VmObject that is pinned in memory.
    paddr*: PAddr

  PageableVmObject* = ref object of VmObject
    ## A virtual memory object backed by a source (anonymous, file, etc.) that can be mapped into
    ## a region of virtual memory, and paged in/out as needed.
    rc*: int                        ## Reference count (how many tasks are using this object)
    pageMap*: Table[uint64, PAddr]  ## Mapping of page indices to physical addresses
    pager*: VmObjectPagerProc       ## Pager procedure for the object

  VmObjectPagerProc* = proc(
    vmobj: VmObject,  ## The VmObject
    offset: uint64,   ## Offset of the page in the VmObject
    npages: uint64,   ## Number of pages to page in (typically 1, but can be more for prefetching)
  ): PAddr
    ## Pager procedure for a VmObject.
    ##
    ## This procedure is called when a page of the VmObject is accessed but not present in memory.
    ## It should load/allocate the page(s) into physical memory and return its physical address.

  ######################## Mapping Definitions ########################

  VmPermission* = enum
    pRead
    pWrite
    pExecute
  VmPermissions* = set[VmPermission]

  VmPrivilege* = enum
    pUser
    pSupervisor

  VmMappingFlag* = enum
    vmPinned         # The page is pinned in memory (non-pageable)
    vmPrivate        # Changes are private to the owner
    vmShared         # Changes are visible to all sharers
  VmMappingFlags* = set[VmMappingFlag]

  VmOsData* = object
    ## This maps to 11 bits in the page table entries (ignored by the MMU)
    ## and can be used by the OS to store any OS-specific data.
    mapped*   {.bitsize:  1.}: uint64  # present=0 and mapped=1 means the page is mapped but not present in memory
    reserved* {.bitsize: 10.}: uint64  # reserved for future use
    dontuse*  {.bitsize: 53.}: uint64  # don't use (we only have 11 bits)

  VmMapping* = object
    ## Describes how a VmObject is mapped into a particular task's address space.
    vaddr*: VAddr                ## The base virtual address of the mapping
    paddr*: Option[PAddr]        ## The base physical address of the mapping (if pre-allocated)
    size*: uint64                ## The size of the mapping

    # The source of data
    vmo*: VmObject               ## Reference to the VmObject being mapped
    offset*: uint64              ## Offset within the VmObject where mapping begins (usually 0)

    # How this task can access this mapping
    permissions*: VmPermissions  ## Read, Write, Execute
    privilege*: VmPrivilege      ## User or Supervisor
    flags*: VmMappingFlags       ## e.g., Shared, CoW
    osdata*: VmOsData            ## OS-specific data for the mapping

proc value*(osdata: VmOsData): uint64 = cast[uint64](osdata)