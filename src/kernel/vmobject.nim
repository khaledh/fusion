import std/tables

import pmm
import vmdefs
import elf

var
  vmObjects: seq[VmObject]
  elfSegments: TableRef[(PAddr, uint64), VmObject]  # (image base, segment offset) -> VmObject

proc initVmObjects*() =
  vmObjects = newSeq[VmObject]()
  elfSegments = newTable[(PAddr, uint64), VmObject]()

proc cleanupVmObject*(vmo: VmObject) =
  ## Clean up a VmObject when it's no longer needed.
  ## For ELF segments, this will decrement the reference count and remove from the global table if needed.
  case vmo.kind
  of vmObjectElfSegment:
    dec vmo.rcSeg
    if vmo.rcSeg == 0:
      # Remove from global table if it's a read-only segment
      if Readable in vmo.ph.flags and not (Writable in vmo.ph.flags):
        let key = (cast[PAddr](vmo.image.base), vmo.ph.offset)
        elfSegments.del(key)
  else:
    discard

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
  ## For read-only segments, this will reuse an existing VmObject if one exists.
  
  # For read-only segments, check if we already have a VmObject for this segment
  if Readable in ph.flags and not (Writable in ph.flags):
    let key = (cast[PAddr](image.base), ph.offset)
    if elfSegments.hasKey(key):
      let existingVmo = elfSegments[key]
      inc existingVmo.rcSeg  # Increment reference count
      return existingVmo

  # Create new VmObject for writable segments or if no existing one found
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

  # For read-only segments, store in the global table
  if Readable in ph.flags and not (Writable in ph.flags):
    let key = (cast[PAddr](image.base), ph.offset)
    elfSegments[key] = result
