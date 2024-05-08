#[
  Task management
]#

import common/pagetables
import loader
import gdt
import sched
import taskdef
import vmm


{.experimental: "codeReordering".}

var
  nextId: uint64 = 0

proc iretq*() {.asmNoStackFrame.} =
  ## We push the address of this proc after the interrupt stack frame so that a simple
  ## `ret` instruction will execute this proc, which then returns to user mode. This
  ## makes returning from both user and kernel mode consistent using a `ret` instruction.
  asm "iretq"

proc createStack*(task: var Task, space: var VMAddressSpace, npages: uint64, mode: PageMode): TaskStack =
  let stackRegion = vmalloc(space, npages)
  vmmap(stackRegion, task.pml4, paReadWrite, mode, noExec = true)
  task.vmRegions.add(stackRegion)
  result.data = cast[ptr UncheckedArray[uint64]](stackRegion.start)
  result.size = npages * PageSize
  result.bottom = cast[uint64](result.data) + result.size

proc createTask*(imagePhysAddr: PhysAddr, imagePageCount: uint64): Task =
  new(result)

  let taskId = nextId
  inc nextId

  result.isUser = true
  result.vmRegions = @[]
  result.pml4 = cast[ptr PML4Table](new PML4Table)

  debugln &"tasks: Loading task from ELF image"
  let imagePtr = cast[pointer](p2v(imagePhysAddr))
  let loadedImage = load(imagePtr, result.pml4)
  result.vmRegions.add(loadedImage.vmRegion)
  debugln &"tasks: Loaded task at: {loadedImage.vmRegion.start.uint64:#x}"

  # map kernel space
  # debugln &"tasks: Mapping kernel space in task's page table"
  var kpml4 = getActivePML4()
  for i in 256 ..< 512:
    result.pml4.entries[i] = kpml4.entries[i]

  # create user and kernel stacks
  # debugln &"tasks: Creating task stacks"
  let ustack = createStack(result, uspace, 1, pmUser)
  let kstack = createStack(result, kspace, 1, pmSupervisor)

  # create stack frame
  #
  # stack
  # bottom --> +-------------------+
  #            | ss                |
  #            | rsp               |
  #            | rflags            | <-- `InterruptStackFrame` (pushed/popped by cpu)
  #            | cs                |
  #            | rip               |
  #            +-------------------+
  #            | iretq proc ptr    | <-- `ret` instruction will pop this into `rip`, which
  #            +-------------------+     will execute `iretq`
  #            | rax               |
  #            | ...               |
  #            | ...               | <-- `TaskRegs` (pushed/popped by kernel)
  #            | ...               |
  #    rsp --> | r15               |
  #            +-------------------+
  #
  # debugln &"tasks: Setting up interrupt stack frame"
  let isfAddr = kstack.bottom - sizeof(InterruptStackFrame).uint64
  var isf = cast[ptr InterruptStackFrame](isfAddr)
  isf.ss = cast[uint64](DataSegmentSelector)
  isf.rsp = cast[uint64](ustack.bottom)
  isf.rflags = cast[uint64](0x202)
  isf.cs = cast[uint64](UserCodeSegmentSelector)
  isf.rip = cast[uint64](loadedImage.entryPoint)

  # debugln &"tasks: Setting up iretq proc ptr"
  let iretqPtrAddr = isfAddr - sizeof(uint64).uint64
  var iretqPtr = cast[ptr uint64](iretqPtrAddr)
  iretqPtr[] = cast[uint64](iretq)

  # debugln &"tasks: Setting up task registers"
  let regsAddr = iretqPtrAddr - sizeof(TaskRegs).uint64
  var regs = cast[ptr TaskRegs](regsAddr)
  zeroMem(regs, sizeof(TaskRegs))

  result.id = taskId
  result.ustack = ustack
  result.kstack = kstack
  result.rsp = regsAddr
  result.state = TaskState.New

  debugln &"tasks: Created user task {taskId}"


proc terminateTask*(task: Task) =
  debugln &"tasks: Terminating task {task.id}"
  # vmfree(task.space, task.ustack.data, task.ustack.size div PageSize)
  # vmfree(task.space, task.kstack.data, task.kstack.size div PageSize)
  task.state = TaskState.Terminated


type
  KernelProc* = proc () {.cdecl.}

proc kernelTaskWrapper*(kproc: KernelProc) =
  kproc()
  terminateTask(getCurrentTask())
  schedule()

proc createKernelTask*(kproc: KernelProc): Task =
  new(result)

  let taskId = nextId
  inc nextId

  result.isUser = false
  result.vmRegions = @[]
  result.pml4 = getActivePML4()

  debugln &"tasks: Creating kernel task"
  let kstack = createStack(result, kspace, 1, pmSupervisor)

  # create stack frame
  #
  # stack
  # bottom --> +-------------------+
  #            | wrapper proc ptr  | <-- `ret` instruction will pop this into `rip`, which
  #            +-------------------+     will execute `kernelTaskWrapper`, which will call
  #            | rax               |     the kernel proc (passed as 1st argument in `rdi`)
  #            | ...               |
  #            | rdi (kproc ptr)   | <-- `TaskRegs` (pushed/popped by kernel)
  #            | ...               |
  #    rsp --> | r15               |
  #            +-------------------+
  #
  # debugln &"tasks: Setting up stack frame"
  let ripAddr = kstack.bottom - sizeof(uint64).uint64
  var rip = cast[ptr uint64](ripAddr)
  rip[] = cast[uint64](kernelTaskWrapper)

  let regsAddr = ripAddr - sizeof(TaskRegs).uint64
  var regs = cast[ptr TaskRegs](regsAddr)
  zeroMem(regs, sizeof(TaskRegs))
  regs.rdi = cast[uint64](kproc)

  result.id = taskId
  result.kstack = kstack
  result.rsp = regsAddr
  result.state = TaskState.New

  debugln &"tasks: Created kernel task {taskId}"
