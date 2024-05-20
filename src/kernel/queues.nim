import condvars
import debugcon
import locks

{.used.}

type
  BlockingQueue*[T] = ref object of RootObj
    maxSize*: int
    queue*: seq[T]
    lock*: Lock
    notEmpty*: CondVar
    notFull*: CondVar

let
  logger = DebugLogger(name: "queue")

proc newBlockingQueue*[T](maxSize: int): BlockingQueue[T] =
  result = BlockingQueue[T]()
  result.maxSize = maxSize
  result.queue = @[]
  result.lock = newSpinLock()
  result.notEmpty = newCondVar()
  result.notFull = newCondVar()

proc enqueue*[T](q: BlockingQueue[T], item: T) =
  q.lock.acquire

  while q.queue.len == q.maxSize:
    logger.info "queue is full, waiting"
    q.notFull.wait(q.lock)

  logger.info "enqueuing item"
  q.queue.add(item)
  q.notEmpty.signal

  q.lock.release

proc enqueueNoWait*[T](q: BlockingQueue[T], item: T) =
  q.lock.acquire

  if q.queue.len < q.maxSize:
    logger.info "enqueuing item"
    q.queue.add(item)
    q.notEmpty.signal

  q.lock.release

proc dequeue*[T](q: BlockingQueue[T]): T =
  q.lock.acquire

  while q.queue.len == 0:
    logger.info "queue is empty, waiting"
    q.notEmpty.wait(q.lock)

  logger.info "dequeueing item"
  result = q.queue.pop
  q.notFull.signal

  q.lock.release

proc dequeueNoWait*[T](q: BlockingQueue[T]): T =
  q.lock.acquire

  if q.queue.len > 0:
    logger.info "dequeueing item"
    result = q.queue.pop
    q.notFull.signal

  q.lock.release
