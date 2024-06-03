#[
  Task scheduler
]#

import std/heapqueue

import ctxswitch
import taskdef

{.experimental: "codeReordering".}

let logger = DebugLogger(name: "sched")

proc cmpPriority(a, b: Task): bool {.inline.} =
  a.priority > b.priority

var
  readyTasks = initHeapQueue[Task](cmp = cmpPriority)
  currentTask {.exportc.}: Task

proc `==`(a, b: Task): bool = a.id == b.id

proc getCurrentTask*(): Task {.inline.} = currentTask

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

  if not currentTask.isNil and currentTask.state == Running:
    if readyTasks.len == 1 and readyTasks[0].id == 0:
      # only the idle task is ready, no need to switch
      return

    if currentTask.priority > readyTasks[0].priority:
      # the current task has higher priority than the next task
      # logger.info &"no higher priority task, scheduling same task"
      return

    # otherwise, put the current task back into the queue
    currentTask.state = TaskState.Ready
    readyTasks.push(currentTask)

  # switch to the task with the highest priority
  var nextTask = readyTasks.pop()

  # logger.info &"switching -> {nextTask.id}"

  # if currentTask.isNil or currentTask.state == Terminated:
  #   logger.info &"switching -> {nextTask.id}"
  # else:
  #   logger.info &"switching {currentTask.id} -> {nextTask.id}"

  switchTo(nextTask)
