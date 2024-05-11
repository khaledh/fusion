#[
  Fusion kernel
]#

import common/[bootinfo, libc, malloc, pagetables]
import cpu
import idt
import lapic
import gdt
import pmm
import sched
import syscalls
import taskdef
import taskmgr
import timer
import vmm

proc NimMain() {.importc.}
proc KernelMainInner(bootInfo: ptr BootInfo)
proc unhandledException*(e: ref Exception)

####################################################################################################
# Kernel entry point
####################################################################################################

proc KernelMain(bootInfo: ptr BootInfo) {.exportc.} =
  NimMain()

  try:
    KernelMainInner(bootInfo)
  except Exception as e:
    unhandledException(e)

  quit()

proc KernelMainInner(bootInfo: ptr BootInfo) =
  debugln ""
  debugln "kernel: Fusion Kernel"

  debugln "kernel: Init PMM"
  pmInit(bootInfo.physicalMemoryVirtualBase, bootInfo.physicalMemoryMap)

  debugln "kernel: Init VMM"
  vmInit(bootInfo.physicalMemoryVirtualBase, pmm.pmAlloc)
  vmAddRegion(kspace, bootInfo.kernelImageVirtualBase.VirtAddr, bootInfo.kernelImagePages)
  vmAddRegion(kspace, bootInfo.kernelStackVirtualBase.VirtAddr, bootInfo.kernelStackPages)

  debugln "kernel: Init GDT"
  gdtInit()

  debugln "kernel: Init IDT"
  idtInit()

  debugln "kernel: Init LAPIC "
  let lapicPhysAddr = lapic.getBasePhysAddr()
  let lapicFrameAddr = lapicPhysAddr - (lapicPhysAddr mod PageSize)
  # map LAPIC frame into virtual memory
  let lapicVMRegion = vmalloc(kspace, 1)
  mapRegion(
    pml4 = getActivePML4(),
    virtAddr = lapicVMRegion.start,
    physAddr = lapicFrameAddr.PhysAddr,
    pageCount = 1,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
    noExec = true
  )
  lapicInit(lapicVMRegion.start.uint64)
  
  debugln "kernel: Init timer"
  timerInit()

  debugln "kernel: Init syscalls"
  syscallInit()

  debugln "kernel: Creating tasks"

  let idleTask = createKernelTask(cpu.idle, low(TaskPriority))

  var utask1 = createUserTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
  )
  var utask2 = createUserTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
  )

  debugln "kernel: Adding tasks to scheduler"
  sched.addTask(idleTask)
  sched.addTask(utask1)
  sched.addTask(utask2)

  debugln "kernel: Starting scheduler"
  sched.schedule()

####################################################################################################
# Report unhandled Nim exceptions
####################################################################################################

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debug getStackTrace(e)
  quit()
