#[
  Fusion kernel
]#

import common/[bootinfo, libc, malloc, pagetables]
import idt
import lapic
import gdt
import pmm
import sched
import syscalls
import taskmgr
import timer
import vmm

proc NimMain() {.importc.}
proc KernelMainInner(bootInfo: ptr BootInfo)
proc unhandledException*(e: ref Exception)

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

  debugln "kernel: Initializing PMM"
  pmInit(bootInfo.physicalMemoryVirtualBase, bootInfo.physicalMemoryMap)

  debugln "kernel: Initializing VMM"
  vmInit(bootInfo.physicalMemoryVirtualBase, pmm.pmAlloc)
  vmAddRegion(kspace, bootInfo.kernelImageVirtualBase.VirtAddr, bootInfo.kernelImagePages)
  vmAddRegion(kspace, bootInfo.kernelStackVirtualBase.VirtAddr, bootInfo.kernelStackPages)

  debugln "kernel: Initializing GDT"
  gdtInit()

  debugln "kernel: Initializing IDT"
  idtInit()

  debugln "kernel: Initializing LAPIC "
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
  
  debugln "kernel: Initializing timer"
  timerInit()

  debugln "kernel: Initializing Syscalls"
  syscallInit()

  debugln "kernel: Creating tasks"

  # let kidle = createKernelTask(cpu.idle)

  # proc khello() {.cdecl.} =
  #   debugln "Hello from kernel!"
  #   schedule()  # yield
  #   debugln "Bye from kernel!"
  
  # let ktask = createKernelTask(khello)

  var utask1 = createTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
  )
  var utask2 = createTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
  )

  debugln "kernel: Adding tasks to scheduler"
  # sched.addTask(kidle)
  # sched.addTask(ktask)
  sched.addTask(utask1)
  sched.addTask(utask2)


  debugln "kernel: Starting scheduler"
  sched.schedule()

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debug getStackTrace(e)
  quit()
