#[
  Task scheduler
]#

import std/[heapqueue, sequtils]

import ctxswitch
import lapic
import stopwatch as sw
import taskdef

let logger = DebugLogger(name: "sched")

proc cmpPriority(a, b: Task): bool {.inline.} =
  a.priority > b.priority

var
  readyTasks = initHeapQueue[Task](cmp = cmpPriority)
  currentTask {.exportc.}: Task
  stopwatch: Stopwatch

proc `==`(a, b: Task): bool = a.id == b.id

proc getCurrentTask*(): Task = currentTask

proc addTask*(t: Task) =
  if not currentTask.isNil and currentTask == t:
    return

  let idx = readyTasks.find(t)
  if idx < 0:
    readyTasks.push(t)

proc removeTask*(t: Task) =
  let idx = readyTasks.find(t)
  if idx >= 0:
    readyTasks.del(idx)

proc schedule*() =
  if readyTasks.len == 0:
    # logger.info &"no ready tasks, scheduling same task"
    return

  let elapsedTicks = stopwatch.split()
  let elapsedMs = ticksToDuration(elapsedTicks)

  if not currentTask.isNil and currentTask.state == Running:
    if currentTask.id != 0:  # skip the idle task
      # adjust the remaining quantum
      dec currentTask.remainingQuantumMs, elapsedMs
      if currentTask.remainingQuantumMs > 0:
        # the task still has some time left
        return

    if currentTask.priority > readyTasks[0].priority:
      # the current task has higher priority than the next task
      # logger.info &"no higher priority task, scheduling same task"
      return

    # put the current task back into the queue
    currentTask.state = TaskState.Ready
    readyTasks.push(currentTask)

  # switch to the task with the highest priority
  var nextTask = readyTasks.pop()

  logger.info &"switching -> {nextTask.id}"
  switchTo(nextTask)

proc schedInit*(tasks: openArray[Task]) =
  tasks.apply(addTask)
  stopwatch = newStopwatch()
  stopwatch.start()
