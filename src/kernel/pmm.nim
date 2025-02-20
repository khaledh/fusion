#[
  Physical memory manager (PMM)

  - The physical memory manager uses a free list to keep track of free regions of physical memory.
  - Reserved physical memory regions are excluded from the free list.
  - The free list is a singly linked list of PMNode objects, sorted by the address of the regions.
  - Each PMNode object represents a contiguous region of free physical memory, and is stored at the
    beginning of the region.
  - Free regions are split and merged as needed.

  API
  - `pmInit`: Initialize the physical memory manager.
  - `pmAlloc`: Allocate a contiguous region of physical memory.
  - `pmFree`: Free a contiguous region of physical memory.
]#

import common/bootinfo

const
  FrameSize = 4096

type
  PMNode = object
    ## A node in the physical memory free list.
    nframes: uint64
    next: ptr PMNode

  PMRegion* = object
    ## A region of physical memory.
    start*: PhysAddr
    nframes*: uint64
  
  PageFrame* = object
    ## A page frame in physical memory.
    paddr*: PhysAddr
    rc*: uint16       # reference count

  InvalidRequest* = object of CatchableError
  OutOfPhysicalMemory* = object of CatchableError

let
  logger = DebugLogger(name: "pmm")

var
  head: ptr PMNode                   ## The head of the free list
  maxPhysAddr: PhysAddr              ## The maximum physical address (exclusive)
  physicalMemoryVirtualBase: uint64  ## The virtual base address of the physical memory
  reservedRegions: seq[PMRegion]     ## Reserved regions of physical memory
  pageFrames: seq[PageFrame]         ## Page frames in physical memory

##########################################################################################
# Utility functions
###########################################################################################

proc toPhysAddr(p: ptr PMNode): PhysAddr {.inline.} =
  ## Convert a node pointer (virtual) to a physical address.
  result = PhysAddr(cast[uint64](p) - physicalMemoryVirtualBase)

proc toPMNodePtr(p: PhysAddr): ptr PMNode {.inline.} =
  ## Convert a physical address to a node pointer (virtual).
  result = cast[ptr PMNode](cast[uint64](p) + physicalMemoryVirtualBase)

proc endAddr(paddr: PhysAddr, nframes: uint64): PhysAddr {.inline.} =
  ## Calculate the end address given a physical address and the number of frames.
  result = paddr +! nframes * FrameSize

proc endAddr(region: PMRegion): PhysAddr {.inline.} =
  ## Calculate the end address of a region.
  result = endAddr(region.start, region.nframes)

proc adjacent(node: ptr PMNode, paddr: PhysAddr): bool =
  ## Check if the given node region is adjacent to a physical address.
  result = (
    not node.isNil and
    node.toPhysAddr +! node.nframes * FrameSize == paddr
  )

proc adjacent(paddr: PhysAddr, nframes: uint64, node: ptr PMNode): bool =
  ## Check if the given physical address is adjacent to a node region.
  result = (
    not node.isNil and
    paddr +! nframes * FrameSize == node.toPhysAddr
  )

proc adjacent(region1, region2: PMRegion): bool =
  ## Check if two physical memory regions are adjacent.
  result = (
    region1.endAddr == region2.start or
    region2.endAddr == region1.start
  )

proc overlaps(region1, region2: PMRegion): bool =
  ## Check if two physical memory regions overlap.
  var r1 = region1
  var r2 = region2
  if r1.start > r2.start:
    r1 = region2
    r2 = region1
  result = (
    r1.start < endAddr(r2.start, r2.nframes) and
    r2.start < endAddr(r1.start, r1.nframes)
  )

##########################################################################################
# Initialization
##########################################################################################

