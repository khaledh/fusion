import std/deques

import condvars
import locks

type
  BlockingQueue*[T] = ref object of RootObj
    cap*: int
    items*: Deque[T]
    lock*: Lock
    notEmpty*: CondVar
    notFull*: CondVar

let
  logger = DebugLogger(name: "queue")

proc newBlockingQueue*[T](capacity: int): BlockingQueue[T] =
  result = BlockingQueue[T](
    cap: capacity,
    items: initDeque[T](),
    lock: newSpinLock(),
    notEmpty: newCondVar(),
    notFull: newCondVar(),
  )

proc len*[T](q: BlockingQueue[T]): int =
  withLock(q.lock):
    result = q.items.len

proc isEmpty*[T](q: BlockingQueue[T]): bool =
  withLock(q.lock):
    result = q.items.len == 0

proc isFull*[T](q: BlockingQueue[T]): bool =
  withLock(q.lock):
    result = q.items.len == q.cap

proc enqueue*[T](q: BlockingQueue[T], item: T) =
  withLock(q.lock):
    while q.items.len == q.cap:
      logger.info "queue is full, waiting"
      q.notFull.wait(q.lock)

    q.items.addLast(item)
    q.notEmpty.signal

proc enqueueNoWait*[T](q: BlockingQueue[T], item: T): bool =
  withLock(q.lock):
    if q.items.len < q.cap:
      q.items.addLast(item)
      q.notEmpty.signal
      result = true
    else:
      result = false

proc dequeue*[T](q: BlockingQueue[T]): T =
  withLock(q.lock):
    while q.items.len == 0:
      logger.info "queue is empty, waiting"
      q.notEmpty.wait(q.lock)

    result = q.items.popFirst()
    q.notFull.signal

proc dequeueNoWait*[T](q: BlockingQueue[T]): Option[T] =
  withLock(q.lock):
    if q.items.len > 0:
      result = some(q.items.popFirst())
      q.notFull.signal
