#[
  Task management
]#

import std/heapqueue

import common/pagetables
import lapic
import elfloader
import gdt
import sched
import timer
import task
import vmdefs, vmmgr, vmpagetbl, vmspace, vmobject


let
  logger = DebugLogger(name: "taskmgr")

proc cmpSleepUntil(a, b: Task): bool {.inline.} =
  a.sleepUntil < b.sleepUntil

const
  TaskUserStackPages = 8    # 32 KiB
  TaskKernelStackPages = 4  # 16 KiB

var
  tasks = newSeq[Task]()
  sleepers = initHeapQueue[Task](cmp = cmpSleepUntil)
  nextTaskId: uint64 = 0


proc wakeupTasks*()

proc taskmgrInit*() =
  timer.registerCallback(wakeupTasks)

proc iretq*() {.asmNoStackFrame.} =
  ## We push the address of this proc after the interrupt stack frame so that a simple
  ## `ret` instruction will execute this proc, which then returns to the new task. This
  ## makes returning from both new and interrupted tasks the same.
  asm "iretq"

proc createUserStack*(pml4: ptr PML4Table, npages: uint64): TaskStack =
  let guardPage = usAlloc(1)
  let mapping = uvMapAt(
    pml4 = pml4,
    vaddr = guardPage.start +! PageSize.uint64,
    npages = npages,
    perms = {pRead, pWrite},
    flags = {vmPrivate},
  )
  result.vmMapping = mapping
  discard usAllocAt(mapping.region.end, 1)

  result.data = cast[ptr UncheckedArray[uint64]](mapping.region.start)
  result.size = npages * PageSize
  result.bottom = cast[uint64](result.data) + result.size

proc createKernelStack*(npages: uint64): TaskStack =
  let guardPage = ksAlloc(1)
  let mappingForKernel = kvMapAt(
    vaddr = guardPage.start +! PageSize.uint64,
    npages = npages,
    perms = {pRead, pWrite},
    flags = {vmPrivate},
  )
  result.vmMapping = mappingForKernel
  kvmMappings.add(mappingForKernel)
  
  result.data = cast[ptr UncheckedArray[uint64]](mappingForKernel.region.start)
  result.size = npages * PageSize
  result.bottom = cast[uint64](result.data) + result.size

# New task stack frame
#
# Steps when task is about to execute:
# 1. `ctxswitch.resume` loads `rsp` with task.rsp and jumps to `ctxswitch.returnToTask`
# 2. `ctxswitch.returnToTask` pops the initial task registers (zeros) from the stack
# 3. `ctxswitch.returnToTask` executs `ret` which pops the `taskmgr.iretq` proc ptr into `rip`
# 4. `taskmgr.iretq` executes `iretq` causing the cpu to pop the `InterruptStackFrame` from the stack
#     a. `cs:rip` points to the task's entry point
#     b. `ss:rsp` points to the task's user stack
#     c. `rflags` is set to 0x202 (interrupts enabled)
# 5. The task begins execution using its user stack
#
#       1000 +-------------------+
#        ff8 | ss                | <-- stack bottom
#        ff0 | rsp               |
#        fe8 | rflags            | <-- `InterruptStackFrame` (pushed/popped by cpu)
#        fe0 | cs                |
#        fd8 | rip               |
#            +-------------------+
#        fd0 | iretq proc ptr    | <-- `ret` instruction will pop this into `rip`, which
#            +-------------------+     will execute `iretq`
#        fc8 | rax               |
#            | ...               |
#            | ...               | <-- `TaskRegs` (pushed/popped by kernel)
#            | ...               |
#        f58 | r15               | <-- rsp
#            +-------------------+


proc createUserTask*(
  imagePhysAddr: PAddr,
  imagePageCount: uint64,
  name: string = "",
  priority: TaskPriority = 0
): Task =
  logger.info "Creating user task"

  var pml4 = newPageTable()

  logger.info &"Loading task from ELF image"
  let imagePtr = cast[pointer](p2v(imagePhysAddr))
  let newLoadedImage = loadElfImage(imagePtr, pml4)

  logger.info &"Creating user and kernel stacks"
  let ustack = createUserStack(pml4, TaskUserStackPages)
  let kstack = createKernelStack(TaskKernelStackPages)

  # map kernel space
  for i in 256 ..< 512:
    pml4.entries[i] = kpml4.entries[i]

  # create stack frame
  # logger.info &"setting up interrupt stack frame"
  let isfAddr = kstack.bottom - sizeof(InterruptStackFrame).uint64
  var isf = cast[ptr InterruptStackFrame](isfAddr)
  isf.ss = cast[uint64](DataSegmentSelector)
  isf.rsp = cast[uint64](ustack.bottom)
  isf.rflags = cast[uint64](0x202)
  isf.cs = cast[uint64](UserCodeSegmentSelector)
  isf.rip = cast[uint64](newLoadedImage.entryPoint)

  # logger.info &"setting up iretq proc ptr"
  let iretqPtrAddr = isfAddr - sizeof(uint64).uint64
  var iretqPtr = cast[ptr uint64](iretqPtrAddr)
  iretqPtr[] = cast[uint64](iretq)

  # logger.info &"setting up task registers"
  let regsAddr = iretqPtrAddr - sizeof(TaskRegs).uint64
  var regs = cast[ptr TaskRegs](regsAddr)
  zeroMem(regs, sizeof(TaskRegs))

  let taskId = nextTaskId
  inc nextTaskId

  result = Task(
    id: taskId,
    name: name,
    priority: priority,
    pml4: pml4,
    ustack: ustack,
    kstack: kstack,
    rsp: regsAddr,
    state: TaskState.New,
    isUser: true,
  )

  # add all vm mappings to the task
  result.vmMappings.add(newLoadedImage.vmMappings)
  result.vmMappings.add(ustack.vmMapping)

  tasks.add(result)

  logger.info &"Created user task {taskId}"
  logger.info &"  Base: {newLoadedImage.base.uint64:#x}"
  logger.info &"  Entry point: {newLoadedImage.entryPoint.uint64:#x}"