proc pmInit*(physMemoryVirtualBase: uint64, memoryMap: MemoryMap) =
  ## Initialize the physical memory manager.
  physicalMemoryVirtualBase = physMemoryVirtualBase

  var prev: ptr PMNode

  for i in 0 ..< memoryMap.len:
    let entry = memoryMap.entries[i]
    if entry.type == MemoryType.Free:
      maxPhysAddr = endAddr(entry.start.PhysAddr, entry.nframes)
      if not prev.isNil and adjacent(prev, entry.start.PhysAddr):
        # merge contiguous regions
        prev.nframes += entry.nframes
      else:
        # create a new node
        var node: ptr PMNode = entry.start.PhysAddr.toPMNodePtr
        node.nframes = entry.nframes
        node.next = nil

        if not prev.isNil:
          prev.next = node
        else:
          head = node

        prev = node

    elif entry.type == MemoryType.Reserved:
      reservedRegions.add(PMRegion(start: entry.start.PhysAddr, nframes: entry.nframes))
    
    elif i > 0:
      # check if there's a gap between the previous entry and the current entry
      let prevEntry = memoryMap.entries[i - 1]
      let gap = (
        entry.start.PhysAddr - endAddr(prevEntry.start.PhysAddr, prevEntry.nframes)
      )
      if gap > 0:
        reservedRegions.add(PMRegion(
          start: endAddr(prevEntry.start.PhysAddr, prevEntry.nframes),
          nframes: gap div FrameSize
        ))
    
  # initialize pageFrames
  let totalPages = maxPhysAddr.uint64 div FrameSize
  logger.info &"Total pages: {totalPages}"
  logger.info &"pageFrames size: {totalPages * sizeof(PageFrame).uint64} bytes"
  pageFrames = newSeq[PageFrame](totalPages)

##########################################################################################
# Alloc / Alias
##########################################################################################

proc pmAlloc*(nframes: Positive): PhysAddr =
  ## Allocate a contiguous region of physical memory.
  let nframes = nframes.uint64

  var
    prev: ptr PMNode
    curr = head

  # find a region with enough frames
  while not curr.isNil and curr.nframes < nframes:
    prev = curr
    curr = curr.next
  
  if curr.isNil:
    # no region found
    raise newException(OutOfPhysicalMemory, "Out of physical memory")

  var newnode: ptr PMNode
  if curr.nframes == nframes:
    # exact match
    newnode = curr.next
  else:
    # split the region
    newnode = toPMNodePtr(curr.toPhysAddr +! nframes * FrameSize)
    newnode.nframes = curr.nframes - nframes
    newnode.next = curr.next

  if not prev.isNil:
    prev.next = newnode
  else:
    head = newnode

  zeroMem(curr, nframes * FrameSize)
  result = curr.toPhysAddr

  # increment the reference count
  var pfn = curr.toPhysAddr.uint64 div FrameSize
  for i in 0 ..< nframes:
    if pfn >= pageFrames.len.uint64:
      let paddr = pfn * FrameSize
      raise newException(InvalidRequest, &"Physical address {paddr:#x} is out of range")
    inc pageFrames[pfn].rc
    inc pfn

proc pmAlias*(paddr: PhysAddr, nframes: Positive) =
  ## Increment the reference count of a region of physical memory. The region must be
  ## already allocated.
  if paddr.uint64 mod FrameSize != 0:
    raise newException(InvalidRequest, &"Unaligned physical address: {paddr.uint64:#x}")

  if paddr.uint64 >= maxPhysAddr.uint64:
    # the region is outside of the physical memory, probably a hardware device
    return

  var pfn = paddr.uint64 div FrameSize
  for i in 0 ..< nframes:
    let pfnAddr = pfn * FrameSize
    if pfn >= pageFrames.len.uint64:
      raise newException(InvalidRequest, &"Physical address {pfnAddr:#x} is out of range")
    if pageFrames[pfn].rc == 0:
      raise newException(InvalidRequest, &"Physical address {pfnAddr:#x} is not allocated")

    inc pageFrames[pfn].rc
    inc pfn

##########################################################################################
# Free
##########################################################################################

