#[
  Fusion kernel
]#

import common/[bootinfo, libc, malloc, serde]
import
  channels, cpu, ctxswitch, devmgr, drivers/pci, idt, lapic,
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
  lapicInit()

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

  # test channels

  logger.info "creating a channel [for testing]"
  let ch = newChannel(msgSize = sizeof(int))

  proc sendAlloc(size: int): pointer =
    result = channels.alloc(ch.id, size)

  let packedObj = serialize("ping from kernel", sendAlloc)
  let size = sizeof(packedObj.len) + packedObj.len
  let msg = Message(len: size, data: cast[ptr UncheckedArray[byte]](packedObj))

  discard send(ch.id, msg)

  # end test channels

  logger.info "init scheduler"
  schedInit([utask1, utask2])

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
