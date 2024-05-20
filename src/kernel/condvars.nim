import std/deques

import locks
import sched
import taskdef
import taskmgr

type
  CondVar* = ref object of RootObj
    lock: Lock
    waiters: Deque[Task]

proc newCondVar*(): CondVar =
  result = CondVar(
    lock: newMutex()
  )

proc wait*(cv: CondVar, wl: var Lock) =
  # lock the condvar while we add ourselves to the waiters list
  cv.lock.acquire()
  cv.waiters.addLast(getCurrentTask())
  cv.lock.release()

  # release the waiter lock and wait for a signal
  wl.release()
  suspend()

  # we have been signaled, reacquire the waiter lock and return
  wl.acquire()

proc signal*(cv: CondVar) =
  # lock the condvar while we (potentially) remove a waiter 
  cv.lock.acquire()

  # signal the first waiter (if any)
  if cv.waiters.len > 0:
    cv.waiters.popFirst().resume()

  cv.lock.release()

proc broadcast*(cv: CondVar) =
  # lock the condvar while we (potentially) remove all waiters
  cv.lock.acquire()

  # signal all waiters
  while cv.waiters.len > 0:
    cv.waiters.popFirst().resume()

  cv.lock.release()