proc pmFreeRegion(paddr: PhysAddr, nframes: Positive)
proc pmFree*(paddr: PhysAddr, nframes: uint64) =
  ## Free a contiguous region of physical memory.
  if paddr.uint64 mod FrameSize != 0:
    raise newException(InvalidRequest, &"Unaligned physical address: {paddr.uint64:#x}")

  if paddr +! nframes * FrameSize > maxPhysAddr:
    # the region is outside of the physical memory
    raise newException(
      InvalidRequest,
      &"Attempt to free a region outside of the physical memory.\n" &
      &"  Request: start={paddr.uint64:#x} + nframes={nframes} > max={maxPhysAddr.uint64:#x}"
    )

  for region in reservedRegions:
    if overlaps(region, PMRegion(start: paddr, nframes: nframes)):
      # the region is reserved
      raise newException(
        InvalidRequest,
        &"Attempt to free a reserved region.\n" &
        &"  Request: start={paddr.uint64:#x}, nframes={nframes}\n" &
        &"  Reserved: start={region.start.uint64:#x}, nframes={region.nframes}"
      )

  # decrement the reference count of each page and build a list of contiguous regions to
  # free
  var regions: seq[PMRegion]
  regions.add(default(PMRegion))

  var pfnAddr = paddr
  var pfn = paddr.uint64 div FrameSize
  logger.info &"freeing {nframes} frames at {paddr.uint64:#x}"
  for i in 0 ..< nframes:
    if pfn >= pageFrames.len.uint64:
      raise newException(InvalidRequest, &"Physical address {paddr.uint64:#x} is out of range")

    dec pageFrames[pfn].rc
    if pageFrames[pfn].rc == 0:
      inc regions[^1].nframes
      if regions[^1].start.uint64 == 0:
        regions[^1].start = pfnAddr

    elif regions[^1].nframes > 0:
      regions.add(default(PMRegion))

    inc pfn
    inc pfnAddr, FrameSize

  for region in regions:
    if region.nframes > 0:
      pmFreeRegion(region.start, region.nframes)

proc pmFreeRegion(paddr: PhysAddr, nframes: Positive) =
  let nframes = nframes.uint64
  var
    prev: ptr PMNode
    curr = head

  while not curr.isNil and curr.toPhysAddr < paddr:
    prev = curr
    curr = curr.next

  let
    overlapsWithCurr = not curr.isNil and paddr +! nframes * FrameSize > curr.toPhysAddr
    overlapsWithPrev = not prev.isNil and paddr < prev.toPhysAddr +! prev.nframes * FrameSize

  if overlapsWithCurr or overlapsWithPrev:
    raise newException(
      InvalidRequest,
      &"Attempt to free a region that overlaps with another free region.\n" &
      &"  Request: start={paddr.uint64:#x}, nframes={nframes}"
    )

  # the region to be freed is between prev and curr (either of them can be nil)

  if prev.isNil and curr.isNil:
    # logger.info "pmFree: the list is empty"
    # the list is empty
    var newnode = paddr.toPMNodePtr
    newnode.nframes = nframes
    newnode.next = nil
    head = newnode

  elif prev.isNil and adjacent(paddr, nframes, curr):
    # logger.info "pmFree: at the beginning, adjacent to curr"
    # at the beginning, adjacent to curr
    var newnode = paddr.toPMNodePtr
    newnode.nframes = nframes + curr.nframes
    newnode.next = curr.next
    head = newnode

  elif curr.isNil and adjacent(prev, paddr):
    # logger.info "pmFree: at the end, adjacent to prev"
    # at the end, adjacent to prev
    prev.nframes += nframes

  elif adjacent(prev, paddr) and adjacent(paddr, nframes, curr):
    # logger.info "pmFree: exactly between prev and curr"
    # exactly between prev and curr
    prev.nframes += nframes + curr.nframes
    prev.next = curr.next

  else:
    # not adjacent to any other region
    # logger.info "pmFree: not adjacent to any other region"
    var newnode = paddr.toPMNodePtr
    newnode.nframes = nframes
    newnode.next = curr
    if not prev.isNil:
      prev.next = newnode
    else:
      head = newnode

##########################################################################################
# Debugging
##########################################################################################

iterator pmFreeRegions*(): tuple[paddr: PhysAddr, nframes: uint64] =
  ## Iterate over all physical memory regions.
  var node = head
  while not node.isNil:
    yield (node.toPhysAddr, node.nframes)
    node = node.next

proc printFreeRegions*() =
  logger.raw &"""   {"Start":>16}"""
  logger.raw &"""   {"Start (KB)":>12}"""
  logger.raw &"""   {"Size (KB)":>11}"""
  logger.raw &"""   {"#Pages":>9}"""
  logger.raw "\n"
  var totalFreePages: uint64 = 0
  for (start, nframes) in pmFreeRegions():
    logger.raw &"   {cast[uint64](start):>#16x}"
    logger.raw &"   {cast[uint64](start) div 1024:>#12}"
    logger.raw &"   {nframes * 4:>#11}"
    logger.raw &"   {nframes:>#9}"
    logger.raw "\n"
    totalFreePages += nframes
  logger.info &"total free: {totalFreePages * 4} KiB ({totalFreePages * 4 div 1024} MiB)"
