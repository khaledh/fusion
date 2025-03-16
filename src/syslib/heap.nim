# Heap allocator for user space

import std/strformat

type
  PageAllocator* = object
    ## Page allocator interface used by the heap.
    requestPages*: proc (numPages: int): pointer
    freePages*: proc (p: pointer, numPages: int)

  PageSetHeader = ptr PageSetHeaderObj
  PageSetHeaderObj = object
    ## Tracks a contiguous set of pages allocated by the heap.
    numPages: int
    next: PageSetHeader

  BlockHeader = ptr BlockHeaderObj
  BlockHeaderObj = object
    ## Header for each block in the heap.
    sizeField: int     # Size of block including header (3 LSBs used for flags, bit 0 = free)
    next: BlockHeader  # Next free block (if this block is free)
    prev: BlockHeader  # Previous free block (if this block is free)
    magic: int         # Magic number to detect invalid memory blocks during free

  Heap* = object
    ## A heap backed by a page allocator.
    freeList: BlockHeader         # Head of free blocks list
    pageAllocator: PageAllocator  # Page allocator for requesting pages
    pagesHead: PageSetHeader      # Head of linked list of allocated page sets
    pagesTail: PageSetHeader      # Tail      "

  HeapStats* = object
    ## Statistics about heap memory usage
    totalMemory*: int      ## Total memory managed by the heap (bytes)
    freeMemory*: int       ## Memory that's available for allocation (bytes)
    usedMemory*: int       ## Memory that's currently allocated (bytes)
    overhead*: int         ## Memory used by page headers and block headers
    pageCount*: int        ## Number of pages allocated from the OS
    blockCount*: int       ## Total number of blocks (free + used)
    freeBlockCount*: int   ## Number of free blocks
    largestFreeBlock*: int ## Size of the largest free block
    fragmentation*: float  ## Fragmentation ratio (1 - largest free block / total free memory)

const
  PageSize = 4096           # Page size in bytes
  MinPages = 4              # Minimum number of pages to request
  MinAllocSize = 8          # Minimum allocation size in bytes
  DefaultAlignment = 8      # Default alignment for allocations
  FlagsMask =
    DefaultAlignment - 1    # Mask for block flags
  FreeFlag = 0x1            # Bit 0 indicates if block is free
  MagicNumber = 0x00C0FFEE  # Magic number for block validation

########################################################
# Helper functions
########################################################

template `+!`(p: pointer, offset: int): pointer =
  cast[pointer](cast[int](p) + offset)

template `-!`(p: pointer, offset: int): pointer =
  cast[pointer](cast[int](p) - offset)

template roundUp(n: int, alignment: int): int =
  (n + alignment - 1) and not(alignment - 1)

proc roundUpToPageSize(size: int): int {.inline.} =
  ## Round up to the nearest page size.
  result = roundUp(size, PageSize)

proc roundUpToAlignment(size: int): int {.inline.} =
  result = roundUp(size, DefaultAlignment)

proc flags(blk: BlockHeader): int {.inline.} =
  result = blk.sizeField and FlagsMask

proc userSize(blk: BlockHeader): int {.inline.} =
  result = blk.sizeField and not FlagsMask

proc `userSize=`(blk: BlockHeader, value: int) {.inline.} =
  assert (value and FlagsMask) == 0, fmt"Block size is not aligned to {DefaultAlignment} bytes"
  blk.sizeField = value or blk.flags

proc fullSize(blk: BlockHeader): int {.inline.} =
  sizeof(BlockHeaderObj) + blk.userSize

proc expandBlock(blk: BlockHeader, value: int) {.inline.} =
  blk.userSize = blk.userSize + value

proc isFree(blk: BlockHeader): bool {.inline.} =
  result = (blk.sizeField and FreeFlag) != 0

proc `isFree=`(blk: BlockHeader, value: bool) {.inline.} =
  if value:
    blk.sizeField = blk.sizeField or FreeFlag
  else:
    blk.sizeField = blk.sizeField and not FreeFlag

proc adjacent(a, b: BlockHeader): bool {.inline.} =
  a +! a.fullSize == b

iterator pageSets*(heap: Heap): PageSetHeader =
  ## Iterate over all page sets in the heap
  var pgSetHeader = heap.pagesHead
  while pgSetHeader != nil:
    yield pgSetHeader
    pgSetHeader = pgSetHeader.next

iterator freeBlocks*(heap: Heap): BlockHeader =
  ## Iterate over all free blocks in the heap
  var blk = heap.freeList
  while blk != nil:
    yield blk
    blk = blk.next

iterator blocksInPageSet*(pgSetHeader: PageSetHeader): BlockHeader =
  ## Iterate over all blocks in a page set
  let pgSetHeaderSize = roundUpToAlignment(sizeof(PageSetHeaderObj))
  var blk = cast[BlockHeader](cast[pointer](pgSetHeader) +! pgSetHeaderSize)
  let pageEnd = cast[pointer](pgSetHeader) +! pgSetHeader.numPages * PageSize
  
  while cast[pointer](blk) < pageEnd:
    yield blk
    blk = cast[BlockHeader](cast[pointer](blk) +! blk.fullSize)

