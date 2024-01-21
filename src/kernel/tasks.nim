import std/options
import std/strformat

import common/pagetables
import debugcon
import loader
import gdt
import pmm
import vmm

type
  TaskStack* = object
    data*: ptr UncheckedArray[uint64]
    size*: uint64
    bottom*: uint64

  Task* = ref object
    id*: uint64
    space*: VMAddressSpace
    ustack*: TaskStack
    kstack*: TaskStack
    rsp*: uint64

var
  nextId: uint64 = 0
  currentTask* {.exportc.}: Task

proc createStack*(space: var VMAddressSpace, npages: uint64, mode: PageMode): TaskStack =
  let stackPtr = vmalloc(space, npages, paReadWrite, mode)
  if stackPtr.isNone:
    raise newException(Exception, "tasks: Failed to allocate stack")
  result.data = cast[ptr UncheckedArray[uint64]](stackPtr.get)
  result.size = npages * PageSize
  result.bottom = cast[uint64](result.data) + result.size

proc createTask*(
  imageVirtAddr: VirtAddr,
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

  # create interrupt stack frame on the kernel stack
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

proc switchTo*(task: var Task) {.noreturn.} =
  currentTask = task
  tss.rsp0 = task.kstack.bottom
  let rsp = task.rsp
  setActivePML4(task.space.pml4)
  asm """
    mov rsp, %0
    mov rbp, 0
    iretq
    :
    : "r"(`rsp`)
  """
