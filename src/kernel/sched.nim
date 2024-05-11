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

proc getCurrentTask*(): Task = currentTask

proc addTask*(t: Task) =
  readyTasks.push(t)

proc schedule*() =
  if readyTasks.len == 0:
    # debugln &"sched: no ready tasks, scheduling same task"
    return

  if not (currentTask.isNil or currentTask.state == Terminated):
    if currentTask.priority > readyTasks[0].priority:
      # the current task has higher priority than the next task
      # debugln &"sched: no higher priority task, scheduling same task"
      return
    # put the current task back into the queue
    currentTask.state = TaskState.Ready
    readyTasks.push(currentTask)

  # switch to the task with the highest priority
  var nextTask = readyTasks.pop()

  # if currentTask.isNil or currentTask.state == Terminated:
  #   debugln &"sched: switching -> {nextTask.id}"
  # else:
  #   debugln &"sched: switching {currentTask.id} -> {nextTask.id}"

  switchTo(nextTask)
