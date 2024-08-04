#[
  Low-level context switching
]#

import cpu
import gdt
import taskdef
import vmm

var
  currentTask {.importc.}: Task


proc resume(task: Task) {.asmNoStackFrame.}
proc switch(old: Task, new: Task) {.asmNoStackFrame.}

proc switchTo*(next: var Task) =
  # set the TSS rsp0 to the new task's kernel stack
  tss.rsp0 = next.kstack.bottom
  # activate the new task's page tables
  setActivePML4(next.pml4)

  var oldTask = currentTask
  currentTask = next
  currentTask.state = TaskState.Running

  if oldTask.isNil or oldTask.state == TaskState.Terminated:
    resume(currentTask)
  else:
    switch(oldTask, currentTask)

proc resume(task: Task) {.asmNoStackFrame.} =
  asm """
    mov rsp, [rdi]
    jmp returnToTask
  """

proc switch(old: Task, new: Task) {.asmNoStackFrame.} =
  pushRegs()
  asm """
    # switch stacks
    mov [rdi], rsp
    mov rsp, [rsi]
    jmp returnToTask
  """

proc returnToTask() {.asmNoStackFrame, exportc.} =
  popRegs()
  asm "ret"
