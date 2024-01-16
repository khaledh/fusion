import std/strformat

import common/[bootinfo, libc, malloc, pagetables]
import debugcon
import idt
import gdt
import pmm
import syscalls
import tasks
import vmm

const
  UserImageVirtualBase = 0x0000000040000000
  UserStackVirtualBase = 0x0000000050000000

proc NimMain() {.importc.}
proc KernelMainInner(bootInfo: ptr BootInfo)
proc unhandledException*(e: ref Exception)

proc printFreeRegions() =
  debug &"""   {"Start":>16}"""
  debug &"""   {"Start (KB)":>12}"""
  debug &"""   {"Size (KB)":>11}"""
  debug &"""   {"#Pages":>9}"""
  debugln ""
  var totalFreePages: uint64 = 0
  for (start, nframes) in pmFreeRegions():
    debug &"   {cast[uint64](start):>#16x}"
    debug &"   {cast[uint64](start) div 1024:>#12}"
    debug &"   {nframes * 4:>#11}"
    debug &"   {nframes:>#9}"
    debugln ""
    totalFreePages += nframes
  debugln &"kernel: Total free: {totalFreePages * 4} KiB ({totalFreePages * 4 div 1024} MiB)"

proc printVMRegions(memoryMap: MemoryMap) =
  debug &"""   {"Start":>20}"""
  debug &"""   {"Type":12}"""
  debug &"""   {"VM Size (KB)":>12}"""
  debug &"""   {"#Pages":>9}"""
  debugln ""
  for i in 0 ..< memoryMap.len:
    let entry = memoryMap.entries[i]
    debug &"   {entry.start:>#20x}"
    debug &"   {entry.type:#12}"
    debug &"   {entry.nframes * 4:>#12}"
    debug &"   {entry.nframes:>#9}"
    debugln ""

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

  debug "kernel: Initializing physical memory manager "
  pmInit(bootInfo.physicalMemoryVirtualBase, bootInfo.physicalMemoryMap)
  debugln "[success]"

  debug "kernel: Initializing virtual memory manager "
  vmInit(bootInfo.physicalMemoryVirtualBase, pmm.pmAlloc)
  vmAddRegion(kspace, bootInfo.kernelImageVirtualBase.VirtAddr, bootInfo.kernelImagePages)
  vmAddRegion(kspace, bootInfo.kernelStackVirtualBase.VirtAddr, bootInfo.kernelStackPages)
  debugln "[success]"


  debugln "kernel: Physical memory free regions "
  printFreeRegions()

  debugln "kernel: Virtual memory regions "
  printVMRegions(bootInfo.virtualMemoryMap)

  debug "kernel: Initializing GDT "
  gdtInit()
  debugln "[success]"

  debug "kernel: Initializing IDT "
  idtInit()
  debugln "[success]"

  debugln "kernel: Creating user task"
  var task = createTask(
    imageVirtAddr = UserImageVirtualBase.VirtAddr,
    imagePhysAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    imagePageCount = bootInfo.userImagePages,
    entryPoint = UserImageVirtualBase.VirtAddr
  )

  debug "kernel: Initializing Syscalls "
  syscallInit(task.kstack.bottom)
  debugln "[success]"

  debugln "kernel: Switching to user mode"
  switchTo(task)

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debug getStackTrace(e)
  quit()
