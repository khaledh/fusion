#[
  Fusion kernel UEFI bootloader
]#

import std/sets

import common/[bootinfo, malloc, pagetables]
import libc, uefi
import kernel/debugcon
import kernel/vmm

const
  PhysicalMemoryVirtualBase = 0xffff_8000_0000_0000'u64 # start of upper half

  KernelImagePhysicalBase = 0x10_0000'u64  # at 1 MiB
  KernelImageVirtualBase = 0xffff_ffff_8000_0000'u64 + KernelImagePhysicalBase

  BootInfoSize = 4 * KiB
  BootInfoPages = BootInfoSize div PageSize
  BootInfoVirtualBase = 0xffff_ffff_ffff_0000'u64 - BootInfoSize # Last page of address space

  KernelStackSize = 16 * KiB
  KernelStackPages = KernelStackSize div PageSize
  KernelStackVirtualEnd = BootInfoVirtualBase  # Right below BootInfo
  KernelStackVirtualBase = KernelStackVirtualEnd - KernelStackSize

let
  logger = DebugLogger(name: "boot")

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
  bootInfoPhysicalBase: uint64,
  physMemoryPages: uint64,
  physMemoryMap: seq[MemoryMapEntry],
  virtMemoryMap: seq[MemoryMapEntry],
  kernelImagePhysicalBase: uint64,
  kernelImagePages: uint64,
  kernelStackPhysicalBase: uint64,
  kernelStackPages: uint64,
  userImagePhysicalBase: uint64,
  userImagePages: uint64,
)

