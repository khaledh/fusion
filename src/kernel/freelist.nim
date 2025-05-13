#[
  A generic free list implementation.
]#
import std/strformat

const
  MagicNumber = 0xfbe27fd9e829630a'u64

let
  logger = DebugLogger(name: "freelist")

type
  FreeList* = object
    base*: uint64
    size*: uint64
    head*: FreeNode
    search*: FreeNode  # Node to start searching from

  FreeNode* = ref object
    start*: uint64
    size*: uint64
    next*: FreeNode
    prev*: FreeNode

  AllocatedSlice* = object
    magic: uint64 = MagicNumber
    start*: uint64
    size*: uint64

  OutOfSpaceError* = object of CatchableError
    ## An error raised when there is no space left in the free list to allocate.

template first*(list: FreeList): FreeNode = list.head.next  # skip the dummy node

template `end`*(list: FreeList): uint64 = list.base + list.size
template `end`*(node: FreeNode): uint64 = node.start + node.size
template `end`*(slice: AllocatedSlice): uint64 = slice.start + slice.size

proc newFreeList*(base: uint64, size: uint64): FreeList =
  ## Create a new free list.
  var dummy = FreeNode()
  let node = FreeNode(start: base, size: size, next: nil, prev: dummy)
  dummy.next = node
  result = FreeList(base: base, size: size, head: dummy, search: node)

proc adjacent(a, b: FreeNode): bool =
  ## Check if two free nodes are adjacent.
  return a.start + a.size == b.start

proc coalesce(a, b: FreeNode) =
  ## Coalesce two free nodes.
  assert adjacent(a, b), "Nodes are not adjacent"
  inc(a.size, b.size)
  a.next = b.next
  if not b.next.isNil:
    b.next.prev = a

proc insertNode(list: var FreeList, node: var FreeNode) =
  var prev = list.head  # dummy node
  var curr = prev.next
  while not curr.isNil and curr.start < node.start:
    prev = curr
    curr = curr.next

  # insert node between prev and curr
  node.next = curr
  node.prev = prev
  prev.next = node
  if not curr.isNil:
    curr.prev = node

  # coalesce with the previous free node if it's adjacent
  if adjacent(prev, node):
    coalesce(prev, node)
    node = prev

  # coalesce with the next free node if it's adjacent
  if not curr.isNil and adjacent(node, curr):
    coalesce(node, curr)

proc removeNode(list: var FreeList, node: FreeNode) =
  node.prev.next = node.next
  if not node.next.isNil:
    node.next.prev = node.prev
  if list.search == node:
    list.search = node.next

proc alloc*(list: var FreeList, n: uint64): AllocatedSlice =
  ## Allocate a new item of size `n` from the free list.
  var node = list.search
  while not node.isNil and node.size < n:
    node = node.next
  
  if node.isNil:
    raise newException(OutOfSpaceError, "Out of space")

  result = AllocatedSlice(start: node.start, size: n)

  if node.size == n:
    removeNode(list, node)
  else:
    inc(node.start, n)
    dec(node.size, n)

proc free*(list: var FreeList, slice: AllocatedSlice) =
  ## Free a slice of memory.
  if slice.magic != MagicNumber:
    raise newException(ValueError, "Slice was not allocated by this allocator")

  if slice.start < list.base or slice.start + slice.size > list.end:
    raise newException(ValueError, "Slice is out of bounds of the free list")

  var node = FreeNode(start: slice.start, size: slice.size, next: nil, prev: nil)
  insertNode(list, node)

proc reserve*(list: var FreeList, start, size: uint64): AllocatedSlice =
  ## Reserve a slice at a specific address.
  if start < list.base or start + size > list.end:
    var msg = "Slice is out of bounds of the free list\n"
    msg.add &" free list range: {list.base:#x} - {list.end:#x}\n"
    msg.add &" slice range: {start:#x} - {start + size:#x}\n"
    raise newException(ValueError, msg)

  if size == 0:
    raise newException(ValueError, "Size must be greater than 0")

  result = AllocatedSlice(start: start, size: size)

  # carve out the slice from the free list
  var node = list.first
  while not node.isNil and not (node.start <= start and node.end >= start + size):
    node = node.next
  
  if node.isNil:
    raise newException(OutOfSpaceError, "Out of space or slice overlaps with existing allocations")

  # logger.info &"reserve: carving out slice at {start:#>016x} ({bytesToBinSize(size)})"

  if node.size == size:
    # perfect fit
    # logger.info &"reserve: perfect fit, removing node"
    removeNode(list, node)
  elif node.start == start:
    # start of the slice is the start of the node
    # logger.info &"reserve: start of the slice is the start of the node"
    inc(node.start, size)
    dec(node.size, size)
  elif node.end == start + size:
    # end of the slice is the end of the node
    # logger.info &"reserve: end of the slice is the end of the node"
    dec(node.size, size)
  else:
    # split the node
    # logger.info &"reserve: splitting the node"
    let after = FreeNode(
      start: start + size,
      size: node.end - (start + size),
      next: node.next,
      prev: node
    )
    # logger.info &"node.end: {node.end:#>016x}"
    # logger.info &"reserve: after node: {after.start:#>016x} - {after.end - 1:#>016x} ({bytesToBinSize(after.size)})"
    node.size = start - node.start
    if not node.next.isNil:
      node.next.prev = after
    node.next = after

proc dump*(list: FreeList) =
  ## Dump the free list to the console.
  var node = list.first
  while not node.isNil:
    logger.info &" {node.start:#>016x} - {node.end - 1:#>016x} ({bytesToBinSize(node.size, bThousands)})"
    node = node.next
