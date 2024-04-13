import std/strformat

import common/[bootinfo, libc, malloc]
import cpu
import debugcon
import elf
import idt
import gdt
import pmm
import sched
import syscalls
import tasks
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

  debug "kernel: Initializing PMM "
  pmInit(bootInfo.physicalMemoryVirtualBase, bootInfo.physicalMemoryMap)
  debugln "[success]"

  debug "kernel: Initializing VMM "
  vmInit(bootInfo.physicalMemoryVirtualBase, pmm.pmAlloc)
  vmAddRegion(kspace, bootInfo.kernelImageVirtualBase.VirtAddr, bootInfo.kernelImagePages)
  vmAddRegion(kspace, bootInfo.kernelStackVirtualBase.VirtAddr, bootInfo.kernelStackPages)
  debugln "[success]"

  debug "kernel: Initializing GDT "
  gdtInit()
  debugln "[success]"

  debug "kernel: Initializing IDT "
  idtInit()
  debugln "[success]"

  debug "kernel: Initializing Syscalls "
  syscallInit()
  debugln "[success]"

  debugln "kernel: Creating user tasks"
  var task1 = createTask(
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
  )
  debugln &"kernel: Task loadeed at {task1.vaddr.uint64:#x}"

  elf.load(cast[ptr UncheckedArray[byte]](task1.vaddr))
  halt()
  # var task2 = createTask(
  #   imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
  #   imagePageCount = bootInfo.userImagePages,
  # )
  # var task3 = createTask(
  #   imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
  #   imagePageCount = bootInfo.userImagePages,
  # )

  debugln "kernel: Adding tasks to scheduler"
  sched.addTask(task1)
  # sched.addTask(task2)
  # sched.addTask(task3)

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
