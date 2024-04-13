import std/strformat

import cpu
import debugcon
import gdt
import tasks
import vmm

{.experimental: "codeReordering".}

var
  currentTask {.importc.}: Task

proc switchTo*(next: var Task) =
  tss.rsp0 = next.kstack.bottom
  setActivePML4(next.pml4)

  if not (currentTask.isNil or currentTask.state == TaskState.Terminated):
    pushRegs()
    asm """
      mov %0, rsp
      : "=m" (`currentTask`->rsp)
    """

  currentTask = next

  case next.state
  of TaskState.New:
    next.state = TaskState.Running
    asm """
      mov rsp, %0
      iretq
      :
      : "m" (`currentTask`->rsp)
    """
  else:
    next.state = TaskState.Running
    asm """
      mov rsp, %0
      :
      : "m" (`currentTask`->rsp)
    """
    popRegs()
