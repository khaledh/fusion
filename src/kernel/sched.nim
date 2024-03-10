import std/[deques, strformat]

import cpu
import ctxswitch
import debugcon
import tasks

{.experimental: "codeReordering".}

var
  readyTasks = initDeque[Task]()
  currentTask {.exportc.}: Task

proc getCurrentTask*(): var Task = currentTask

proc addTask*(t: Task) =
  readyTasks.addLast(t)

proc schedule*() =
  if readyTasks.len == 0:
    if currentTask.isNil or currentTask.state == Terminated:
      debugln &"sched: no tasks to run, halting"
      halt()
    else:
      # no ready tasks, keep running the current task
      return

  if not (currentTask.isNil or currentTask.state == Terminated):
    # put the current task back into the queue
    currentTask.state = TaskState.Ready
    readyTasks.addLast(currentTask)

  # switch to the first task in the queue
  var nextTask = readyTasks.popFirst()

  if currentTask.isNil:
    debugln &"sched: switching -> {nextTask.id}"
  else:
    debugln &"sched: switching {currentTask.id} -> {nextTask.id}"
  
  switchTo(nextTask)
