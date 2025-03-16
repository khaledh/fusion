discard """
  matrix: "-d:macosx"
"""

# Test for heap fragmentation and coalescing
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

# Initial stats check
echo "Initial heap state:"
heap.printStats()
var stats = heap.getStats()
assert stats.totalMemory == MinPages * PageSize
assert stats.fragmentation == 0.0

# Create some pointers to track allocations
var ptrs: array[20, pointer]

# Create fragmentation pattern: allocate 10 blocks of different sizes
echo "\nAllocating 10 blocks of various sizes:"
for i in 0..9:
  let size = (i+1) * 50  # 50, 100, 150, ... 500 bytes
  ptrs[i] = heap.alloc(size)
  assert ptrs[i] != nil
  echo "Allocated block ", i, " of size ", size, " bytes"

heap.printStats()
stats = heap.getStats()
assert stats.blockCount > 10  # At least our 10 blocks plus free blocks
assert stats.freeBlockCount >= 1

# Free every other block to create fragmentation
echo "\nFreeing alternating blocks to create fragmentation:"
for i in 0..9:
  if i mod 2 == 0:
    echo "Freeing block ", i
    heap.free(ptrs[i])
    ptrs[i] = nil

heap.printStats()
stats = heap.getStats()
assert stats.freeBlockCount >= 5  # At least 5 free blocks (one for each we freed)
# Note: Coalescing might happen and prevent fragmentation in some cases
let hasFragmentation = stats.fragmentation > 0.0
echo "Has fragmentation: ", hasFragmentation

# Record the fragmentation level
let fragmentationBefore = stats.fragmentation
echo "Fragmentation level: ", fragmentationBefore

# Allocate a few more blocks of varying sizes to fit in the fragments
echo "\nAllocating blocks to fit in fragments:"
for i in 10..14:
  let size = 30 * (i - 9)  # 30, 60, 90, 120, 150 bytes
  ptrs[i] = heap.alloc(size)
  assert ptrs[i] != nil
  echo "Allocated block ", i, " of size ", size, " bytes"

heap.printStats()
stats = heap.getStats()

# Free all remaining blocks - this should trigger coalescing
echo "\nFreeing all blocks to test coalescing:"
for i in 0..14:
  if ptrs[i] != nil:
    heap.free(ptrs[i])
    ptrs[i] = nil

heap.printStats()
stats = heap.getStats()

# Check if coalescing worked properly
assert stats.freeBlockCount <= 2  # Should be at most 2 blocks (one in each page set)
# Fragmentation might be 0 if all blocks in a page set are coalesced
assert stats.fragmentation <= fragmentationBefore  # Fragmentation should not increase
assert stats.largestFreeBlock > 0  # Should have a large free block

# Test that the largest free block is close to the maximum free space in a page set
# The difference would be the page header and block header overhead
let expectedLargest = (MinPages * PageSize) - roundUpToAlignment(sizeof(PageSetHeaderObj)) - sizeof(BlockHeaderObj)
assert stats.largestFreeBlock >= expectedLargest - 200  # Allow some overhead

# Allocate a large block, then many small blocks, then free the large block
# This creates an "island" of a large free block
echo "\nTesting island creation:"
ptrs[0] = heap.alloc(10000)  # Large block
assert ptrs[0] != nil

# Allocate small blocks after it
for i in 1..5:
  ptrs[i] = heap.alloc(100)
  assert ptrs[i] != nil

# Free the large block, creating an island
heap.free(ptrs[0])
ptrs[0] = nil

heap.printStats()
stats = heap.getStats()
assert stats.freeBlockCount >= 2  # At least 2 free blocks (the island and any others)