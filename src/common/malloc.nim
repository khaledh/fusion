#[
  A simple heap bump allocator that is used for Nim's `any` target.
]#

{.used.}

import common/debugcon

when defined(Heap4M):
  const HeapSize = 1024 * 1024 * 4
elif defined(Heap2M):
  const HeapSize = 1024 * 1024 * 2
else:
  const HeapSize = 1024 * 1024

var
  heap*: array[HeapSize, byte]
  heapBumpPtr*: int = cast[int](addr heap[0])
  heapMaxPtr*: int = cast[int](addr heap[0]) + heap.high

proc malloc*(size: csize_t): pointer {.exportc.} =
  if heapBumpPtr + size.int > heapMaxPtr:
    debugln "Out of memory"
    # return nil
    quit()

  result = cast[pointer](heapBumpPtr)
  inc heapBumpPtr, size.int

proc calloc*(num: csize_t, size: csize_t): pointer {.exportc.} =
  result = malloc(size * num)

proc free*(p: pointer) {.exportc.} =
  discard

proc realloc*(p: pointer, new_size: csize_t): pointer {.exportc.} =
  result = malloc(new_size)
  copyMem(result, p, new_size)
  free(p)
