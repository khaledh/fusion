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
    space*: VMAddressSpace
    id*: uint64
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

proc createStack*(space: var VMAddressSpace, npages: uint64, mode: PageMode): TaskStack =
  let stackPtr = vmalloc(space, npages, paReadWrite, mode)
  if stackPtr.isNone:
    raise newException(Exception, "tasks: Failed to allocate stack")
  result.data = cast[ptr UncheckedArray[uint64]](stackPtr.get)
  result.size = npages * PageSize
  result.bottom = cast[uint64](result.data) + result.size

template orRaise[T](opt: Option[T], exc: ref Exception): T =
  if opt.isSome:
    opt.get
  else:
    raise exc

proc createTask*(
  imagePhysAddr: PhysAddr,
  imagePageCount: uint64,
): Task =
  new(result)

  let taskId = nextId
  inc nextId

  var uspace = VMAddressSpace(
    minAddress: UserSpaceMinAddress,
    maxAddress: UserSpaceMaxAddress,
    pml4: cast[ptr PML4Table](new PML4Table)
  )

  # allocate user image vm region
  let imageVirtAddr = vmalloc(uspace, imagePageCount, paReadWrite, pmUser).orRaise(
    newException(Exception, "tasks: Failed to allocate VM region for user image")
  )

  # map user image
  mapRegion(
    pml4 = uspace.pml4,
    virtAddr = imageVirtAddr,
    physAddr = imagePhysAddr,
    pageCount = imagePageCount,
    pageAccess = paReadWrite,
    pageMode = pmUser,
  )

  # temporarily map the user image in kernel space
  mapRegion(
    pml4 = kspace.pml4,
    virtAddr = imageVirtAddr,
    physAddr = imagePhysAddr,
    pageCount = imagePageCount,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
  )
  # apply relocations to user image
  debugln "kernel: Applying relocations to user image"
  let entryPoint = applyRelocations(cast[ptr UncheckedArray[byte]](imageVirtAddr))

  # map kernel space
  var kpml4 = getActivePML4()
  for i in 256 ..< 512:
    uspace.pml4.entries[i] = kpml4.entries[i]

  # create user and kernel stacks
  let ustack = createStack(uspace, 1, pmUser)
  let kstack = createStack(kspace, 1, pmSupervisor)

  # create interrupt stack frame
  var index = kstack.size div 8
  kstack.data[index - 1] = cast[uint64](DataSegmentSelector) # SS
  kstack.data[index - 2] = cast[uint64](ustack.bottom) # RSP
  kstack.data[index - 3] = cast[uint64](0x202) # RFLAGS
  kstack.data[index - 4] = cast[uint64](UserCodeSegmentSelector) # CS
  kstack.data[index - 5] = cast[uint64](entryPoint) # RIP

  result.id = taskId
  result.space = uspace
  result.ustack = ustack
  result.kstack = kstack
  result.rsp = cast[uint64](kstack.data[index - 5].addr)
  result.state = TaskState.New
