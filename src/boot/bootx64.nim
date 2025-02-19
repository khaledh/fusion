#[
  Fusion kernel UEFI bootloader
]#

import std/sets

import common/[bootinfo, malloc, pagetables]
import libc, uefi
import kernel/debugcon
import kernel/vmm

const
  KernelPhysicalBase = 0x10_0000'u64
  KernelVirtualBase = 0xFFFF_8000_0000_0000'u64 + KernelPhysicalBase

  KernelStackVirtualBase = 0xFFFF_8001_0000_0000'u64 # KernelVirtualBase + 4 GiB
  KernelStackSize = 16 * 1024'u64
  KernelStackPages = KernelStackSize div PageSize

  BootInfoVirtualBase = KernelStackVirtualBase + KernelStackSize # after kernel stack

  PhysicalMemoryVirtualBase = 0xFFFF_8002_0000_0000'u64 # KernelVirtualBase + 8 GiB

####################################################################################################
# Forward declarations
####################################################################################################

proc NimMain() {.importc.}
proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus
proc checkStatus(status: EfiStatus)
proc unhandledException(e: ref Exception)

proc loadImage(
  imagePath: WideCString,
  rootDir: ptr EfiFileProtocol,
  memoryType: EfiMemoryType,
  loadAddress: Option[EfiPhysicalAddress] = none(EfiPhysicalAddress),
): tuple[base: EfiPhysicalAddress, pages: uint64]

proc convertUefiMemoryMap(
  uefiMemoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  uefiMemoryMapSize: uint,
  uefiMemoryMapDescriptorSize: uint,
): seq[MemoryMapEntry]

proc createVirtualMemoryMap(
  kernelImagePages: uint64,
  physMemoryPages: uint64,
): seq[MemoryMapEntry]

proc initBootInfo(
  bootInfoBase: uint64,
  physMemoryPages: uint64,
  physMemoryMap: seq[MemoryMapEntry],
  virtMemoryMap: seq[MemoryMapEntry],
  kernelImagePages: uint64,
  kernelStackBase: uint64,
  kernelStackPages: uint64,
  userImageBase: uint64,
  userImagePages: uint64,
)

proc createPageTable(
  bootloaderBase: uint64,
  bootloaderPages: uint64,
  kernelImageBase: uint64,
  kernelImagePages: uint64,
  kernelStackBase: uint64,
  kernelStackPages: uint64,
  bootInfoBase: uint64,
  bootInfoPages: uint64,
  physMemoryPages: uint64,
): ptr PML4Table


####################################################################################################
# Bootloader entry point
####################################################################################################

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  NimMain()
  uefi.sysTable = sysTable
  consoleClear()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)

proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus =
  consoleOutColor "Fusion OS Bootloader", fgYellow
  echo ""
  echo ""

  var status: EfiStatus

  # get the LoadedImage protocol from the image handle
  var loadedImage: ptr EfiLoadedImageProtocol

  consoleOut "boot: Acquiring LoadedImage protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    imgHandle, EfiLoadedImageProtocolGuid, cast[ptr pointer](addr loadedImage)
  )

  # get the FileSystem protocol from the device handle
  var fileSystem: ptr EfiSimpleFileSystemProtocol

  consoleOut "boot: Acquiring SimpleFileSystem protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    loadedImage.deviceHandle, EfiSimpleFileSystemProtocolGuid, cast[ptr pointer](addr fileSystem)
  )

  # open the root directory
  var rootDir: ptr EfiFileProtocol

  consoleOut "boot: Opening root directory"
  checkStatus fileSystem.openVolume(fileSystem, addr rootDir)

  # load kernel image
  let (kernelImageBase, kernelImagePages) = loadImage(
    imagePath = W"efi\fusion\kernel.bin",
    rootDir = rootDir,
    memoryType = OsvKernelCode,
    loadAddress = KernelPhysicalBase.EfiPhysicalAddress.some
  )

  # load user task image
  let (userImageBase, userImagePages) = loadImage(
    imagePath = W"efi\fusion\utask.bin",
    rootDir = rootDir,
    memoryType = OsvUserCode,
  )

  # close the root directory
  consoleOut "boot: Closing root directory"
  checkStatus rootDir.close(rootDir)

  consoleOut &"boot: Allocating memory for kernel stack (16 KiB)"
  var kernelStackBase: uint64
  let kernelStackPages = KernelStackSize div PageSize
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAnyPages,
    OsvKernelStack,
    kernelStackPages,
    kernelStackBase.addr,
  )

  consoleOut &"boot: Allocating memory for BootInfo"
  var bootInfoBase: uint64
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAnyPages,
    OsvKernelData,
    1,
    bootInfoBase.addr,
  )

  # memory map
  var memoryMapSize = 0.uint
  var memoryMap: ptr UncheckedArray[EfiMemoryDescriptor]
  var memoryMapKey: uint
  var memoryMapDescriptorSize: uint
  var memoryMapDescriptorVersion: uint32

  # get memory map size
  status = uefi.sysTable.bootServices.getMemoryMap(
    addr memoryMapSize,
    cast[ptr EfiMemoryDescriptor](nil),
    cast[ptr uint](nil),
    cast[ptr uint](addr memoryMapDescriptorSize),
    cast[ptr uint32](nil)
  )
  # increase memory map size to account the next call to allocatePool
  inc memoryMapSize, memoryMapDescriptorSize * 2

  # allocate pool for memory map
  # this changes the memory map size, hence the previous step
  consoleOut "boot: Allocating pool for memory map"
  checkStatus uefi.sysTable.bootServices.allocatePool(
    EfiLoaderData, memoryMapSize, cast[ptr pointer](addr memoryMap)
  )

  # get memory map
  echo "boot: Getting memory map and exiting boot services"
  status = uefi.sysTable.bootServices.getMemoryMap(
    addr memoryMapSize,
    cast[ptr EfiMemoryDescriptor](memoryMap),
    addr memoryMapKey,
    addr memoryMapDescriptorSize,
    addr memoryMapDescriptorVersion
  )

  # IMPORTANT: After this point we cannot output anything to the console, since calling
  # a boot service may change the memory map and invalidate our map key. We can only
  # output to the console in case of an error (since we quit anyway).
  if status != EfiSuccess:
    consoleOutError &" [failed, status = {status:#x}]"
    quit()

  status = uefi.sysTable.bootServices.exitBootServices(imgHandle, memoryMapKey)
  if status != EfiSuccess:
    echo &"boot: Failed to exit boot services: {status:#x}"
    quit()

  # let numEntries = memoryMapSize div memoryMapDescriptorSize
  # debugln &"UEFI Memory Map ({numEntries} entries):"
  # debug &"""   {"Entry"}"""
  # debug &"""   {"Type":22}"""
  # debug &"""   {"Start":>12}"""
  # debug &"""   {"Start (KB)":>15}"""
  # debug &"""   {"#Pages":>10}"""
  # debugln ""

  # for i in 0 ..< numEntries:
  #   let entry = cast[ptr EfiMemoryDescriptor](cast[uint64](memoryMap) + i * memoryMapDescriptorSize)
  #   debug &"   {i:>5}"
  #   debug &"   {entry.type:22}"
  #   debug &"   {entry.physicalStart:>#12x}"
  #   debug &"   {entry.physicalStart div 1024:>#15}"
  #   debug &"   {entry.numberOfPages:>#10}"
  #   debugln ""

  # ======= NO MORE UEFI BOOT SERVICES =======

  # debugln ""

  let physMemoryMap = convertUefiMemoryMap(memoryMap, memoryMapSize, memoryMapDescriptorSize)

  # get max free physical memory address
  var maxPhysAddr: PhysAddr
  for i in 0 ..< physMemoryMap.len:
    if physMemoryMap[i].type == Free:
      maxPhysAddr = physMemoryMap[i].start.PhysAddr +! physMemoryMap[i].nframes * PageSize

  let physMemoryPages: uint64 = maxPhysAddr.uint64 div PageSize

  let virtMemoryMap = createVirtualMemoryMap(kernelImagePages, physMemoryPages)

  debugln &"boot: Preparing BootInfo"
  initBootInfo(
    bootInfoBase,
    physMemoryPages,
    physMemoryMap,
    virtMemoryMap,
    kernelImagePages,
    kernelStackBase,
    kernelStackPages,
    userImageBase,
    userImagePages,
  )

  let bootloaderPages = (loadedImage.imageSize.uint + 0xFFF) div 0x1000.uint

  let pml4 = createPageTable(
    cast[uint64](loadedImage.imageBase),
    bootloaderPages,
    cast[uint64](kernelImageBase),
    kernelImagePages,
    kernelStackBase,
    kernelStackPages,
    bootInfoBase,
    1, # bootInfoPages
    physMemoryPages,
  )

  # jump to kernel
  let kernelStackTop = KernelStackVirtualBase + KernelStackSize
  let cr3 = cast[uint64](pml4)
  debugln &"boot: Jumping to kernel at {cast[uint64](KernelVirtualBase):#010x}"
  asm """
    mov rdi, %0  # bootInfo
    mov cr3, %2  # PML4
    mov rsp, %1  # kernel stack top
    jmp %3       # kernel entry point
    :
    : "r"(`bootInfoBase`),
      "r"(`kernelStackTop`),
      "r"(`cr3`),
      "r"(`KernelVirtualBase`)
  """

  # we should never get here
  return EfiLoadError

