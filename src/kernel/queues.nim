import std/deques

import condvars
import locks

let
  logger = DebugLogger(name: "queue")

type
  BlockingQueue*[T] = ref object of RootObj
    lock*: Lock
    cap*: int
    items*: Deque[T]
    notEmptyListeners*: seq[QueueListener]
    notFullListeners*: seq[QueueListener]
  
  QueueListener* = ref object of RootObj
    lock*: Lock
    cv*: CondVar
    isSignaled*: bool

proc newBlockingQueue*[T](capacity: int): BlockingQueue[T] =
  result = BlockingQueue[T](
    cap: capacity,
    items: initDeque[T](),
    lock: newSpinLock(),
    notEmptyListeners: @[],
    notFullListeners: @[],
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

####################################################################################################
# Listener management
####################################################################################################

proc newQueueListener*(): QueueListener =
  result = QueueListener(
    cv: newCondVar(),
    lock: newSpinLock(),
    isSignaled: false,
  )

### Helpers (private)

template addListener(listeners: var seq[QueueListener], listener: QueueListener) =
  listeners.add(listener)

template removeListener(listeners: var seq[QueueListener], listener: QueueListener) =
  let idx = listeners.find(listener)
  if idx >= 0:
    listeners.del(idx)

template withListener(listeners: var seq[QueueListener], listener: QueueListener, body: untyped) =
  try:
    addListener(listeners, listener)
    body
  finally:
    removeListener(listeners, listener)

### Notify listeners (private)

template notifyListeners(listeners: seq[QueueListener]) =
  for listener in listeners:
    withLock(listener.lock):
      if not listener.isSignaled:
        listener.isSignaled = true
        listener.cv.signal

### Add/Remove listeners (public)

proc addNotEmptyListener*[T](q: BlockingQueue[T], listener: QueueListener) =
  withLock(q.lock):
    addListener(q.notEmptyListeners, listener)

proc removeNotEmptyListener*[T](q: BlockingQueue[T], listener: QueueListener) =
  withLock(q.lock):
    removeListener(q.notEmptyListeners, listener)

proc addNotFullListener*[T](q: BlockingQueue[T], listener: QueueListener) =
  withLock(q.lock):
    addListener(q.notFullListeners, listener)

proc removeNotFullListener*[T](q: BlockingQueue[T], listener: QueueListener) =
  withLock(q.lock):
    removeListener(q.notFullListeners, listener)

####################################################################################################
# Enqueue
####################################################################################################

proc enqueue*[T](q: BlockingQueue[T], item: T) =
  withLock(q.lock):
    while q.items.len == q.cap:
      logger.info "queue is full, waiting"
      let notFull = newQueueListener()
      withListener(q.notFullListeners, notFull):
        notFull.cv.wait(q.lock)

    q.items.addLast(item)
    notifyListeners(q.notEmptyListeners)

proc enqueueNoWait*[T](q: BlockingQueue[T], item: T): bool =
  withLock(q.lock):
    if q.items.len < q.cap:
      q.items.addLast(item)
      notifyListeners(q.notEmptyListeners)
      result = true

####################################################################################################
# Dequeue
####################################################################################################

proc dequeue*[T](q: BlockingQueue[T]): T =
  withLock(q.lock):
    while q.items.len == 0:
      logger.info "queue is empty, waiting"
      let notEmpty = newQueueListener()
      withListener(q.notEmptyListeners, notEmpty):
        notEmpty.cv.wait(q.lock)
    
    result = q.items.popFirst()
    notifyListeners(q.notFullListeners)

proc dequeueNoWait*[T](q: BlockingQueue[T]): Option[T] =
  withLock(q.lock):
    if q.items.len > 0:
      result = some(q.items.popFirst())
      notifyListeners(q.notFullListeners)
