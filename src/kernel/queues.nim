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
    q.notFull.wait(q.lock)
  q.queue.add(item)
  q.notEmpty.signal

  q.lock.release

proc enqueueNoWait*[T](q: BlockingQueue[T], item: T) =
  q.lock.acquire

  if q.queue.len < q.maxSize:
    q.queue.add(item)
    q.notEmpty.signal

  q.lock.release

proc dequeue*[T](q: BlockingQueue[T]): T =
  q.lock.acquire

  while q.queue.len == 0:
    q.notEmpty.wait(q.lock)
  result = q.queue.pop
  q.notFull.signal

  q.lock.release

proc dequeueNoWait*[T](q: BlockingQueue[T]): T =
  q.lock.acquire

  if q.queue.len > 0:
    result = q.queue.pop
    q.notFull.signal

  q.lock.release