########################################################
# Heap functions (private)
########################################################

proc newHeap*(pageAllocator: PageAllocator): Heap =
  ## Initialize the heap with an initial set of pages.
  result.pageAllocator = pageAllocator
  
  # Request initial set of pages
  let p = pageAllocator.requestPages(MinPages)
  
  # Track the allocated pages - store header at beginning of page
  let pgSetHeader = cast[PageSetHeader](p)
  pgSetHeader.numPages = MinPages
  pgSetHeader.next = nil
  result.pagesHead = pgSetHeader
  result.pagesTail = pgSetHeader
  
  # Initialize the free list - start after the page header
  let pgSetHeaderSize = roundUpToAlignment(sizeof(PageSetHeaderObj))
  let initialBlock = cast[BlockHeader](p +! pgSetHeaderSize)
  initialBlock.userSize = (pgSetHeader.numPages * PageSize) - pgSetHeaderSize - sizeof(BlockHeaderObj)
  initialBlock.isFree = true
  initialBlock.next = nil
  initialBlock.prev = nil

  result.freeList = initialBlock

proc `=destroy`*(heap: Heap) =
  ## Destroy the heap.
  ##
  ## This will free all the pages allocated by the heap.
  var curr = heap.pagesHead
  var next: PageSetHeader = nil
  while curr != nil:
    next = curr.next  # take a copy of `next` before freeing the header
    echo fmt"Freeing {curr.numPages} pages"
    heap.pageAllocator.freePages(curr, curr.numPages)
    curr = next

proc coalesce(heap: var Heap, blk: BlockHeader): BlockHeader
proc insertFreeBlock(heap: var Heap, blk: BlockHeader) =
  ## Insert a block into the free list in address order.
  var current = heap.freeList
  var prev: BlockHeader = nil

  while current != nil and current < blk:
    prev = current
    current = current.next

  # Insert the block
  blk.next = current
  blk.prev = prev

  if prev == nil:
    heap.freeList = blk
  else:
    prev.next = blk

  if current != nil:
    current.prev = blk
  
  # Coalesce with adjacent free blocks
  discard coalesce(heap, blk)

proc findFreeBlock(heap: var Heap, size: int): BlockHeader =
  # Best-fit block selection strategy
  var blk = heap.freeList
  var bestFit: BlockHeader = nil
  var bestSize = high(int)
  
  while blk != nil:
    if blk.isFree and blk.userSize >= size:
      # Found a fit, check if it's better than current best
      if blk.userSize < bestSize:
        bestFit = blk
        bestSize = blk.userSize
        # Perfect fit - no need to keep searching
        if blk.userSize == size:
          break
    blk = blk.next
  
  return bestFit

proc expandHeap(heap: var Heap, minSize: int): BlockHeader =
  ## Expand the heap by requesting new pages from the page allocator.
  let minPages = roundUpToPageSize(minSize) div PageSize
  let numPages = max(minPages, MinPages)
  echo fmt"Requesting {numPages} pages"
  let p = heap.pageAllocator.requestPages(numPages)
  
  # Track the allocated pages - store header at beginning of page
  let pgSetHeader = cast[PageSetHeader](p)
  pgSetHeader.numPages = numPages
  heap.pagesTail.next = pgSetHeader
  heap.pagesTail = pgSetHeader
  
  # Create new block after the page header
  let pgSetHeaderSize = roundUpToAlignment(sizeof(PageSetHeaderObj))
  let newBlock = cast[BlockHeader](p +! pgSetHeaderSize)
  newBlock.userSize = (numPages * PageSize) - pgSetHeaderSize - sizeof(BlockHeaderObj)
  newBlock.isFree = true

  # Add to free list in address order (so that coalesce works correctly)
  insertFreeBlock(heap, newBlock)

  return newBlock

proc removeFreeBlock(heap: var Heap, blk: BlockHeader) =
  ## Remove a block from the free list.
  if heap.freeList == blk:
    heap.freeList = blk.next

  if blk.prev != nil:
    blk.prev.next = blk.next
  
  if blk.next != nil:
    blk.next.prev = blk.prev

proc split(blk: BlockHeader, size: int) =
  ## Split a block into two blocks: one of the requested size and one
  ## of the remaining size.
  let remainingSize = blk.userSize - size
  if remainingSize > (sizeof(BlockHeaderObj) + MinAllocSize):
    # Create new block from remaining space
    let newBlock = cast[BlockHeader](blk +! (sizeof(BlockHeaderObj) + size))
    newBlock.userSize = remainingSize - sizeof(BlockHeaderObj)
    newBlock.isFree = true
    newBlock.next = blk.next
    newBlock.prev = blk
    
    # Update next block's prev pointer if it exists
    if blk.next != nil:
      blk.next.prev = newBlock

    # Update original block
    blk.userSize = size
    blk.next = newBlock

