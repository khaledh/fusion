import gdt
import tasks
import vmm

{.experimental: "codeReordering".}

var
  currentTask {.importc.}: Task


proc switchTask*(curr, next: Task) =
  # debugln &"kernel: Switching to task {task.id}"
  # debugln &"kernel: task.ustack.bottom = {task.ustack.bottom:#x}"
  # debugln &"kernel: task.kstack.bottom = {task.kstack.bottom:#x}"
  # debugln &"kernel: task.rsp = {task.rsp:#x}"
  # debugln &"kernel: task.space.pml4 = {cast[uint64](task.space.pml4):#x}"
  tss.rsp0 = next.kstack.bottom
  let rsp = next.rsp
  setActivePML4(next.space.pml4)

  # debugln &"kernel: oldTask.state = {oldTask.state}"
  # debugln &"kernel: newTask.state = {currentTask.state}"

  if not curr.isNil and curr.state != TaskState.Terminated:
    curr.state = TaskState.Ready

  currentTask = next

  if next.state == TaskState.New:
    next.state = TaskState.Running
    if curr.isNil:
      returnToNewTask(next)
    else:
      switchToNewTask(curr, next)
  else:
    next.state = TaskState.Running
    switchContext(curr, next)


template pushRegs() =
  asm """
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
  """

template popRegs() =
  asm """
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
  """

proc returnToNewTask(t: Task) {.asmNoStackFrame, noreturn.} =
  asm """
    mov rsp, [rdi]  # load from t.rsp
    iretq
  """

proc switchToNewTask(curr, next: Task) {.asmNoStackFrame, noreturn.} =
  pushRegs()
  asm """
    mov [rdi], rsp  # save to curr.rsp  
    mov rsp, [rsi]  # load from next.rsp
    iretq
  """

proc switchContext*(curr: Task, next: Task) {.asmNoStackFrame.} =
  pushRegs()
  asm """
    mov [rdi], rsp  # save to curr.rsp  
    mov rsp, [rsi]  # load from next.rsp
  """
  popRegs()
  asm """
    ret
  """
