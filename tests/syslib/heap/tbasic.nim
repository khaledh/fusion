discard """
  matrix: "-d:macosx"
"""

# Basic allocation and deallocation test
include syslib/heap

# Mock page allocator for testing
proc mockRequestPages(numPages: int): pointer =
  result = alloc(numPages * PageSize)

proc mockFreePages(p: pointer, numPages: int) =
  dealloc(p)

let allocator = PageAllocator(
  requestPages: mockRequestPages,
  freePages: mockFreePages
)

var heap = newHeap(allocator)

heap.printStats()
# Add assertion for initial stats
var stats = heap.getStats()
assert stats.totalMemory == MinPages * PageSize
assert stats.freeMemory == (MinPages * PageSize) - roundUpToAlignment(sizeof(PageSetHeaderObj)) - sizeof(BlockHeaderObj)
assert stats.overhead == roundUpToAlignment(sizeof(PageSetHeaderObj)) + sizeof(BlockHeaderObj)
assert stats.usedMemory == 0  # No user memory allocated yet
assert stats.pageCount == MinPages
assert stats.blockCount == 1
assert stats.freeBlockCount == 1

# Allocate a small block
echo ""
echo "allocating 100 bytes"
let p1 = heap.alloc(100)
assert p1 != nil
heap.printStats()

# Verify stats after first allocation
stats = heap.getStats()
heap.printStats()
assert stats.freeBlockCount == 1  # Should still be 1 free block after the allocated one
assert stats.blockCount == 2  # Now we have 2 blocks - one allocated and one free
assert stats.usedMemory >= 100  # Used memory should include at least the allocated size (header is in overhead)

echo ""
echo "allocating 5 bytes"
let p2 = heap.alloc(5)
assert p2 != nil
heap.printStats()

# Verify stats after second allocation
stats = heap.getStats()
assert stats.blockCount == 3  # Now we have 3 blocks
assert stats.freeBlockCount == 1  # Still 1 free block
assert stats.usedMemory >= 100 + 8  # 100 bytes + at least 8 bytes (min alloc)

# Free the first block
echo ""
echo "freeing 100 bytes"
heap.free(p1)
heap.printStats()

# Verify stats after freeing first block
stats = heap.getStats()
assert stats.freeBlockCount == 2
assert stats.usedMemory >= 8  # Only the 5-byte allocation (rounded to min 8)

echo ""
echo "freeing 5 bytes"
heap.free(p2)
heap.printStats()

# Verify stats after freeing all blocks
stats = heap.getStats()
assert stats.freeBlockCount == 1  # Should be back to 1 free block after coalescing
assert stats.overhead == roundUpToAlignment(sizeof(PageSetHeaderObj)) + sizeof(BlockHeaderObj)  # Page header and block header overhead
assert stats.usedMemory == 0  # No user memory allocated
assert stats.blockCount == 1  # Back to 1 block
# Check if we're back to initial state (minus page header overhead)
assert stats.freeMemory == (MinPages * PageSize) - roundUpToAlignment(sizeof(PageSetHeaderObj)) - sizeof(BlockHeaderObj)

# New test case: Allocate large block that spans multiple pages
echo ""
echo "allocating large block of 20000 bytes"
let p3 = heap.alloc(20000)
assert p3 != nil
heap.printStats()

# Verify stats after large allocation
stats = heap.getStats()
assert stats.blockCount == 3  # One free from the original page set, one allocated, and one free remaining in the new page set
assert stats.freeBlockCount == 2  # Still 1 free block
assert stats.usedMemory >= 20000  # Large block

echo ""
echo "freeing large block of 20000 bytes"
heap.free(p3)
heap.printStats()

# Verify stats after freeing large block
stats = heap.getStats()
assert stats.blockCount == 2  # one from each page set (cannot be coalesced)
assert stats.freeBlockCount == 2  # both are free
assert stats.usedMemory == 0  # No user memory allocated
assert stats.overhead == 2 * roundUpToAlignment(sizeof(PageSetHeaderObj)) + 2 * sizeof(BlockHeaderObj)  # Page and block headers
