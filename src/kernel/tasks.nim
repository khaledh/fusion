#[
  Task management
]#

import common/pagetables
import debugcon
import loader
import gdt
import vmm

{.experimental: "codeReordering".}

type
  TaskStack* = object
    data*: ptr UncheckedArray[uint64]
    size*: uint64
    bottom*: uint64

  Task* = ref object
    rsp*: uint64
    id*: uint64
    vmRegions*: seq[VMRegion]
    pml4*: ptr PML4Table
    ustack*: TaskStack
    kstack*: TaskStack
    state*: TaskState
  
  TaskState* = enum
    New
    Ready
    Running
    Terminated

var
  nextId: uint64 = 0


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

  result.vmRegions = @[]
  result.pml4 = cast[ptr PML4Table](new PML4Table)

  debugln &"tasks: Loading task from ELF image"
  let loadedImage = load(imagePhysAddr, result.pml4)
  result.vmRegions.add(loadedImage.vmRegion)
  debugln &"tasks: Loaded task at: {loadedImage.vmRegion.start.uint64:#x}"

  # map kernel space
  debugln &"tasks: Mapping kernel space in task's page table"
  var kpml4 = getActivePML4()
  for i in 256 ..< 512:
    result.pml4.entries[i] = kpml4.entries[i]

  # create user and kernel stacks
  debugln &"tasks: Creating task stacks"
  let ustack = createStack(result, uspace, 1, pmUser)
  let kstack = createStack(result, kspace, 1, pmSupervisor)

  # create interrupt stack frame
  debugln &"tasks: Setting up interrupt stack frame"
  var index = kstack.size div 8
  kstack.data[index - 1] = cast[uint64](DataSegmentSelector) # ss
  kstack.data[index - 2] = cast[uint64](ustack.bottom) # rsp
  kstack.data[index - 3] = cast[uint64](0x202) # rflags
  kstack.data[index - 4] = cast[uint64](UserCodeSegmentSelector) # cs
  kstack.data[index - 5] = cast[uint64](loadedImage.entryPoint) # rip

  result.id = taskId
  result.ustack = ustack
  result.kstack = kstack
  result.rsp = cast[uint64](kstack.data[index - 5].addr)
  result.state = TaskState.New

  debugln &"tasks: Created user task {taskId}"


proc terminateTask*(task: var Task) =
  debugln &"tasks: Terminating task {task.id}"
  # vmfree(task.space, task.ustack.data, task.ustack.size div PageSize)
  # vmfree(task.space, task.kstack.data, task.kstack.size div PageSize)
  task.state = TaskState.Terminated


type
  KernelProc[T] = proc (arg: T)

proc createKernelTask*[T](kproc: KernelProc[T], arg: T): Task =
  new(result)

  let taskId = nextId
  inc nextId

  result.vmRegions = @[]
  result.pml4 = getActivePML4()

  debugln &"tasks: Creating kernel task"
  let stack = createStack(result, kspace, 1, pmSupervisor)

  # create stack frame
  debugln &"tasks: Setting up stack frame"
  var index = stack.size div 8
  stack.data[index - 1] = cast[uint64](arg)
  stack.data[index - 2] = cast[uint64](kproc) # rip

  result.id = taskId
  result.kstack = stack
  result.rsp = cast[uint64](stack.data[index - 2].addr)
  result.state = TaskState.New

  debugln &"tasks: Created kernel task {taskId}"
