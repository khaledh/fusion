import std/tables

import pmm
import vmdefs

var vmObjectIdCounter = 0

proc nextVmObjectId(): int =
  result = vmObjectIdCounter
  vmObjectIdCounter += 1

proc anonVmObjectPager*(vmobj: VmObject, offset: uint64, npages: uint64): PAddr =
  ## Pager procedure for an anonymous VmObject.
  ##
  ## It simply allocates physical memory for the page(s) and returns the physical address.
  result = pmAlloc(npages)

proc newPinnedVmObject*(paddr: PAddr, size: uint64): PinnedVmObject =
  ## Create a new pinned VmObject.
  result = PinnedVmObject(
    id: nextVmObjectId(),
    size: size,
    paddr: paddr,
  )

proc newAnonymousVmObject*(size: uint64): VmObject =
  ## Create a new anonymous VmObject.
  result = PageableVmObject(
    id: nextVmObjectId(),
    size: size,
    rc: 1,
    pageMap: initTable[uint64, PAddr](),
    pager: anonVmObjectPager,
  )
