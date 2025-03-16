#[
  Segment tree implementation.
]#

type
  Node[T: ref] = ref object
    ## The segment represented by this node. T must have a `start` and `end` field.
    ## `start` is inclusive, while `end` is exclusive (both must be `Ordinal`).
    segment: T
    leftChild, rightChild: Node

  SegmentTree*[T: ref] = ref object
    ## A binary tree of non-overlapping segments. The segments in the left subtree all end
    ## before the segment in the parent node, and the segments in the right subtree all
    ## start after the segment in the parent node.
    min*, max*: Ordinal
    root: Node[T]

proc newNode[T: ref](segment: T): Node =
  new(result)
  result.segment = segment

proc insert*[T: ref](tree: var SegmentTree, segment: T) =
  if segment.start < tree.min or segment.end > tree.max:
    raise newException(ValueError, "Segment is out of tree bounds")

  if tree.root.isNil:
    tree.root = newNode(segment)
    return
  
  var node = tree.root
  while true:
    if segment.end <= node.segment.start:
      if node.leftChild.isNil:
        node.leftChild = newNode(segment)
        # balance tree by rotating right
        var temp = node.leftChild
        node.leftChild = temp.rightChild
        temp.rightChild = node
        node = temp
        
        return
      else:
        node = node.leftChild
    elif segment.start >= node.segment.end:
      if node.rightChild.isNil:
        node.rightChild = newNode(segment)
        return
      else:
        node = node.rightChild
    else:
      raise newException(ValueError, "Overlapping segments are not allowed")

proc find*[T: ref](tree: SegmentTree, point: Ordinal): lent T =
  if point < tree.min or point > tree.max:
    raise newException(ValueError, "Point is out of tree bounds")

  var node = tree.root
  while node != nil:
    if point >= node.segment.left and point < node.segment.right:
      return node.segment
    elif point < node.segment.left:
      node = node.leftChild
    else:
      node = node.rightChild

  return nil

proc findFreeSegment(tree: SegmentTree, minSize: Positive): tuple[start, end: Ordinal] =
  var start = tree.min
  var end = tree.max
  var node = tree.root
  while node != nil:
    if start + minSize <= node.segment.start:
      end = node.segment.start
      node = node.leftChild
    else:
      start = node.segment.end
      node = node.rightChild

  return (start, end)
