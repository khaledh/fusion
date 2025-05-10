#[
  Task management
]#

import std/heapqueue

import common/pagetables
import lapic
import loader
import gdt
import sched
import timer
import taskdef
import vmm


let
  logger = DebugLogger(name: "taskmgr")

proc cmpSleepUntil(a, b: Task): bool {.inline.} =
  a.sleepUntil < b.sleepUntil

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

proc createStack*(
  vmRegions: var seq[VMRegion],
  pml4: ptr PML4Table,
  space: var VMAddressSpace,
  npages: uint64,
  mode: PageMode
): TaskStack =
  let stackRegion = vmalloc(space, npages)
  vmmap(stackRegion, pml4, paReadWrite, mode, noExec = true)
  vmRegions.add(stackRegion)
  result.data = cast[ptr UncheckedArray[uint64]](stackRegion.start)
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
#            +-------------------+
#      0xfff | ss                | <-- stack bottom
#            | rsp               |
#            | rflags            | <-- `InterruptStackFrame` (pushed/popped by cpu)
#            | cs                |
#            | rip               |
#            +-------------------+
#      0xfd8 | iretq proc ptr    | <-- `ret` instruction will pop this into `rip`, which
#            +-------------------+     will execute `iretq`
#      0xfd0 | rax               |
#            | ...               |
#            | ...               | <-- `TaskRegs` (pushed/popped by kernel)
#            | ...               |
#      0xf58 | r15               | <-- rsp
#            +-------------------+
#

proc createUserTask*(
  imagePhysAddr: PhysAddr,
  imagePageCount: uint64,
  name: string = "",
  priority: TaskPriority = 0
): Task =

  var vmRegions = newSeq[VMRegion]()
  var pml4 = cast[ptr PML4Table](new PML4Table)

  logger.info &"loading task from ELF image"
  let imagePtr = cast[pointer](p2v(imagePhysAddr))
  let loadedImage = load(imagePtr, pml4)
  vmRegions.add(loadedImage.vmRegion)
  logger.info &"loaded task at: {loadedImage.vmRegion.start.uint64:#x}"

  # map kernel space
  # logger.info &"mapping kernel space in task's page table"
  for i in 256 ..< 512:
    pml4.entries[i] = kpml4.entries[i]

  # create user and kernel stacks
  # logger.info &"creating task stacks"
  let ustack = createStack(vmRegions, pml4, uspace, 1, pmUser)
  let kstack = createStack(vmRegions, pml4, kspace, 1, pmSupervisor)

  # create stack frame

  # logger.info &"setting up interrupt stack frame"
  let isfAddr = kstack.bottom - sizeof(InterruptStackFrame).uint64
  var isf = cast[ptr InterruptStackFrame](isfAddr)
  isf.ss = cast[uint64](DataSegmentSelector)
  isf.rsp = cast[uint64](ustack.bottom)
  isf.rflags = cast[uint64](0x202)
  isf.cs = cast[uint64](UserCodeSegmentSelector)
  isf.rip = cast[uint64](loadedImage.entryPoint)

  # logger.info &"setting up iretq proc ptr"
  let iretqPtrAddr = isfAddr - sizeof(uint64).uint64
  var iretqPtr = cast[ptr uint64](iretqPtrAddr)
  iretqPtr[] = cast[uint64](iretq)

  # logger.info &"setting up task registers"
  let regsAddr = iretqPtrAddr - sizeof(TaskRegs).uint64
  var regs = cast[ptr TaskRegs](regsAddr)
  zeroMem(regs, sizeof(TaskRegs))
  regs.rdi = 5050

  let taskId = nextTaskId
  inc nextTaskId

  result = Task(
    id: taskId,
    name: name,
    priority: priority,
    vmRegions: vmRegions,
    pml4: pml4,
    ustack: ustack,
    kstack: kstack,
    rsp: regsAddr,
    state: TaskState.New,
    isUser: true,
  )

  tasks.add(result)

  logger.info &"created user task {taskId}"

type
  KernelProc* = proc () {.cdecl.}

proc terminate*()

proc kernelTaskWrapper*(kproc: KernelProc) =
  logger.info &"starting kernel task \"{getCurrentTask().name}\""
  kproc()
  terminate()

proc createKernelTask*(kproc: KernelProc, name: string = "", priority: TaskPriority = 0): Task =

  var vmRegions = newSeq[VMRegion]()
  var pml4 = getActivePML4()

  logger.info &"creating kernel task \"{name}\""
  let kstack = createStack(vmRegions, pml4, kspace, 1, pmSupervisor)

  # create stack frame

  # logger.info &"setting up interrupt stack frame"
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
    vmRegions: vmRegions,
    pml4: pml4,
    kstack: kstack,
    rsp: regsAddr,
    state: TaskState.New,
    isUser: false,
  )
  tasks.add(result)

  logger.info &"created kernel task {taskId}"

###
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
  task.state = TaskState.Terminated
  # vmfree(task.space, task.ustack.data, task.ustack.size div PageSize)
  # vmfree(task.space, task.kstack.data, task.kstack.size div PageSize)
  sched.removeTask(task)
  sched.schedule()

###
# Task operations on other tasks
###

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
