{.used.}

import kernel/debugcon

var
  heap*: array[2*1024*1024, byte]
  heapBumpPtr*: int = cast[int](addr heap[0])
  heapMaxPtr*: int = cast[int](addr heap[0]) + heap.high

proc malloc*(size: csize_t): pointer {.exportc.} =
  if heapBumpPtr + size.int > heapMaxPtr:
    debugln "Out of memory"
    # return nil
    quit()

  result = cast[pointer](heapBumpPtr)

  # let oldHeapSize = heapBumpPtr - cast[int](addr heap)
  inc heapBumpPtr, size.int
  # let newHeapSize = heapBumpPtr - cast[int](addr heap)

  # if oldHeapSize < 6*1024*1024 and newHeapSize >= 6*1024*1024:
  #   debugln "******** heap >= 6M ********"
  #   quit()
  # if oldHeapSize < 5*1024*1024 and newHeapSize >= 5*1024*1024:
  #   debugln "******** heap >= 5M ********"
  #   quit()
  # if oldHeapSize < 4*1024*1024 and newHeapSize >= 4*1024*1024:
  #   debugln "******** heap >= 4M ********"
  # if oldHeapSize < 2*1024*1024 and newHeapSize >= 2*1024*1024:
  #   debugln "******** heap >= 2M ********"
  # if oldHeapSize < 1024*1024 and newHeapSize >= 1024*1024:
  #   debugln "******** heap >= 1M ********"
  # if oldHeapSize < 512*1024 and newHeapSize >= 512*1024:
  #   debugln "******** heap >= 512k ********"
  # if oldHeapSize < 256*1024 and newHeapSize >= 256*1024:
  #   debugln "******** heap >= 256k ********"
  # if oldHeapSize < 128*1024 and newHeapSize >= 128*1024:
  #   debugln "******** heap >= 128k ********"
  # elif oldHeapSize < 64*1024 and newHeapSize >= 64*1024:
  #   debugln "******** heap >= 64k ********"
  # elif oldHeapSize < 32*1024 and newHeapSize >= 32*1024:
  #   debugln "******** heap >= 32k ********"
  # elif oldHeapSize < 16*1024 and newHeapSize >= 16*1024:
  #   debugln "******** heap >= 16k ********"

proc calloc*(num: csize_t, size: csize_t): pointer {.exportc.} =
  # if num > 100:
  #   debugln "calloc: ", $num, " ", $size
  result = malloc(size * num)

proc free*(p: pointer) {.exportc.} =
  discard

proc realloc*(p: pointer, new_size: csize_t): pointer {.exportc.} =
  result = malloc(new_size)
  copyMem(result, p, new_size)
  free(p)


proc aligned_malloc*(size: int, alignment: int): pointer {.exportc.} =
  let p = malloc((size + alignment).csize_t)
  let mask = (alignment - 1).uint
  let aligned = (cast[uint](p) + mask) and not mask
  result = cast[pointer](aligned)
  # debugln "alloc_aligned: ", $size, " ", $alignment, " ", $p, " ", $result