proc createPageTable(
  bootloaderPhysicalBase: uint64,
  bootloaderPages: uint64,
  kernelImagePhysicalBase: uint64,
  kernelImagePages: uint64,
  kernelStackPhysicalBase: uint64,
  kernelStackPages: uint64,
  bootInfoPhysicalBase: uint64,
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
  var efiLoadedImage: ptr EfiLoadedImageProtocol

  consoleOut "boot: Acquiring LoadedImage protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    imgHandle, EfiLoadedImageProtocolGuid, cast[ptr pointer](addr efiLoadedImage)
  )

  # get the FileSystem protocol from the device handle
  var fileSystem: ptr EfiSimpleFileSystemProtocol

  consoleOut "boot: Acquiring SimpleFileSystem protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    efiLoadedImage.deviceHandle, EfiSimpleFileSystemProtocolGuid, cast[ptr pointer](addr fileSystem)
  )

  # open the root directory
  var rootDir: ptr EfiFileProtocol

  consoleOut "boot: Opening root directory"
  checkStatus fileSystem.openVolume(fileSystem, addr rootDir)

  # load kernel image
  let (kernelImagePhysicalBase, kernelImagePages) = loadImage(
    imagePath = W"efi\fusion\kernel.bin",
    rootDir = rootDir,
    memoryType = OsvKernelCode,
    loadAddress = KernelImagePhysicalBase.EfiPhysicalAddress.some
  )

  # load user task image
  let (userImagePhysicalBase, userImagePages) = loadImage(
    imagePath = W"efi\fusion\utask.bin",
    rootDir = rootDir,
    memoryType = OsvUserCode,
  )

  # close the root directory
  consoleOut "boot: Closing root directory"
  checkStatus rootDir.close(rootDir)

  consoleOut &"boot: Allocating memory for kernel stack (16 KiB)"
  var kernelStackPhysicalBase: uint64
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAnyPages,
    OsvKernelStack,
    KernelStackPages,
    kernelStackPhysicalBase.addr,
  )

  consoleOut &"boot: Allocating memory for BootInfo"
  var bootInfoPhysicalBase: uint64
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAnyPages,
    OsvKernelData,
    1,
    bootInfoPhysicalBase.addr,
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
  # logger.info &"UEFI Memory Map ({numEntries} entries):"
  # logger.raw &"""   {"Entry"}"""
  # logger.raw &"""   {"Type":22}"""
  # logger.raw &"""   {"Start":>12}"""
  # logger.raw &"""   {"Start (KB)":>15}"""
  # logger.raw &"""   {"#Pages":>10}"""
  # logger.info ""

  # for i in 0 ..< numEntries:
  #   let entry = cast[ptr EfiMemoryDescriptor](cast[uint64](memoryMap) + i * memoryMapDescriptorSize)
  #   logger.raw &"   {i:>5}"
  #   logger.raw &"   {entry.type:22}"
  #   logger.raw &"   {entry.physicalStart:>#12x}"
  #   logger.raw &"   {entry.physicalStart div 1024:>#15}"
  #   logger.raw &"   {entry.numberOfPages:>#10}"
  #   logger.info ""

  # ======= NO MORE UEFI BOOT SERVICES =======

  logger.raw "Fusion UEFI Bootloader\n"
  logger.raw "\n"

  let physMemoryMap = convertUefiMemoryMap(memoryMap, memoryMapSize, memoryMapDescriptorSize)

  # get max free physical memory address
  var maxPhysAddr: PhysAddr
  for i in 0 ..< physMemoryMap.len:
    if physMemoryMap[i].type == Free:
      maxPhysAddr = physMemoryMap[i].start.PhysAddr +! physMemoryMap[i].nframes * PageSize

  let physMemoryPages: uint64 = maxPhysAddr.uint64 div PageSize

  let virtMemoryMap = createVirtualMemoryMap(kernelImagePages, physMemoryPages)

  logger.info &" Preparing BootInfo"
  initBootInfo(
    bootInfoPhysicalBase,
    physMemoryPages,
    physMemoryMap,
    virtMemoryMap,
    kernelImagePhysicalBase.uint64,
    kernelImagePages,
    kernelStackPhysicalBase,
    KernelStackPages,
    userImagePhysicalBase,
    userImagePages,
  )

  let bootloaderPages = (efiLoadedImage.imageSize.uint + 0xFFF) div 0x1000.uint

  let pml4 = createPageTable(
    cast[uint64](efiLoadedImage.imageBase),
    bootloaderPages,
    kernelImagePhysicalBase.uint64,
    kernelImagePages,
    kernelStackPhysicalBase,
    KernelStackPages,
    bootInfoPhysicalBase,
    BootInfoPages,
    physMemoryPages,
  )

  # jump to kernel
  let cr3 = cast[uint64](pml4)
  logger.info &" Jumping to kernel at {cast[uint64](KernelImageVirtualBase):#010x}"
  asm """
    mov rdi, %0  # bootInfo
    mov cr3, %1  # PML4
    mov rsp, %2  # kernel stack top
    jmp %3       # kernel entry point
    :
    : "r"(`bootInfoPhysicalBase`),
      "r"(`cr3`),
      "r"(`KernelStackVirtualEnd`),
      "r"(`KernelImageVirtualBase`)
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
    start: KernelImageVirtualBase,
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
    nframes: BootInfoPages
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
  bootInfoPhysicalBase: uint64,
  physMemoryPages: uint64,
  physMemoryMap: seq[MemoryMapEntry],
  virtMemoryMap: seq[MemoryMapEntry],
  kernelImagePhysicalBase: uint64,
  kernelImagePages: uint64,
  kernelStackPhysicalBase: uint64,
  kernelStackPages: uint64,
  userImagePhysicalBase: uint64,
  userImagePages: uint64,
) =
  var bootInfo = cast[ptr BootInfo](bootInfoPhysicalBase)
  bootInfo.physicalMemoryVirtualBase = PhysicalMemoryVirtualBase
  bootInfo.physicalMemoryPages = physMemoryPages

  # copy physical memory map entries to boot info
  bootInfo.physicalMemoryMap.len = physMemoryMap.len.uint
  bootInfo.physicalMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoPhysicalBase + sizeof(BootInfo).uint64)
  for i in 0 ..< physMemoryMap.len:
    bootInfo.physicalMemoryMap.entries[i] = physMemoryMap[i]
  let physMemoryMapSize = physMemoryMap.len.uint64 * sizeof(MemoryMapEntry).uint64

  # copy virtual memory map entries to boot info
  bootInfo.virtualMemoryMap.len = virtMemoryMap.len.uint
  bootInfo.virtualMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoPhysicalBase + sizeof(BootInfo).uint64 + physMemoryMapSize)
  for i in 0 ..< virtMemoryMap.len:
    bootInfo.virtualMemoryMap.entries[i] = virtMemoryMap[i]

  bootInfo.kernelImageVirtualBase = KernelImageVirtualBase
  bootInfo.kernelImagePhysicalBase = kernelImagePhysicalBase
  bootInfo.kernelImagePages = kernelImagePages

  bootInfo.kernelStackVirtualBase = KernelStackVirtualBase
  bootInfo.kernelStackPhysicalBase = kernelStackPhysicalBase
  bootInfo.kernelStackPages = kernelStackPages

  bootInfo.userImagePhysicalBase = userImagePhysicalBase
  bootInfo.userImagePages = userImagePages

####################################################################################################
# Page table mapping
####################################################################################################

type
  AlignedPage = object
    data {.align(PageSize).}: array[PageSize, uint8]

proc createPageTable(
  bootloaderPhysicalBase: uint64,
  bootloaderPages: uint64,
  kernelImagePhysicalBase: uint64,
  kernelImagePages: uint64,
  kernelStackPhysicalBase: uint64,
  kernelStackPages: uint64,
  bootInfoPhysicalBase: uint64,
  bootInfoPages: uint64,
  physMemoryPages: uint64,
): ptr PML4Table =

  proc bootAlloc(nframes: uint64): PhysAddr =
    result = cast[PhysAddr](new AlignedPage)

  # initialize vmm using identity-mapped physical memory
  vmInit(physMemoryVirtualBase = 0'u64, physAlloc = bootAlloc)

  logger.info &" Creating new page tables"
  var pml4 = cast[ptr PML4Table](bootAlloc(1))

  # identity-map bootloader image
  logger.info &"""   {"Identity-mapping bootloader\:":<30} base={bootloaderPhysicalBase:#010x}, pages={bootloaderPages}"""
  identityMapRegion(
    pml4, bootloaderPhysicalBase.PhysAddr, bootloaderPages.uint64,
    paReadWrite, pmSupervisor
  )

  # identity-map boot info
  logger.info &"""   {"Identity-mapping BootInfo\:":<30} base={bootInfoPhysicalBase:#010x}, pages={bootInfoPages}"""
  identityMapRegion(
    pml4, bootInfoPhysicalBase.PhysAddr, bootInfoPages,
    paReadWrite, pmSupervisor
  )

  # map all physical memory; assume 128 MiB of physical memory
  logger.info &"""   {"Mapping physical memory\:":<30} base={PhysicalMemoryVirtualBase:#010x}, pages={physMemoryPages}"""
  mapRegion(
    pml4, PhysicalMemoryVirtualBase.VirtAddr, 0.PhysAddr, physMemoryPages,
    paReadWrite, pmSupervisor
  )

  # map kernel to higher half
  logger.info &"""   {"Mapping kernel to higher half\:":<30} base={KernelImageVirtualBase:#010x}, pages={kernelImagePages}"""
  mapRegion(
    pml4, KernelImageVirtualBase.VirtAddr, kernelImagePhysicalBase.PhysAddr, kernelImagePages,
    paReadWrite, pmSupervisor
  )

  # map kernel stack
  logger.info &"""   {"Mapping kernel stack\:":<30} base={KernelStackVirtualBase:#010x}, pages={kernelStackPages}"""
  mapRegion(
    pml4, KernelStackVirtualBase.VirtAddr, kernelStackPhysicalBase.PhysAddr, kernelStackPages,
    paReadWrite, pmSupervisor
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
  # logger.info "boot: Unhandled exception: " & e.msg & " [" & $e.name & "]"
  echo ""
  # logger.info ""
  if e.trace.len > 0:
    echo "boot: Stack trace:"
    # logger.info "boot: Stack trace:"
    echo getStackTrace(e)
    # logger.info getStackTrace(e)
  quit()
