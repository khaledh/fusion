import std/strformat

import common/[libc, malloc, uefi]
import debugcon

proc NimMain() {.importc.}
proc KernelMainInner(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
)
proc unhandledException*(e: ref Exception)

proc KernelMain(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
) {.exportc.} =
  NimMain()

  try:
    KernelMainInner(memoryMap, memoryMapSize, memoryMapDescriptorSize)
  except Exception as e:
    unhandledException(e)

  quit()

proc KernelMainInner(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
) =
  debugln ""
  debugln "kernel: Hello, world!"
  quit()

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

  quit()

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: {e.msg} [{e.name}]"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debugln getStackTrace(e)
  quit()