####################################################################################################
# Load image from filesystem
####################################################################################################

proc loadImage(
  imagePath: WideCString,
  rootDir: ptr EfiFileProtocol,
  memoryType: EfiMemoryType,
  loadAddress: Option[EfiPhysicalAddress] = none(EfiPhysicalAddress),
): tuple[base: EfiPhysicalAddress, pages: uint64] =
  # open the image file
  var file: ptr EfiFileProtocol

  consoleOut "boot: Opening image: "
  consoleOut imagePath
  checkStatus rootDir.open(rootDir, addr file, imagePath, 1, 1)

  # get file size
  var fileInfo: EfiFileInfo
  var fileInfoSize = sizeof(EfiFileInfo).uint

  consoleOut "boot: Getting file info"
  checkStatus file.getInfo(
    file, addr EfiFileInfoGuid, addr fileInfoSize, addr fileInfo
  )
  echo &"boot: Image file size: {fileInfo.fileSize} bytes"

  var imageBase: EfiPhysicalAddress
  let imagePages = (fileInfo.fileSize + 0xFFF).uint div PageSize.uint # round up to nearest page

  consoleOut &"boot: Allocating memory for image"
  if loadAddress.isSome:
    imageBase = cast[EfiPhysicalAddress](loadAddress.get)
    checkStatus uefi.sysTable.bootServices.allocatePages(
      AllocateAddress,
      memoryType,
      imagePages,
      cast[ptr EfiPhysicalAddress](imageBase.addr)
    )
  else:
    checkStatus uefi.sysTable.bootServices.allocatePages(
      AllocateAnyPages,
      memoryType,
      imagePages,
      cast[ptr EfiPhysicalAddress](imageBase.addr)
    )

  # read the image into memory
  consoleOut "boot: Reading image into memory"
  checkStatus file.read(file, cast[ptr uint](addr fileInfo.fileSize), cast[pointer](imageBase))

  # close the image file
  consoleOut "boot: Closing image file"
  checkStatus file.close(file)

  result = (imageBase, imagePages.uint64)


####################################################################################################
# Memory map utilities
####################################################################################################

# We use a HashSet here because the `EfiMemoryType` has values greater than 64K,
# which is the maximum value supported by Nim sets.
const
  FreeMemoryTypes = [
    EfiConventionalMemory,
    EfiBootServicesCode,
    EfiBootServicesData,
    EfiLoaderCode,
    EfiLoaderData,
  ].toHashSet

