#[
  Fusion kernel
]#

import common/bootinfo
import
  acpi, cpu, ctxswitch, devmgr, drivers/pci, ioapic, idt, lapic, gdt,
  pmm, sched, syscalls, task, taskmgr, timer, vmmgr, con/console

const KernelVersion = "0.3.0"

let
  logger = DebugLogger(name: "main")

proc kmain*(bootInfo: ptr BootInfo) =
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
  let acpiMemoryPhysicalBase = bootInfo.acpiMemoryPhysicalBase
  let acpiMemoryPages = bootInfo.acpiMemoryPages
  let acpiRsdpPhysicalAddr = bootInfo.acpiRsdpPhysicalAddr
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

  logger.info "init acpi"
  acpiInit(
    acpiMemoryPhysicalBase.PAddr,
    acpiMemoryPages,
    acpiRsdpPhysicalAddr.PAddr,
  )

  logger.info "init lapic"
  lapicInit()

  logger.info "init ioapic"
  ioapicInit(acpi.getMadt())

  logger.info "init pci"
  pci.showPciConfig()
  devmgrInit()

  logger.info "init timer"
  timerInit()

  logger.info "init syscalls"
  syscallInit()

  logger.info "init task manager"
  taskmgrInit()

  logger.info "init idle task"
  var idleTask = createKernelTask(cpu.idle, "idle", TaskPriority.low)

  logger.info "init console"
  let consoleTask = createKernelTask(console.start, "console")

  logger.info "init scheduler"
  schedInit([consoleTask])

  ############### testing #######################################################
  logger.info ""
  logger.info &"{dim()}========== for testing =========={undim()}"
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
