import std/tables

import pmm
import vmdefs
import elf

var
  vmObjects: seq[VmObject]

proc nextVmObjectId(): uint64 =
  result = vmObjects.len.uint64

proc getVmObject*(id: uint64): Option[VmObject] =
  if id < vmObjects.len.uint64:
    result = some(vmObjects[id])
  else:
    result = none(VmObject)

proc anonVmObjectPageIn*(vmobj: VmObject, offset: uint64, npages: uint64): PAddr =
  ## Pager procedure for an anonymous VmObject.
  ##
  ## It simply allocates physical memory for the page(s) and returns the physical address.
  result = pmAlloc(npages)
  var pageIndex = offset div PageSize
  for i in 0 ..< npages:
    vmobj.pageMap[pageIndex] = result +! i * PageSize
    inc(pageIndex)

proc newPinnedVmObject*(paddr: PAddr, size: uint64): VmObject =
  ## Create a new pinned VmObject.
  result = VmObject(
    kind: vmObjectPinned,
    id: nextVmObjectId(),
    size: size,
    paddr: paddr,
  )
  vmObjects.add(result)

proc newAnonymousVmObject*(size: uint64): VmObject =
  ## Create a new anonymous VmObject.
  result = VmObject(
    kind: vmObjectPageable,
    id: nextVmObjectId(),
    size: size,
    rc: 1,
    pageMap: newTable[uint64, PAddr](),
    pager: anonVmObjectPageIn,
  )
  vmObjects.add(result)

proc newPageableVmObject*(size: uint64, pager: VmObjectPagerProc): VmObject =
  ## Create a new pageable VmObject.
  result = VmObject(
    kind: vmObjectPageable,
    id: nextVmObjectId(),
    size: size,
    rc: 1,
    pageMap: newTable[uint64, PAddr](),
    pager: pager,
  )
  vmObjects.add(result)

proc newElfSegmentVmObject*(
  image: ElfImage,
  ph: ptr ElfProgramHeader,
  size: uint64,
  pager: VmObjectPagerProc,
): VmObject =
  ## Create a new VmObject for an ELF segment.
  result = VmObject(
    kind: vmObjectElfSegment,
    id: nextVmObjectId(),
    size: size,
    pageMap: newTable[uint64, PAddr](),
    image: image,
    pager: pager,
    ph: ph,
    rcSeg: 1,
  )
  vmObjects.add(result)
