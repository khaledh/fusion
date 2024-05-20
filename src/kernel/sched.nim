#[
  Task scheduler
]#

import std/heapqueue

import ctxswitch
import taskdef

{.experimental: "codeReordering".}

var
  readyTasks = initHeapQueue[Task]()
  currentTask {.exportc.}: Task

proc `<`(a, b: Task): bool = a.priority > b.priority
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
  # let currentTaskStr = if not currentTask.isNil: $currentTask.id else: "nil"
  # debugln &"sched: currentTask = {currentTaskStr}"
  # let readyTasksStr = $readyTasks
  # debugln &"sched: readyTasks = {readyTasksStr}"
  if readyTasks.len == 0:
    # debugln &"sched: no ready tasks, scheduling same task"
    return

  if not currentTask.isNil and currentTask.state == Running:
    if currentTask.priority > readyTasks[0].priority:
      # the current task has higher priority than the next task
      # debugln &"sched: no higher priority task, scheduling same task"
      return
    # put the current task back into the queue
    currentTask.state = TaskState.Ready
    readyTasks.push(currentTask)

  # switch to the task with the highest priority
  var nextTask = readyTasks.pop()

  debugln &"sched: switching -> {nextTask.id}"

  # if currentTask.isNil or currentTask.state == Terminated:
  #   debugln &"sched: switching -> {nextTask.id}"
  # else:
  #   debugln &"sched: switching {currentTask.id} -> {nextTask.id}"

  switchTo(nextTask)
