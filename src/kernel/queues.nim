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
  debugln("blockingQ.enqueue: acquiring lock")
  q.lock.acquire
  debugln("blockingQ.enqueue: acquired lock")
  while q.queue.len == q.maxSize:
    debugln("blockingQ.enqueue: waiting for notFull")
    q.notFull.wait(q.lock)
    debugln("blockingQ.enqueue: notFull signaled")
  debugln("blockingQ.enqueue: adding item")
  q.queue.add(item)
  debugln("blockingQ.enqueue: signaling notEmpty")
  q.notEmpty.signal
  debugln("blockingQ.enqueue: releasing lock")
  q.lock.release

proc enqueueNoWait*[T](q: BlockingQueue[T], item: T) =
  q.lock.acquire
  if q.queue.len < q.maxSize:
    q.queue.add(item)
    q.notEmpty.signal
  q.lock.release

proc dequeue*[T](q: BlockingQueue[T]): T =
  debugln("blockingQ.dequeue: acquiring lock")
  q.lock.acquire
  debugln("blockingQ.dequeue: acquired lock")
  while q.queue.len == 0:
    debugln("blockingQ.dequeue: waiting for notEmpty")
    q.notEmpty.wait(q.lock)
    debugln("blockingQ.dequeue: notEmpty signaled")
  debugln("blockingQ.dequeue: popping item")
  result = q.queue.pop
  debugln("blockingQ.dequeue: signaling notFull")
  q.notFull.signal
  debugln("blockingQ.dequeue: releasing lock")
  q.lock.release
  debugln("blockingQ.dequeue: released lock")

proc dequeueNoWait*[T](q: BlockingQueue[T]): T =
  debugln("blockingQ.dequeueNoWait: acquiring lock")
  q.lock.acquire
  debugln("blockingQ.dequeueNoWait: acquired lock")
  if q.queue.len > 0:
    debugln("blockingQ.dequeueNoWait: popping item")
    result = q.queue.pop
    debugln("blockingQ.dequeueNoWait: signaling notFull")
    q.notFull.signal
  debugln("blockingQ.dequeueNoWait: releasing lock")
  q.lock.release
