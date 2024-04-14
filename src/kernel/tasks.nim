import std/options
import std/strformat

import common/pagetables
import cpu
import debugcon
import elf
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

template orRaise[T](opt: Option[T], exc: ref Exception): T =
  if opt.isSome:
    opt.get
  else:
    raise exc

proc createTask*(imagePhysAddr: PhysAddr, imagePageCount: uint64): Task =
  new(result)

  let taskId = nextId
  inc nextId

  result.vmRegions = @[]
  result.pml4 = cast[ptr PML4Table](new PML4Table)

  # allocate user image vm region
  # let imageRegion = vmalloc(uspace, imagePageCount).orRaise(
  #   newException(Exception, "tasks: Failed to allocate VM region for user image")
  # )
  # vmmap(imageRegion, result.pml4, paReadWrite, pmUser)
  let loadedImage = elf.load(imagePhysAddr, result.pml4)
  let imageRegion = loadedImage.mapRegion
  let entryPoint = loadedImage.entryPoint

  result.vmRegions.add(imageRegion)

  result.vaddr = imageRegion.start
  debugln &"kernel: User image virt addr: {result.vaddr.uint64:#x}"

  mapRegion(
    pml4 = result.pml4,
    virtAddr = result.vaddr,
    physAddr = imagePhysAddr,
    pageCount = imagePageCount,
    pageAccess = paReadWrite,
    pageMode = pmUser,
  )

  # temporarily map the user image in kernel space
  var kpml4 = getActivePML4()
  mapRegion(
    pml4 = kpml4,
    virtAddr = result.vaddr,
    physAddr = imagePhysAddr,
    pageCount = imagePageCount,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
  )
  halt()

  # apply relocations to user image
  debugln "kernel: Applying relocations to user image"
  applyRelocations(cast[ptr UncheckedArray[byte]](result.vaddr))

  # map kernel space
  for i in 256 ..< 512:
    result.pml4.entries[i] = kpml4.entries[i]

  # create user and kernel stacks
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


proc terminateTask*(task: var Task) =
  # vmfree(task.space, task.ustack.data, task.ustack.size div PageSize)
  # vmfree(task.space, task.kstack.data, task.kstack.size div PageSize)
  task.state = TaskState.Terminated
