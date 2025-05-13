import std/tables

import pmm
import vmdefs

var
  vmObjects: seq[VmObject]

proc nextVmObjectId(): uint64 =
  result = vmObjects.len.uint64

proc getVmObject*(id: uint64): Option[VmObject] =
  if id < vmObjects.len.uint64:
    result = some(vmObjects[id])
  else:
    result = none(VmObject)

proc anonVmObjectPager*(vmobj: PageableVmObject, offset: uint64, npages: uint64): PAddr =
  ## Pager procedure for an anonymous VmObject.
  ##
  ## It simply allocates physical memory for the page(s) and returns the physical address.
  result = pmAlloc(npages)
  var pageIndex = offset div PageSize
  for i in 0 ..< npages:
    vmobj.pageMap[pageIndex] = result +! i * PageSize
    inc(pageIndex)

proc newPinnedVmObject*(paddr: PAddr, size: uint64): PinnedVmObject =
  ## Create a new pinned VmObject.
  result = PinnedVmObject(
    id: nextVmObjectId(),
    size: size,
    paddr: paddr,
  )
  vmObjects.add(result)

proc newAnonymousVmObject*(size: uint64): VmObject =
  ## Create a new anonymous VmObject.
  result = PageableVmObject(
    id: nextVmObjectId(),
    size: size,
    rc: 1,
    pageMap: initTable[uint64, PAddr](),
    pager: anonVmObjectPager,
  )
  vmObjects.add(result)
