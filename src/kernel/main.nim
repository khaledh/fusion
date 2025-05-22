#[
  Fusion kernel
]#

import common/[bootinfo, libc, malloc, serde]
import
  channels, cpu, ctxswitch, devmgr, drivers/pci, idt, lapic,
  gdt, pmm, sched, syscalls, task, taskmgr, timer, vmmgr, con/console

const KernelVersion = "0.2.0"

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

  logger.info "init gdt"
  gdtInit()

  logger.info "init idt"
  idtInit()

  logger.info "init pmm"
  pmInit(
    bootInfo.physicalMemoryMap,
    bootInfo.physicalMemoryVirtualBase,
    bootInfo.physicalMemoryPages,
  )

  # copy some bootinfo fields before we switch to the new page table
  let userImagePhysicalBase = bootInfo.userImagePhysicalBase.PAddr
  let userImagePages = bootInfo.userImagePages

  logger.info "init vmm"
  vmmgrInit(
    bootInfo.kernelImageVirtualBase.VAddr,
    bootInfo.kernelImagePhysicalBase.PAddr,
    bootInfo.kernelImagePages,
    bootInfo.kernelStackVirtualBase.VAddr,
    bootInfo.kernelStackPhysicalBase.PAddr,
    bootInfo.kernelStackPages,
    bootInfo.physicalMemoryVirtualBase.VAddr,
    bootInfo.physicalMemoryPages,
  )

  logger.info "init lapic"
  lapicInit()

  pci.showPciConfig()
  devmgrInit()

  logger.info "init console"
  console.init()
  console.write("Fusion OS")

  logger.info "init timer"
  timerInit()

  logger.info "init syscalls"
  syscallInit()

  logger.info "init task manager"
  taskmgrInit()

  var idleTask = createKernelTask(cpu.idle, "idle", TaskPriority.low)

  logger.info "init scheduler"
  schedInit([])

  ############### testing #######################################################
  logger.info ""
  logger.info &"{dim()}========== for testing =========={undim()}"

  # test channel
  logger.info "creating a channel"
  let ch = channels.create(msgSize = sizeof(int))
  
  proc sendAlloc(size: int): pointer =
    result = channels.alloc(ch.id, size)
  
  let packedObj = serialize(">> \e[91mping from kernel\e[0m", sendAlloc)
  let size = sizeof(packedObj.len) + packedObj.len
  let msg = Message(len: size, data: cast[ptr UncheckedArray[byte]](packedObj))
  
  discard channels.send(ch.id, msg)

  #test user tasks
  logger.info &"creating two user tasks"

  var utask1 = createUserTask(
    imagePhysAddr = userImagePhysicalBase,
    imagePageCount = userImagePages,
    name = "utask1",
  )
  logger.info ""

  var utask2 = createUserTask(
    imagePhysAddr = userImagePhysicalBase,
    imagePageCount = userImagePages,
    name = "utask2",
  )

  sched.addTask(utask1)
  sched.addTask(utask2)

  logger.info &"{dim()}================================={undim()}"
  logger.info ""
  ############### /testing ######################################################

  logger.info "kernel ready"
  logger.raw "\n"
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
