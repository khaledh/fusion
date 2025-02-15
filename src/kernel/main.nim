#[
  Fusion kernel
]#

import common/[bootinfo, libc, malloc, pagetables]
import
  channels, cpu, ctxswitch, devmgr, drivers/pci, idt, lapic, gfxsrv,
  gdt, pmm, sched, syscalls, taskdef, taskmgr, timer, vmm

const KernelVersion = "0.1.0"

let logger = DebugLogger(name: "main")

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
  logger.raw "\n"
  logger.raw &"Fusion Kernel (v{KernelVersion})\n"
  logger.raw "\n"

  logger.info "init pmm"
  pmInit(bootInfo.physicalMemoryVirtualBase, bootInfo.physicalMemoryMap)

  logger.info "init vmm"
  vmInit(bootInfo.physicalMemoryVirtualBase, pmm.pmAlloc)
  vmAddRegion(kspace, bootInfo.kernelImageVirtualBase.VirtAddr, bootInfo.kernelImagePages)
  vmAddRegion(kspace, bootInfo.kernelStackVirtualBase.VirtAddr, bootInfo.kernelStackPages)

  logger.info "init gdt"
  gdtInit()

  logger.info "init idt"
  idtInit()

  logger.info "init lapic"
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

  pci.showPciConfig()
  devmgrInit()

  logger.info "init timer"
  timerInit()

  logger.info "init syscalls"
  syscallInit()

  logger.info "init task manager"
  taskmgrInit()

  logger.info "creating tasks"

  var idleTask = createKernelTask(cpu.idle, "idle", TaskPriority.low)
  let gfxTask = createKernelTask(gfxsrv.start, "gfxsrv")

  # create user tasks [for testing]
  var utask1 = createUserTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
    name = "utask1",
  )
  var utask2 = createUserTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
    name = "utask2",
  )

  logger.info "creating a channel [for testing]"
  let ch = newChannel(msgSize = sizeof(int))
  var data = new(int)
  data[] = 1010
  let msg = Message(len: sizeof(int), data: cast[ptr UncheckedArray[byte]](data))
  discard send(ch.id, msg)


  logger.info "init scheduler"
  schedInit([gfxTask, utask1, utask2])

  logger.info "switching to the idle task"
  switchTo(idleTask)

####################################################################################################
# Report unhandled Nim exceptions
####################################################################################################

proc unhandledException*(e: ref Exception) =
  logger.info ""
  logger.info &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    logger.info ""
    logger.info "Stack trace:"
    debug getStackTrace(e)
  quit()