########################################################
# Kernel task management
########################################################

type
  KernelProc* = proc () {.cdecl.}

proc terminate*()

proc kernelTaskWrapper*(kproc: KernelProc) =
  logger.info &"starting kernel task \"{getCurrentTask().name}\""
  kproc()
  terminate()

proc createKernelTask*(kproc: KernelProc, name: string = "", priority: TaskPriority = 0): Task =

  var pml4 = getActivePageTable()

  logger.info &"Creating kernel task \"{name}\""
  let kstack = createKernelStack(TaskKernelStackPages)

  # create stack frame

  let isfAddr = kstack.bottom - sizeof(InterruptStackFrame).uint64
  var isf = cast[ptr InterruptStackFrame](isfAddr)
  isf.ss = 0  # kernel ss selector must be null
  isf.rsp = cast[uint64](kstack.bottom)
  isf.rflags = cast[uint64](0x002)  # disable interrupts on entry
  isf.cs = cast[uint64](KernelCodeSegmentSelector)
  isf.rip = cast[uint64](kernelTaskWrapper)

  # logger.info &"setting up iretq proc ptr"
  let iretqPtrAddr = isfAddr - sizeof(uint64).uint64
  var iretqPtr = cast[ptr uint64](iretqPtrAddr)
  iretqPtr[] = cast[uint64](iretq)

  # logger.info &"setting up task registers"
  let regsAddr = iretqPtrAddr - sizeof(TaskRegs).uint64
  var regs = cast[ptr TaskRegs](regsAddr)
  zeroMem(regs, sizeof(TaskRegs))
  regs.rdi = cast[uint64](kproc)  # pass kproc as an argument to kernelTaskWrapper

  let taskId = nextTaskId
  inc nextTaskId

  result = Task(
    id: taskId,
    name: name,
    priority: priority,
    pml4: pml4,
    kstack: kstack,
    rsp: regsAddr,
    state: TaskState.New,
    isUser: false,
  )
  result.vmMappings.add(kstack.vmMapping)

  tasks.add(result)

  logger.info &"Created kernel task {taskId}"

########################################################
# Task operations on self
###

proc suspend*() =
  var task = sched.getCurrentTask()
  logger.info &"suspending task {task.id}"
  task.state = TaskState.Suspended
  sched.removeTask(task)
  sched.schedule()
  logger.info &"resumed task {task.id}"

proc sleep*(durationMs: uint64) =
  var task = sched.getCurrentTask()
  logger.info &"task {task.id} sleeping for {durationMs} ms"
  task.sleepUntil = getFutureTicks(durationMs)
  task.state = TaskState.Sleeping
  sleepers.push(task)
  sched.removeTask(task)
  sched.schedule()

proc terminate*() =
  var task = sched.getCurrentTask()
  logger.info &"terminating task {task.id}"

  # Clean up VmObjects
  for mapping in task.vmMappings:
    cleanupVmObject(mapping.vmo)

  task.state = TaskState.Terminated
  sched.removeTask(task)
  sched.schedule()

########################################################
# Task operations on other tasks
########################################################

proc resume*(task: Task) =
  logger.info &"setting task {task.id} to ready"
  task.state = TaskState.Ready
  sched.addTask(task)


proc wakeupTasks*() =
  if sleepers.len == 0:
    return

  let now = getCurrentTicks()

  # logger.info &"waking up tasks, sleepers.len: {sleepers.len}"
  # logger.info &"now: {now}"
  # for i in 0 ..< sleepers.len:
  #   logger.info &"sleepers[{i}].id: {sleepers[i].id}, sleepers[{i}].sleepUntil: {sleepers[i].sleepUntil}"

  while sleepers.len > 0 and sleepers[0].sleepUntil <= now:
    let task = sleepers.pop()
    logger.info &"waking up task {task.id}"
    task.state = TaskState.Ready
    sched.addTask(task)
