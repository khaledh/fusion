#[
  BootInfo is a struct that is passed to the kernel by the bootloader.
  It contains information about the system's memory layout.
]#

type
  MemoryType* = enum
    Free
    KernelCode
    KernelData
    KernelStack
    UserCode
    UserData
    UserStack
    Reserved

  MemoryMapEntry* = object
    `type`*: MemoryType
    start*: uint64
    nframes*: uint64

  MemoryMap* = object
    len*: uint
    entries*: ptr UncheckedArray[MemoryMapEntry]

  BootInfo* = object
    physicalMemoryMap*: MemoryMap
    virtualMemoryMap*: MemoryMap
    physicalMemoryVirtualBase*: uint64
    physicalMemoryPages*: uint64
    kernelImageVirtualBase*: uint64
    kernelImagePhysicalBase*: uint64
    kernelImagePages*: uint64
    kernelStackVirtualBase*: uint64
    kernelStackPhysicalBase*: uint64
    kernelStackPages*: uint64
    userImagePhysicalBase*: uint64
    userImagePages*: uint64
