import std/options
import std/strformat

import common/pagetables
import debugcon
import loader
import gdt
import pmm
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
    vaddr*: VirtAddr
  
  TaskState* = enum
    New
    Ready
    Running
    Terminated

var
  nextId: uint64 = 0


template orRaise[T](opt: Option[T], exc: ref Exception): T =
  if opt.isSome:
    opt.get
  else:
    raise exc

proc createStack*(task: var Task, space: var VMAddressSpace, npages: uint64, mode: PageMode): TaskStack =
  let stackRegionOpt = vmalloc(space, npages)
  if stackRegionOpt.isNone:
    raise newException(Exception, "tasks: Failed to allocate stack")
  let stackRegion = stackRegionOpt.get
  vmmap(stackRegion, task.pml4, paReadWrite, mode)
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

  debugln &"kernel: Loading task from ELF image"
  let loadedImage = load(imagePhysAddr, result.pml4)
  let imageRegion = loadedImage.vmRegion
  let entryPoint = loadedImage.entryPoint

  result.vmRegions.add(imageRegion)

  result.vaddr = imageRegion.start
  debugln &"kernel: Task loaded at: {result.vaddr.uint64:#x}"

  # map kernel space
  debugln &"kernel: Mapping kernel space in task's page table"
  var kpml4 = getActivePML4()
  for i in 256 ..< 512:
    result.pml4.entries[i] = kpml4.entries[i]

  # create user and kernel stacks
  debugln &"kernel: Creating task stacks"
  let ustack = createStack(result, uspace, 1, pmUser)
  let kstack = createStack(result, kspace, 1, pmSupervisor)

  # create interrupt stack frame
  var index = kstack.size div 8
  kstack.data[index - 1] = cast[uint64](DataSegmentSelector) # SS
  kstack.data[index - 2] = cast[uint64](ustack.bottom) # RSP
  kstack.data[index - 3] = cast[uint64](0x202) # RFLAGS
  kstack.data[index - 4] = cast[uint64](UserCodeSegmentSelector) # CS
  kstack.data[index - 5] = cast[uint64](entryPoint) # RIP

  result.id = taskId
  result.ustack = ustack
  result.kstack = kstack
  result.rsp = cast[uint64](kstack.data[index - 5].addr)
  result.state = TaskState.New

  debugln &"kernel: Task {taskId} created"


proc terminateTask*(task: var Task) =
  # vmfree(task.space, task.ustack.data, task.ustack.size div PageSize)
  # vmfree(task.space, task.kstack.data, task.kstack.size div PageSize)
  task.state = TaskState.Terminated
