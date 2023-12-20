import std/strformat

import common/[libc, malloc, uefi]
import debugcon
import paging

proc NimMain() {.importc.}
proc KernelMainInner(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
)
proc unhandledException*(e: ref Exception)

proc KernelEntry(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
) {.exportc.} =
  NimMain()

  try:
    KernelEntryInner(memoryMap, memoryMapSize, memoryMapDescriptorSize)
  except Exception as e:
    unhandledException(e)

  quit()

proc KernelMainInner(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
) =
  let numMemoryMapEntries = memoryMapSize div memoryMapDescriptorSize

  debugln ""
  debugln &"Memory Map ({numMemoryMapEntries} entries):"
  debug &"""   {"Entry"}"""
  debug &"""   {"Type":22}"""
  debug &"""   {"PhysicalStart":>15}"""
  debug &"""   {"PhysicalStart (KB)":>15}"""
  debug &"""   {"NumberOfPages":>13}"""
  debugln ""
  for i in 0 ..< numMemoryMapEntries:
    let entry = cast[ptr EfiMemoryDescriptor](cast[uint64](memoryMap) + i * memoryMapDescriptorSize)
    debug &"   {i:>5}"
    debug &"   {entry.type:22}"
    debug &"   {entry.physicalStart:>#15x}"
    debug &"   {entry.physicalStart div 1024:>#18}"
    debug &"   {entry.numberOfPages:>#13}"
    debugln ""

  var pml4 = new(PML4Table)
  # identity map the first 4MB of memory
  mapPages(pml4, 0x0'u64, 0x0'u64, 1024'u64, paReadWrite, pmSupervisor)
  # map the kernel to the upper half
  mapPage(pml4, 0xFFFF800000000000'u64, 0x100000'u64, paReadWrite, pmSupervisor)
  # install the page table
  installPageTable(pml4)

  # jump to the kernel upper half
  KernelMainUpperHalf(memoryMap, memoryMapSize, memoryMapDescriptorSize)


proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: {e.msg} [{e.name}]"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debugln getStackTrace(e)
  quit()
