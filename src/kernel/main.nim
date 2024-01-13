import std/[options, strformat]

import common/[bootinfo, libc, malloc, pagetables]
import debugcon
import idt
import gdt
import pmm
import syscalls
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

  # debugln &"kernel: User image physical address: {bootInfo.userImagePhysicalBase:#010x}"
  # debugln &"kernel: User image pages: {bootInfo.userImagePages}"

  # debugln ""
  # debugln &"Memory Map ({bootInfo.physicalMemoryMap.len} entries):"
  # debug &"""   {"Entry"}"""
  # debug &"""   {"Type":12}"""
  # debug &"""   {"Start":>12}"""
  # debug &"""   {"Start (KB)":>15}"""
  # debug &"""   {"#Pages":>10}"""
  # debugln ""

  # totalFreePages = 0
  # for i in 0 ..< bootInfo.physicalMemoryMap.len:
  #   let entry = bootInfo.physicalMemoryMap.entries[i]
  #   debug &"   {i:>5}"
  #   debug &"   {entry.type:12}"
  #   debug &"   {entry.start:>#12x}"
  #   debug &"   {entry.start div 1024:>#15}"
  #   debug &"   {entry.nframes:>#10}"
  #   debugln ""
  #   if entry.type == MemoryType.Free:
  #     totalFreePages += entry.nframes

  # debugln ""
  # debugln &"Total free: {totalFreePages * 4} KiB ({totalFreePages * 4 div 1024} MiB)"

  var kpml4 = getActivePML4()
  # dumpPageTable(kpml4)


  debugln "kernel: Initializing user page table"
  var upml4 = cast[ptr PML4Table](new PML4Table)
  # debugln &" (upml4: {cast[uint64](upml4):#x})"

  # copy kernel page table (upper half)
  debugln "kernel:   Copying kernel space user page table"
  for i in 256 ..< 512:
    upml4.entries[i] = kpml4.entries[i]

  # map user image
  debugln &"kernel:   Mapping user image ({UserImageVirtualBase} -> {bootInfo.userImagePhysicalBase:#x})"
  mapRegion(
    pml4 = upml4,
    virtAddr = UserImageVirtualBase.VirtAddr,
    physAddr = bootInfo.userImagePhysicalBase.PhysAddr,
    pageCount = bootInfo.userImagePages,
    pageAccess = paReadWrite,
    pageMode = pmUser,
  )

  # allocate and map user stack
  let userStackPhysAddr = pmAlloc(1).get
  debugln &"kernel:   Mapping user stack ({UserStackVirtualBase:#x} -> {userStackPhysAddr.uint64:#x})"
  mapRegion(
    pml4 = upml4,
    virtAddr = UserStackVirtualBase.VirtAddr,
    physAddr = userStackPhysAddr,
    pageCount = 1,
    pageAccess = paReadWrite,
    pageMode = pmUser,
  )

  # create a kernel switch stack and set tss.rsp0
  debugln "kernel: Creating kernel switch stack"
  let switchStackPhysAddr = pmAlloc(1).get
  let switchStackVirtAddr = p2v(switchStackPhysAddr)
  mapRegion(
    pml4 = kpml4,
    virtAddr = switchStackVirtAddr,
    physAddr = switchStackPhysAddr,
    pageCount = 1,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
  )
  tss.rsp0 = uint64(switchStackVirtAddr +! PageSize)

  # debugln "Dumping page table:"
  # debugln &" (pml4: {cast[uint64](pml4):#x})"
  # dumpPageTable(upml4)
  # debugln "Done"

  debugln "kernel: Creating interrupt stack frame"
  let userStackBottom = UserStackVirtualBase + PageSize
  let userStackPtr = cast[ptr array[512, uint64]](p2v(userStackPhysAddr))
  userStackPtr[^1] = cast[uint64](DataSegmentSelector) # SS
  userStackPtr[^2] = cast[uint64](userStackBottom) # RSP
  userStackPtr[^3] = cast[uint64](0x202) # RFLAGS
  userStackPtr[^4] = cast[uint64](UserCodeSegmentSelector) # CS
  userStackPtr[^5] = cast[uint64](UserImageVirtualBase) # RIP
  debugln &"            SS: {userStackPtr[^1]:#x}"
  debugln &"           RSP: {userStackPtr[^2]:#x}"
  debugln &"        RFLAGS: {userStackPtr[^3]:#x}"
  debugln &"            CS: {userStackPtr[^4]:#x}"
  debugln &"           RIP: {userStackPtr[^5]:#x}"

  let rsp = cast[uint64](userStackBottom - 5 * 8)

  debug "kernel: Initializing Syscalls "
  syscallInit(tss.rsp0)
  debugln "[success]"

  debugln "kernel: Switching to user mode"
  setActivePML4(upml4)
  asm """
    mov rsp, %0
    mov rbp, rsp
    iretq
    :
    : "r"(`rsp`)
  """

  quit()

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debug getStackTrace(e)
  quit()