proc convertUefiMemoryMap(
  uefiMemoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  uefiMemoryMapSize: uint,
  uefiMemoryMapDescriptorSize: uint,
): seq[MemoryMapEntry] =
  let uefiNumMemoryMapEntries = uefiMemoryMapSize div uefiMemoryMapDescriptorSize

  for i in 0 ..< uefiNumMemoryMapEntries:
    let uefiEntry = cast[ptr EfiMemoryDescriptor](
      cast[uint64](uefiMemoryMap) + i * uefiMemoryMapDescriptorSize
    )
    let memoryType =
      if uefiEntry.type in FreeMemoryTypes:
        Free
      elif uefiEntry.type == OsvKernelCode:
        KernelCode
      elif uefiEntry.type == OsvKernelData:
        KernelData
      elif uefiEntry.type == OsvKernelStack:
        KernelStack
      elif uefiEntry.type == OsvUserCode:
        UserCode
      else:
        Reserved
    result.add(MemoryMapEntry(
      type: memoryType,
      start: uefiEntry.physicalStart,
      nframes: uefiEntry.numberOfPages
    ))

proc createVirtualMemoryMap(
  kernelImagePages: uint64,
  physMemoryPages: uint64,
): seq[MemoryMapEntry] =

  result.add(MemoryMapEntry(
    type: KernelCode,
    start: KernelVirtualBase,
    nframes: kernelImagePages
  ))
  result.add(MemoryMapEntry(
    type: KernelStack,
    start: KernelStackVirtualBase,
    nframes: KernelStackPages
  ))
  result.add(MemoryMapEntry(
    type: KernelData,
    start: BootInfoVirtualBase,
    nframes: 1
  ))
  result.add(MemoryMapEntry(
    type: KernelData,
    start: PhysicalMemoryVirtualBase,
    nframes: physMemoryPages
  ))

####################################################################################################
# BootInfo utilities
####################################################################################################

proc initBootInfo(
  bootInfoBase: uint64,
  physMemoryPages: uint64,
  physMemoryMap: seq[MemoryMapEntry],
  virtMemoryMap: seq[MemoryMapEntry],
  kernelImagePages: uint64,
  kernelStackBase: uint64,
  kernelStackPages: uint64,
  userImageBase: uint64,
  userImagePages: uint64,
) =
  var bootInfo = cast[ptr BootInfo](bootInfoBase)
  bootInfo.physicalMemoryVirtualBase = PhysicalMemoryVirtualBase

  # copy physical memory map entries to boot info
  bootInfo.physicalMemoryMap.len = physMemoryMap.len.uint
  bootInfo.physicalMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoBase + sizeof(BootInfo).uint64)
  for i in 0 ..< physMemoryMap.len:
    bootInfo.physicalMemoryMap.entries[i] = physMemoryMap[i]
  let physMemoryMapSize = physMemoryMap.len.uint64 * sizeof(MemoryMapEntry).uint64

  # copy virtual memory map entries to boot info
  bootInfo.virtualMemoryMap.len = virtMemoryMap.len.uint
  bootInfo.virtualMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoBase + sizeof(BootInfo).uint64 + physMemoryMapSize)
  for i in 0 ..< virtMemoryMap.len:
    bootInfo.virtualMemoryMap.entries[i] = virtMemoryMap[i]

  bootInfo.kernelImageVirtualBase = KernelVirtualBase
  bootInfo.kernelImagePhysicalBase = KernelPhysicalBase
  bootInfo.kernelImagePages = kernelImagePages

  bootInfo.kernelStackVirtualBase = KernelStackVirtualBase
  bootInfo.kernelStackPhysicalBase = kernelStackBase
  bootInfo.kernelStackPages = kernelStackPages

  bootInfo.userImagePhysicalBase = userImageBase
  bootInfo.userImagePages = userImagePages

