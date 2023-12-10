import std/strformat

import common/libc
import common/malloc
import common/uefi

proc NimMain() {.importc.}

proc unhandledException*(e: ref Exception) =
  echo "boot: Unhandled exception: " & e.msg & " [" & $e.name & "]"
  echo ""
  if e.trace.len > 0:
    echo "boot: Stack trace:"
    echo getStackTrace(e)
  quit()

proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus =
  echo "Fusion OS Bootloader\n"

  var status: EfiStatus

  # get the LoadedImage protocol from the image handle
  var loadedImage: ptr EfiLoadedImageProtocol

  echo "boot: Acquiring LoadedImage protocol"
  status = uefi.sysTable.bootServices.handleProtocol(
    imgHandle, EfiLoadedImageProtocolGuid, cast[ptr pointer](addr loadedImage)
  )
  if status != EfiSuccess:
    echo &"Failed to get LoadedImage protocol: {status:#x}"
    quit()

  # get the FileSystem protocol from the device handle
  var deviceHandle = loadedImage.deviceHandle
  var fileSystem: ptr EfiSimpleFileSystemProtocol

  echo "boot: Acquiring FileSystem protocol"
  status = uefi.sysTable.bootServices.handleProtocol(
    deviceHandle, EfiSimpleFileSystemProtocolGuid, cast[ptr pointer](addr fileSystem)
  )
  if status != EfiSuccess:
    echo &"Failed to get FileSystem protocol: {status:#x}"
    quit()

  # open the root directory
  var rootDir: ptr EfiFileProtocol

  echo "boot: Opening root directory"
  status = fileSystem.openVolume(fileSystem, addr rootDir)
  if status != EfiSuccess:
    echo &"Failed to open root directory: {status:#x}"
    quit()

  # get rootDir file info
  var rootDirInfo: EfiFileSystemInfo
  var rootDirInfoSize = sizeof(EfiFileSystemInfo).uint

  echo "boot: Getting root directory info"
  status = rootDir.getInfo(rootDir, addr EfiFileSystemInfoGuid, addr rootDirInfoSize, addr rootDirInfo)
  if status != EfiSuccess:
    echo &"Failed to get root directory info: {status:#x}"
    quit()

  consoleOut "boot: Root directory volume label: "
  consoleOut cast[WideCString](addr rootDirInfo.volumeLabel)
  consoleOut "\r\n"

  # open the kernel file
  var kernelFile: ptr EfiFileProtocol
  let kernelPath = W"efi\fusion\kernel.bin"

  consoleOut "boot: Opening kernel file: "
  consoleOut kernelPath
  consoleOut "\r\n"
  status = rootDir.open(rootDir, addr kernelFile, kernelPath, 1, 1)
  if status != EfiSuccess:
    echo &"Failed to open kernel file: {cast[uint64](10):>0x}"
    quit()

  # get kernel file size
  var kernelInfo: EfiFileInfo
  var kernelInfoSize = sizeof(EfiFileInfo).uint

  echo "boot: Getting kernel file info"
  status = kernelFile.getInfo(kernelFile, addr EfiFileInfoGuid, addr kernelInfoSize, addr kernelInfo)
  if status != EfiSuccess:
    echo &"Failed to get kernel file info: {status:#x}"
    quit()

  echo &"boot: Kernel file size: {kernelInfo.fileSize}"

  # allocate memory for the kernel using AllocatePages
  var kernelPages = (kernelInfo.fileSize + 0xFFF).uint div 0x1000.uint
  var kernelAddr = cast[pointer](0x100000)

  echo &"boot: Allocating memory for kernel at {cast[uint64](kernelAddr):>#016x}"
  status = uefi.sysTable.bootServices.allocatePages(AllocateAddress, EfiRuntimeServicesData, kernelPages, cast[
      ptr EfiPhysicalAddress](addr kernelAddr))

  if status != EfiSuccess:
    echo &"Failed to allocate memory for kernel: {status:#x}"
    quit()

  # read the kernel into memory
  echo "boot: Reading kernel into memory"
  status = kernelFile.read(kernelFile, cast[ptr uint](addr kernelInfo.fileSize), kernelAddr)
  if status != EfiSuccess:
    echo &"Failed to read kernel into memory: {status:#x}"
    quit()

  # close the kernel file
  echo "boot: Closing kernel file"
  status = kernelFile.close(kernelFile)
  if status != EfiSuccess:
    echo &"Failed to close kernel file: {status:#x}"
    quit()

  # close the root directory
  echo "boot: Closing root directory"
  status = rootDir.close(rootDir)

  if status != EfiSuccess:
    echo &"Failed to close root directory: {status:#x}"
    quit()

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
    cast[ptr uint](nil),
    cast[ptr uint32](nil)
  )

  # allocate pool for memory map
  echo "boot: Allocating pool for memory map"
  inc memoryMapSize, sizeof(EfiMemoryDescriptor) * 2
  status = uefi.sysTable.bootServices.allocatePool(EfiLoaderData, memoryMapSize, cast[ptr pointer](
      addr memoryMap))
  if status != EfiSuccess:
    echo &"Failed to allocate pool for memory map: {status:#x}"
    quit()

  # get memory map
  echo "boot: Getting memory map, exiting boot services, and jumping to kernel"
  status = uefi.sysTable.bootServices.getMemoryMap(
    addr memoryMapSize, cast[ptr EfiMemoryDescriptor](memoryMap), addr memoryMapKey, addr memoryMapDescriptorSize,
        addr memoryMapDescriptorVersion
  )
  # IMPORTANT: After this point we cannot output anything to the console, since calling
  # a boot service may change the memory map and invalidate our map key. We can only
  # output to the console in case of an error (since we quit anyway).
  if status != EfiSuccess:
    echo &"Failed to get memory map: {status:#x}"
    quit()

  status = uefi.sysTable.bootServices.exitBootServices(imgHandle, memoryMapKey)
  if status != EfiSuccess:
    echo &"Failed to exit boot services: {status:#x}"
    quit()

  # ======= NO MORE UEFI BOOT SERVICES =======

  # jump to kernel
  var kernelEntry = cast[proc () {.cdecl.}](kernelAddr)
  kernelEntry()

  # we should never get here
  quit()


proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  NimMain()
  uefi.sysTable = sysTable
  consoleClear()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
