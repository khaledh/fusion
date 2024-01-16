import std/options
import std/strformat

import common/pagetables
import debugcon
import gdt
import pmm
import vmm

type
  TaskStack* = object
    data*: ptr UncheckedArray[uint64]
    size*: uint64

  Task* = ref object
    id*: uint64
    space*: VMAddressSpace
    ustack*: TaskStack
    kstack*: TaskStack
    rsp*: uint64

var
  nextId*: uint64 = 0


proc bottom*(s: TaskStack): uint64 =
  result = cast[uint64](s.data) + s.size


proc createTask*(
  imageVirtAddr: VirtAddr,
  imagePhysAddr: PhysAddr,
  imagePageCount: uint64,
  entryPoint: VirtAddr
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

  # map kernel space
  var kpml4 = getActivePML4()
  for i in 256 ..< 512:
    uspace.pml4.entries[i] = kpml4.entries[i]

  # create user stack
  let ustackRegion = vmalloc(uspace, 1, paReadWrite, pmUser)
  if ustackRegion.isNone:
    raise newException(Exception, "tasks: Failed to allocate user stack")
  let ustack = TaskStack(
    data: cast[ptr UncheckedArray[uint64]](ustackRegion.get),
    size: 1 * PageSize
  )

  # create kernel stack
  let kstackRegion = vmalloc(kspace, 1, paReadWrite, pmSupervisor)
  if kstackRegion.isNone:
    raise newException(Exception, "tasks: Failed to allocate kernel stack")
  let kstack = TaskStack(
    data: cast[ptr UncheckedArray[uint64]](kstackRegion.get),
    size: 1 * PageSize
  )

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