####################################################################################################
# Page table mapping
####################################################################################################

type
  AlignedPage = object
    data {.align(PageSize).}: array[PageSize, uint8]

proc createPageTable(
  bootloaderBase: uint64,
  bootloaderPages: uint64,
  kernelImageBase: uint64,
  kernelImagePages: uint64,
  kernelStackBase: uint64,
  kernelStackPages: uint64,
  bootInfoBase: uint64,
  bootInfoPages: uint64,
  physMemoryPages: uint64,
): ptr PML4Table =

  proc bootAlloc(nframes: uint64): PhysAddr =
    result = cast[PhysAddr](new AlignedPage)

  # initialize vmm using identity-mapped physical memory
  vmInit(physMemoryVirtualBase = 0'u64, physAlloc = bootAlloc)

  debugln &"boot: Creating new page tables"
  var pml4 = cast[ptr PML4Table](bootAlloc(1))

  # identity-map bootloader image
  debugln &"""boot:   {"Identity-mapping bootloader\:":<30} base={bootloaderBase:#010x}, pages={bootloaderPages}"""
  mapRegion(
    VMRegion(start: bootloaderBase.VirtAddr, npages: bootloaderPages),
    bootloaderBase.PhysAddr,
    pml4,
    paReadWrite,
    pmSupervisor,
    noExec = false,
  )

  # identity-map boot info
  debugln &"""boot:   {"Identity-mapping BootInfo\:":<30} base={bootInfoBase:#010x}, pages={bootInfoPages}"""
  mapRegion(
    VMRegion(start: bootInfoBase.VirtAddr, npages: bootInfoPages),
    bootInfoBase.PhysAddr,
    pml4,
    paReadWrite,
    pmSupervisor,
    noExec = true,
  )

  # map kernel to higher half
  debugln &"""boot:   {"Mapping kernel to higher half\:":<30} base={KernelVirtualBase:#010x}, pages={kernelImagePages}"""
  mapRegion(
    VMRegion(start: KernelVirtualBase.VirtAddr, npages: kernelImagePages),
    kernelImageBase.PhysAddr,
    pml4,
    paReadWrite,
    pmSupervisor,
    noExec = false,
  )

  # map kernel stack
  debugln &"""boot:   {"Mapping kernel stack\:":<30} base={KernelStackVirtualBase:#010x}, pages={kernelStackPages}"""
  mapRegion(
    VMRegion(start: KernelStackVirtualBase.VirtAddr, npages: kernelStackPages),
    kernelStackBase.PhysAddr,
    pml4,
    paReadWrite,
    pmSupervisor,
    noExec = true,
  )

  # map all physical memory; assume 128 MiB of physical memory
  debugln &"""boot:   {"Mapping physical memory\:":<30} base={PhysicalMemoryVirtualBase:#010x}, pages={physMemoryPages}"""
  mapRegion(
    VMRegion(start: PhysicalMemoryVirtualBase.VirtAddr, npages: physMemoryPages),
    0.PhysAddr,
    pml4,
    paReadWrite,
    pmSupervisor,
    noExec = true,
  )

  result = pml4

####################################################################################################
# Check UEFI return status
####################################################################################################

proc checkStatus(status: EfiStatus) =
  if status != EfiSuccess:
    consoleOutError &" [failed, status = {status:#x}]"
    quit()
  consoleOutSuccess " [success]\r\n"

####################################################################################################
# Report unhandled Nim exceptions
####################################################################################################

proc unhandledException(e: ref Exception) =
  echo "boot: Unhandled exception: " & e.msg & " [" & $e.name & "]"
  # debugln "boot: Unhandled exception: " & e.msg & " [" & $e.name & "]"
  echo ""
  # debugln ""
  if e.trace.len > 0:
    echo "boot: Stack trace:"
    # debugln "boot: Stack trace:"
    echo getStackTrace(e)
    # debugln getStackTrace(e)
  quit()