proc coalesce(heap: var Heap, blk: BlockHeader): BlockHeader =
  ## Coalesce adjacent free blocks (if possible) and return the
  ## coalesced block.
  var blk = blk

  # Check if we can merge with the previous block
  if blk.prev != nil and blk.prev.isFree and adjacent(blk.prev, blk):
    let blockSize = blk.fullSize
    removeFreeBlock(heap, blk)
    expandBlock blk.prev, blockSize
    blk = blk.prev

  # Check if we can merge with the block after blk
  if blk.next != nil and blk.next.isFree and adjacent(blk, blk.next):
    let nextBlockSize = blk.next.fullSize
    removeFreeBlock(heap, blk.next)
    expandBlock blk, nextBlockSize

########################################################
# Heap functions (public)
########################################################

proc alloc*(heap: var Heap, size: int): pointer =
  ## Allocate a block of memory of the requested size.
  if size <= 0:
    return nil

  # Align size to the default alignment
  let alignedSize = if size < MinAllocSize: MinAllocSize else: roundUpToAlignment(size)

  # Find free block
  var blk = findFreeBlock(heap, alignedSize)
  if blk == nil:
    echo fmt"Expanding heap by: {alignedSize}"
    blk = expandHeap(heap, sizeof(BlockHeaderObj) + alignedSize)

  # Split block if too large
  split(blk, alignedSize)
  
  # Mark as used and remove from free list
  blk.isFree = false
  blk.magic = MagicNumber
  removeFreeBlock(heap, blk)

  # Return pointer to usable memory (after header)
  result = blk +! sizeof(BlockHeaderObj)

proc free*(heap: var Heap, p: pointer) =
  ## Free a block of memory.
  ## 
  ## The pointer must have been returned by a previous call to `alloc`.
  ##
  ## This function will silently ignore invalid pointers and double
  ## frees.
  if p == nil: return
  
  # Get block header
  let blk = cast[BlockHeader](p -! sizeof(BlockHeaderObj))

  if blk.magic != MagicNumber:
    return  # Invalid magic number, silently ignore

  if blk.isFree:
    return  # Double free, silently ignore

  # Mark as free
  blk.isFree = true
  
  # Add to free list
  insertFreeBlock(heap, blk)

  # TODO: Return pages to the page allocator if possible

########################################################
# Heap statistics
########################################################

proc getStats*(heap: Heap): HeapStats =
  ## Return statistics about heap memory usage
  result.pageCount = 0
  result.totalMemory = 0
  result.overhead = 0
  
  # Calculate total memory from page list and page set header overhead
  for pgSetHeader in heap.pageSets:
    inc result.pageCount, pgSetHeader.numPages
    inc result.totalMemory, pgSetHeader.numPages * PageSize
    inc result.overhead, roundUpToAlignment(sizeof(PageSetHeaderObj))
  
  # Calculate free memory by traversing free list
  result.freeMemory = 0
  result.freeBlockCount = 0
  result.largestFreeBlock = 0
  for freeBlock in heap.freeBlocks:
    inc(result.freeMemory, freeBlock.userSize)
    inc(result.freeBlockCount)
    if freeBlock.userSize > result.largestFreeBlock:
      result.largestFreeBlock = freeBlock.userSize
  
  # Traverse all blocks to count total blocks and calculate block header overhead
  result.blockCount = 0
  for pgSetHeader in heap.pageSets:
    for blk in pgSetHeader.blocksInPageSet:
      inc result.blockCount
      inc result.overhead, sizeof(BlockHeaderObj)
  
  # Calculate used memory (user memory only, excluding overhead)
  result.usedMemory = result.totalMemory - result.freeMemory - result.overhead

proc printStats*(heap: Heap) =
  ## Print statistics about heap memory usage
  let stats = heap.getStats()
  echo ""
  echo "Heap Statistics:"
  echo fmt"  Total memory:       {stats.totalMemory} bytes"
  echo fmt"  Used memory:        {stats.usedMemory} bytes ({(100 * float(stats.usedMemory) / float(max(1, stats.totalMemory))):0.1f}%)"
  echo fmt"  Free memory:        {stats.freeMemory} bytes ({(100 * float(stats.freeMemory) / float(max(1, stats.totalMemory))):0.1f}%)"
  echo fmt"  Overhead:           {stats.overhead} bytes ({(100 * float(stats.overhead) / float(max(1, stats.totalMemory))):0.1f}%)"
  echo fmt"  Pages:              {stats.pageCount}"
  echo fmt"  Blocks:             {stats.blockCount} ({stats.freeBlockCount} free)"
  echo fmt"  Largest free block: {stats.largestFreeBlock} bytes"
  echo fmt"  Fragmentation:      {(100 * (1.0 - float(stats.largestFreeBlock) / float(max(1, stats.freeMemory)))):0.1f}%"

  # Print all blocks
  echo "Blocks:"
  for pgSetHeader in heap.pageSets:
    for blk in pgSetHeader.blocksInPageSet:
      let isFree = if blk.isFree: "FREE" else: "USED"
      echo fmt"  {cast[int](blk):#08x} {isFree} fullSize = {blk.fullSize: >6}, userSize = {blk.userSize: >6}"
