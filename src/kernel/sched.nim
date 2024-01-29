import std/[deques, strformat]

import cpu
import ctxswitch
import debugcon
import tasks

{.experimental: "codeReordering".}

var
  taskQ = initDeque[Task]()
  currentTask* {.exportc.}: Task

proc addTask*(t: Task) =
  taskQ.addLast(t)

proc removeCurrent*() =
  # TODO: free resources
  currentTask = nil

  if taskQ.len == 0:
    debugln &"sched: no tasks left"
    halt()

  schedule()

proc schedule*() =
  if taskQ.len == 0:
    # no other tasks, just keep running the current one
    return

  if not currentTask.isNil:
    # put the current task back into the queue
    currentTask.state = TaskState.Ready
    taskQ.addLast(currentTask)

  # switch to the first task in the queue
  var nextTask = taskQ.popFirst()

  if currentTask.isNil:
    debugln &"sched: switching -> {nextTask.id}"
  else:
    debugln &"sched: switching {currentTask.id} -> {nextTask.id}"
  
  var prevTask = currentTask
  currentTask = nextTask
  switchTask(prevTask, currentTask)
