import std/deques

import sched
import task
import taskmgr


### atomic operations

proc cmpxchg*(location: var bool, expected: bool, newval: bool): bool {.inline.} =
  asm """
    lock cmpxchg %0, %3
    sete %1
    : "+m"(*`location`), "=q"(`result`)
    : "a"(`expected`), "r"(`newval`)
    : "memory"
  """

### Lock abstraction

type
  Lock* = ref object of RootObj
    locked*: bool = false

method acquire*(l: Lock) {.base.} =
  raise newException(CatchableError, "Method without implementation override")

method release*(l: Lock) {.base.} =
  raise newException(CatchableError, "Method without implementation override")

template withLock*(l: var Lock, body: untyped) =
  block:
    l.acquire()
    defer: l.release()
    body

### SpinLock

type
  SpinLock* = ref object of Lock

proc newSpinLock*(): SpinLock =
  result = SpinLock(locked: false)

method acquire*(s: SpinLock) =
  while true:
    while s.locked:
      asm "pause"
    if cmpxchg(s.locked, expected = false, newval = true):
      break

method release*(s: SpinLock) =
  s.locked = false


### Mutex

type
  Mutex* = ref object of Lock
    waiters*: Deque[Task]

proc newMutex*(): Mutex =
  result = Mutex(
    locked: false,
    waiters: initDeque[Task]()
  )

method acquire*(m: Mutex) =
  while not cmpxchg(m.locked, expected = false, newval = true):
    m.waiters.addLast(getCurrentTask())
    suspend()

method release*(m: Mutex) =
  if m.waiters.len > 0:
    let t = m.waiters.popFirst()
    resume(t)
  else:
    m.locked = false
