#[
  Context switching
]#

import cpu
import gdt
import taskdef
import vmm

{.experimental: "codeReordering".}

var
  currentTask {.importc.}: Task

proc switchTo*(next: var Task) =
  tss.rsp0 = next.kstack.bottom
  setActivePML4(next.pml4)

  var oldTask = currentTask
  currentTask = next
  currentTask.state = TaskState.Running

  if oldTask.isNil or oldTask.state == TaskState.Terminated:
    doBecome(currentTask)
  else:
    doSwitch(oldTask, currentTask)

proc doBecome(task: Task) {.asmNoStackFrame.} =
  asm """
    mov rsp, [rdi]
    jmp resumeTask
  """

proc doSwitch(old: Task, new: Task) {.asmNoStackFrame.} =
  pushRegs()
  asm """
    # switch stacks
    mov [rdi], rsp
    mov rsp, [rsi]
    jmp resumeTask
  """

proc resumeTask() {.asmNoStackFrame, exportc.} =
  popRegs()
  asm """
    sti
    ret
  """
