import std/strformat

import common/[libc, malloc, pagetables, uefi]
import kernel/debugcon
import kernel/paging

const
  KernelPhysicalBase = 0x100000'u64
  KernelVirtualBase = 0xFFFF800000000000'u64


{.emit: """/*TYPESECTION*/
typedef __attribute__((sysv_abi)) void (*KernelEntryPoint)(void*, size_t, size_t);
""".}

type
  KernelEntryPoint {.importc: "KernelEntryPoint", nodecl.} = proc (
    memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
    memoryMapSize: uint,
    memoryMapDescriptorSize: uint,
  ) {.cdecl.}


# forward declarations
proc NimMain() {.importc.}
proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus
proc getStackRegion(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint64,
  memoryMapDescriptorSize: uint64
): tuple[stackBase: uint64, stackPages: uint64]
proc checkStatus*(status: EfiStatus)
proc unhandledException*(e: ref Exception)


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

  # # get rootDir file info
  # var rootDirInfo: EfiFileSystemInfo
  # var rootDirInfoSize = sizeof(EfiFileSystemInfo).uint

  # echo "boot: Getting root directory info"
  # status = rootDir.getInfo(rootDir, addr EfiFileSystemInfoGuid, addr rootDirInfoSize, addr rootDirInfo)
  # if status != EfiSuccess:
  #   echo &"Failed to get root directory info: {status:#x}"
  #   quit()

  # consoleOut "boot: Root directory volume label: "
  # consoleOut cast[WideCString](addr rootDirInfo.volumeLabel)
  # consoleOut "\r\n"

  # open the kernel file
  var kernelFile: ptr EfiFileProtocol
  let kernelPath = W"efi\fusion\kernel.bin"

  consoleOut "boot: Opening kernel file: "
  consoleOut kernelPath
  checkStatus rootDir.open(rootDir, addr kernelFile, kernelPath, 1, 1)

  # get kernel file size
  var kernelInfo: EfiFileInfo
  var kernelInfoSize = sizeof(EfiFileInfo).uint

  consoleOut "boot: Getting kernel file info"
  checkStatus kernelFile.getInfo(kernelFile, addr EfiFileInfoGuid, addr kernelInfoSize, addr kernelInfo)
  echo &"boot: Kernel file size: {kernelInfo.fileSize} bytes"

  # allocate memory for the kernel
  var kernelPages = (kernelInfo.fileSize + 0xFFF).uint div 0x1000.uint # round up to nearest page
  var kernelAddr = cast[pointer](KernelPhysicalBase)

  consoleOut &"boot: Allocating memory for kernel at {cast[uint64](kernelAddr):#x}"
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAddress,
    EfiLoaderCode,
    kernelPages,
    cast[ptr EfiPhysicalAddress](addr kernelAddr)
  )

  # read the kernel into memory
  consoleOut "boot: Reading kernel into memory"
  checkStatus kernelFile.read(kernelFile, cast[ptr uint](addr kernelInfo.fileSize), kernelAddr)

  # close the kernel file
  consoleOut "boot: Closing kernel file"
  checkStatus kernelFile.close(kernelFile)

  # close the root directory
  consoleOut "boot: Closing root directory"
  checkStatus rootDir.close(rootDir)

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
  inc memoryMapSize, memoryMapDescriptorSize

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

  # ======= NO MORE UEFI BOOT SERVICES =======

  debugln ""
  debugln "boot: Creating page table"
  # initialize a throw-away page table to map the kernel
  var pml4 = new PML4Table

  # identity-map bootloader image
  let bootloaderBase = cast[uint64](loadedImage.imageBase)
  let bootloaderPages = (loadedImage.imageSize.uint + 0xFFF) div 0x1000.uint
  debugln &"boot: Identity-mapping bootloader image: base={bootloaderBase:#x}, pages={bootloaderPages}"
  identityMapPages(pml4, bootloaderBase, bootloaderPages.uint64, paReadWrite, pmSupervisor)

  # identity-map bootloader stack
  let (stackBase, stackPages) = getStackRegion(memoryMap, memoryMapSize, memoryMapDescriptorSize)
  debugln &"boot: Identity-mapping stack: base={stackBase:#x}, pages={stackPages}"
  identityMapPages(pml4, stackBase, stackPages, paReadWrite, pmSupervisor)

  # identity-map memory map
  let memoryMapPages = (memoryMapSize + 0xFFF) div 0x1000.uint
  debugln &"boot: Identity-mapping memory map: base={cast[uint64](memoryMap):#x}, pages={memoryMapPages}"
  identityMapPages(pml4, cast[uint64](memoryMap), memoryMapPages, paReadWrite, pmSupervisor)

  # identity-map kernel
  debugln &"boot: Identity-mapping kernel: base={KernelPhysicalBase:#x}, pages={kernelPages}"
  identityMapPages(pml4, KernelPhysicalBase, kernelPages, paReadWrite, pmSupervisor)

  # map kernel to higher half
  debugln &"boot: Mapping kernel to higher half: base={KernelVirtualBase:#x}, pages={kernelPages}"
  mapPages(pml4, KernelVirtualBase, KernelPhysicalBase, kernelPages, paReadWrite, pmSupervisor)

  debugln "boot: Installing page table"
  installPageTable(pml4)

  # jump to kernel
  debugln "boot: Jumping to kernel"
  var kernelMain = cast[KernelEntryPoint](KernelVirtualBase)
  kernelMain(memoryMap, memoryMapSize, memoryMapDescriptorSize)

  # we should never get here
  quit()

proc getStackRegion(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint64,
  memoryMapDescriptorSize: uint64
): tuple[stackBase: uint64, stackPages: uint64] =
  # get stack pointer
  var rsp: uint64
  asm """
    mov %0, rsp
    :"=r"(`rsp`)
  """

  # scan memory map until we find the stack region
  var stackBase: uint64
  var stackPages: uint64
  let numMemoryMapEntries = memoryMapSize div memoryMapDescriptorSize
  for i in 0 ..< numMemoryMapEntries:
    let entry = cast[ptr EfiMemoryDescriptor](cast[uint64](memoryMap) + i * memoryMapDescriptorSize)
    if rsp > entry.physicalStart and rsp < entry.physicalStart + entry.numberOfPages * PageSize:
      stackBase = entry.physicalStart
      stackPages = entry.numberOfPages
      break

  return (stackBase, stackPages)

proc checkStatus*(status: EfiStatus) =
  if status != EfiSuccess:
    consoleOutError &" [failed, status = {status:#x}]"
    quit()
  consoleOutSuccess " [success]\r\n"

proc unhandledException*(e: ref Exception) =
  echo "boot: Unhandled exception: " & e.msg & " [" & $e.name & "]"
  debugln "boot: Unhandled exception: " & e.msg & " [" & $e.name & "]"
  echo ""
  debugln ""
  if e.trace.len > 0:
    echo "boot: Stack trace:"
    debugln "boot: Stack trace:"
    echo getStackTrace(e)
    debugln getStackTrace(e)
  quit()
