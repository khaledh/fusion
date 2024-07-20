import std/deques

import locks
import sched
import taskdef
import taskmgr

type
  CondVar* = ref object of RootObj
    waiters: Deque[Task]
    lock: Lock

proc newCondVar*(): CondVar =
  result = CondVar(lock: newMutex())

proc wait*(cv: CondVar, wl: var Lock) =
  # lock the condvar while we add ourselves to the waiters list
  withLock(cv.lock):
    cv.waiters.addLast(getCurrentTask())

  # release the waiter lock and wait for a signal
  wl.release()
  suspend()

  # we have been signaled, reacquire the waiter lock and return
  wl.acquire()

proc signal*(cv: CondVar) =
  # lock the condvar while we (potentially) remove a waiter 
  withLock(cv.lock):
    # signal the first waiter (if any)
    if cv.waiters.len > 0:
      cv.waiters.popFirst().resume()

proc broadcast*(cv: CondVar) =
  # lock the condvar while we (potentially) remove all waiters
  withLock(cv.lock):
    # signal all waiters
    while cv.waiters.len > 0:
      cv.waiters.popFirst().resume()
