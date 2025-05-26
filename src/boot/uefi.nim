#[
  x86_64 UEFI bindings for Nim
]#

import std/tables

import common/guid

let
  logger = DebugLogger(name: "uefi")

type
  EfiGuid* = object
    data1: uint32
    data2: uint16
    data3: uint16
    data4: array[8, uint8]

  EfiStatus* = uint64

  EfiHandle* = pointer

  EfiPhysicalAddress* = uint64
  EfiVirtualAddress* = uint64

  EfiTableHeader* = object
    signature*: uint64
    revision*: uint32
    headerSize*: uint32
    crc32*: uint32
    reserved*: uint32

  EfiSystemTable* = object
    header*: EfiTableHeader
    firmwareVendor*: WideCString
    firmwareRevision*: uint32
    consoleInHandle*: EfiHandle
    conIn*: pointer
    consoleOutHandle*: EfiHandle
    conOut*: ptr SimpleTextOutput
    standardErrorHandle*: EfiHandle
    stdErr*: ptr SimpleTextOutput
    runtimeServices*: pointer
    bootServices*: ptr EfiBootServices
    numTableEntries*: uint
    configTable*: ptr UncheckedArray[EfiConfigurationTableEntry]

  EfiConfigurationTableEntry* = object
    vendorGuid*: Guid
    vendorTable*: uint64

  SimpleTextOutput* = object
    reset*: pointer
    outputString*: proc (this: ptr SimpleTextOutput, str: WideCString): EfiStatus {.cdecl.}
    testString*: pointer
    queryMode*: pointer
    setMode*: pointer
    setAttribute*: proc (this: ptr SimpleTextOutput, attr: uint64): EfiStatus {.cdecl.}
    clearScreen*: proc (this: ptr SimpleTextOutput): EfiStatus {.cdecl.}
    setCursorPos*: pointer
    enableCursor*: pointer
    mode*: ptr pointer

  SimpleTextForegroundColor* = enum
    fgBlack
    fgBlue
    fgGreen
    fgCyan
    fgRed
    fgMagenta
    fgBrown
    fgLightGray
    fgDarkGray
    fgLightBlue
    fgLightGreen
    fgLightCyan
    fgLightRed
    fgLightMagenta
    fgYellow
    fgWhite

  SimpleTextBackgroundColor* = enum
    bgBlack = 0x00
    bgBlue = 0x10
    bgGreen = 0x20
    bgCyan = 0x30
    bgRed = 0x40
    bgMagenta = 0x50
    bgBrown = 0x60
    bgLightGray = 0x70

  EfiAllocateType* = enum
    AllocateAnyPages,
    AllocateMaxAddress,
    AllocateAddress,
    MaxAllocateType,

  EfiBootServices* = object
    hdr*: EfiTableHeader
    # task priority services
    raiseTpl*: pointer
    restoreTpl*: pointer
    # memory services
    allocatePages*: proc (
        allocateType: EfiAllocateType,
        memoryType: EfiMemoryType,
        pages: uint,
        memory: ptr EfiPhysicalAddress
      ): EfiStatus {.cdecl.}
    freePages*: pointer
    getMemoryMap*: proc (
        memoryMapSize: ptr uint,
        memoryMap: ptr EfiMemoryDescriptor,
        mapKey: ptr uint,
        descriptorSize: ptr uint,
        descriptorVersion: ptr uint32
      ): EfiStatus {.cdecl.}
    allocatePool*: proc (poolType: EfiMemoryType, size: uint, buffer: ptr pointer): EfiStatus {.cdecl.}
    freePool*: pointer
    # event & timer services
    createEvent*: pointer
    setTimer*: pointer
    waitForEvent*: pointer
    signalEvent*: pointer
    closeEvent*: pointer
    checkEvent*: pointer
    # protocol handler services
    installProtocolInterface*: pointer
    reinstallProtocolInterface*: pointer
    uninstallProtocolInterface*: pointer
    handleProtocol*: proc (handle: EfiHandle, protocol: EfiGuid, `interface`: ptr pointer): EfiStatus {.cdecl.}
    reserved*: pointer
    registerProtocolNotify*: pointer
    locateHandle*: pointer
    locateDevicePath*: pointer
    installConfigurationTable*: pointer
    # image services
    loadImage*: pointer
    startImage*: pointer
    exit*: pointer
    unloadImage*: pointer
    exitBootServices*: proc (imageHandle: EfiHandle, mapKey: uint): EfiStatus {.cdecl.}
    # misc services
    getNextMonotonicCount*: pointer
    stall*: pointer          # Stall
    setWatchdogTimer*: pointer
    # driver support services
    connectController*: pointer
    disconnectController*: pointer
    # open and close protocol services
    openProtocol*: pointer
    closeProtocol*: pointer
    openProtocolInformation*: pointer
    # library services
    protocolsPerHandle*: pointer
    locateHandleBuffer*: pointer
    locateProtocol*: pointer # LocateProtocol
    installMultipleProtocolInterfaces*: pointer
    uninstallMultipleProtocolInterfaces*: pointer
    # 32-bit CRC services
    calculateCrc32*: pointer
    # misc services
    copyMem*: pointer
    setMem*: pointer
    createEventEx*: pointer

  EfiMemoryType* = enum
    EfiReservedMemory
    EfiLoaderCode
    EfiLoaderData
    EfiBootServicesCode
    EfiBootServicesData
    EfiRuntimeServicesCode
    EfiRuntimeServicesData
    EfiConventionalMemory
    EfiUnusableMemory
    EfiACPIReclaimMemory
    EfiACPIMemoryNVS
    EfiMemoryMappedIO
    EfiMemoryMappedIOPortSpace
    EfiPalCode
    EfiPersistentMemory
    EfiUnacceptedMemory
    OsvKernelCode = 0x80000000
    OsvKernelData = 0x80000001
    OsvKernelStack = 0x80000002
    OsvUserCode = 0x80000003
    EfiMaxMemoryType

  EfiMemoryDescriptor* = object
    `type`*: EfiMemoryType
    physicalStart*: EfiPhysicalAddress
    virtualStart*: EfiVirtualAddress
    numberOfPages*: uint64
    attribute*: uint64

  EfiLoadedImageProtocol* = object
    revision*: uint32
    parentHandle*: EfiHandle
    systemTable*: ptr EfiSystemTable

    # Source location of the image
    deviceHandle*: EfiHandle
    filePath*: pointer # ptr EfiDevicePathProtocol
    reserved*: pointer

    # Image's load options
    loadOptionsSize*: uint32
    loadOptions*: pointer

    # Location where image was loaded
    imageBase*: pointer
    imageSize*: uint64
    imageCodeType*: EfiMemoryType
    imageDataType*: EfiMemoryType
    unload*: pointer   # EfiImageUnload

  EfiSimpleFileSystemProtocol* = object
    revision*: uint64
    openVolume*: proc (
        this: ptr EfiSimpleFileSystemProtocol,
        root: ptr ptr EfiFileProtocol
      ): EfiStatus {.cdecl.}

  EfiFileProtocol* = object
    revision*: uint64
    open*: proc (this: ptr EfiFileProtocol, newHandle: ptr ptr EfiFileProtocol, fileName: WideCString,
        openMode: uint64, attributes: uint64): EfiStatus {.cdecl.}
    close*: proc (this: ptr EfiFileProtocol): EfiStatus {.cdecl.}
    delete*: pointer
    read*: proc (this: ptr EfiFileProtocol, bufferSize: ptr uint, buffer: pointer): EfiStatus {.cdecl.}
    write*: pointer
    getPosition*: pointer
    setPosition*: pointer
    getInfo*: proc (this: ptr EfiFileProtocol, infoType: ptr EfiGuid, infoSize: ptr uint,
        info: pointer): EfiStatus {.cdecl.}
    setInfo*: pointer
    flush*: pointer
    openEx*: pointer
    readEx*: pointer
    writeEx*: pointer
    flushEx*: pointer

# EfiFileSystemInfo* = object
  #   size*: uint64
  #   readOnly*: bool
  #   volumeSize*: uint64
  #   freeSpace*: uint64
  #   blockSize*: uint32
  #   volumeLabel*: array[32, Utf16Char]

  EfiFileInfo* = object
    size*: uint64
    fileSize*: uint64
    physicalSize*: uint64
    createTime*: EfiTime
    lastAccessTime*: EfiTime
    modificationTime*: EfiTime
    attribute*: uint64
    fileName*: array[256, Utf16Char]

  EfiTime* = object
    year*: uint16
    month*: uint8
    day*: uint8
    hour*: uint8
    minute*: uint8
    second*: uint8
    pad1*: uint8
    nanosecond*: uint32
    timeZone*: int16
    daylight*: uint8
    pad2*: uint8

const
  EfiSuccess* = 0'u64
  EfiLoadError* = 1'u64

  # EfiFileModeRead* = 0x0000000000000001
  # EfiFileModeWrite* = 0x0000000000000002
  # EfiFileModeCreate* = 0x8000000000000000

  EfiLoadedImageProtocolGuid* = EfiGuid(
    data1: 0x5B1B31A1, data2: 0x9562, data3: 0x11d2,
    data4: [0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  EfiSimpleFileSystemProtocolGuid* = EfiGuid(
    data1: 0x964e5b22'u32, data2: 0x6459, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  # EfiFileSystemInfoGuid* = EfiGuid(
  #   data1: 0x9576e93'u32, data2: 0x6d3f, data3: 0x11d2,
  #   data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  # )

  EfiFileInfoGuid* = EfiGuid(
    data1: 0x09576e92'u32, data2: 0x6d3f, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

var
  sysTable*: ptr EfiSystemTable

####################################################################################################
# UEFI console output
####################################################################################################

proc `W`*(s: string): WideCString =
  result = newWideCString(s).toWideCString

proc consoleClear*() =
  assert not sysTable.isNil
  discard sysTable.conOut.clearScreen(sysTable.conOut)

proc consoleOut*(wstr: WideCString) =
  assert not sysTable.isNil
  discard sysTable.conOut.outputString(sysTable.conOut, wstr)

proc consoleOut*(str: string) =
  assert not sysTable.isNil
  discard sysTable.conOut.outputString(sysTable.conOut, W(str))

proc consoleError*(str: string) =
  assert not sysTable.isNil
  discard sysTable.stdErr.outputString(sysTable.stdErr, W(str))

proc consoleOutColor*(
  str: string,
  fg: SimpleTextForegroundColor,
  bg: SimpleTextBackgroundColor = bgBlack
) =
  discard sysTable.conOut.setAttribute(sysTable.conOut, fg.uint + (bg.uint shl 4))
  consoleOut(str)
  discard sysTable.conOut.setAttribute(sysTable.conOut, fgLightGray.uint + (bgBlack.uint shl 4))

proc consoleOutSuccess*(str: string) =
  consoleOutColor(str, fgGreen)

proc consoleOutError*(str: string) =
  consoleOutColor(str, fgLightRed)

####################################################################################################
# UEFI configuration tables
####################################################################################################

const
  EfiLzmaCustomDecompressGuid*   = parseGuid("ee4e5898-3914-4259-6e9d-dc7bd79403cf")
  EfiDxeServicesTableGuid*       = parseGuid("05ad34ba-6f02-4214-2e95-4da0398e2bb9")
  EfiHobListGuid*                = parseGuid("7739f24c-93d7-11d4-3a9a-0090273fc14d")
  EfiMemoryTypeInfoGuid*         = parseGuid("4c19049f-4137-4dd3-109c-8b97a83ffdfa")
  EfiDebugImageInfoTableGuid*    = parseGuid("49152e77-1ada-4764-a2b7-7afefed95e8b")
  EfiMemoryStatusCodeRecordGuid* = parseGuid("060cc026-4c0d-4dda-418f-595fef00a502")
  EfiSmbiosTableGuid*            = parseGuid("eb9d2d31-2d88-11d3-169a-0090273fc14d")
  EfiAcpi1TableGuid*             = parseGuid("eb9d2d30-2d88-11d3-169a-0090273fc14d")
  EfiAcpi2TableGuid*             = parseGuid("8868e871-e4f1-11d3-22bc-0080c73c8881")
  EfiMemoryAttributesTableGuid*  = parseGuid("dcfa911d-26eb-469f-20a2-38b7dc461220")

let efiGuids = {
  EfiLzmaCustomDecompressGuid   : ("LZMA_CUSTOM_DECOMPRESS_GUID", "LZMA Custom Decompress"),
  EfiDxeServicesTableGuid       : ("DXE_SERVICES_TABLE_GUID", "DXE Services Table"),
  EfiHobListGuid                : ("HOB_LIST_GUID", "HOB (Hand-Off Block) List"),
  EfiMemoryTypeInfoGuid         : ("EFI_MEMORY_TYPE_INFORMATION_GUID", "Memory Type Information"),
  EfiDebugImageInfoTableGuid    : ("EFI_DEBUG_IMAGE_INFO_TABLE_GUID", "Debug Image Info Table"),
  EfiMemoryStatusCodeRecordGuid : ("MEMORY_STATUS_CODE_RECORD_GUID", "Memory Status Code Record"),
  EfiSmbiosTableGuid            : ("SMBIOS_TABLE_GUID", "SMBIOS Table"),
  EfiAcpi1TableGuid             : ("ACPI_TABLE_GUID", "ACPI 1.0 Table"),
  EfiAcpi2TableGuid             : ("EFI_ACPI_TABLE_GUID", "ACPI 2.0+ Table"),
  EfiMemoryAttributesTableGuid  : ("EFI_MEMORY_ATTRIBUTES_TABLE_GUID", "Memory Attributes Table"),
}.toTable

proc getUefiConfigTables*(st: ptr EfiSystemTable): Table[Guid, uint64] =
  for i in 0 ..< st.numTableEntries:
    let entry = st.configTable[i]
    result[entry.vendorGuid] = entry.vendorTable

proc dumpUefiConfigTables*(st: ptr EfiSystemTable) =
  let configTables = getUefiConfigTables(st)

  logger.info ""
  logger.info "UEFI Configuration Tables"
  for guid in configTables.keys:
    if guid in efiGuids:
      logger.info &"  {$guid}  {efiGuids[guid][1]}"
    else:
      logger.info &"  {$guid}"
  logger.info ""

####################################################################################################
# Print UEFI memory map
####################################################################################################

proc printUefiMemoryMap(
  memoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  memoryMapSize: uint,
  memoryMapDescriptorSize: uint,
) =
  let numEntries = memoryMapSize div memoryMapDescriptorSize
  logger.info &"UEFI Memory Map ({numEntries} entries):"
  logger.raw &"""   {"Entry"}"""
  logger.raw &"""   {"Type":22}"""
  logger.raw &"""   {"Start (hex)":>12}"""
  logger.raw &"""   {"Start":>10}"""
  logger.raw &"""   {"Size":>10} {dimmed("(#Pages)")}"""
  logger.raw "\n"
  
  var prevEnd = 0'u64
  for i in 0 ..< numEntries:
    let entry = cast[ptr EfiMemoryDescriptor](cast[uint64](memoryMap) + i * memoryMapDescriptorSize)
    if entry.physicalStart.uint64 != prevEnd:
      # gap
      let size = entry.physicalStart.uint64 - prevEnd
      logger.raw &"""           {dim()}{"-- gap --":22}"""
      logger.raw &"   {prevEnd:>11x}h"
      logger.raw &"   {bytesToBinSize(prevEnd):>10}"
      logger.raw &"   {bytesToBinSize(size):>10} ({size div 4096})"
      logger.raw &"{undim()}\n"
    logger.raw &"   {i:>5}"
    logger.raw &"   {entry.type:22}"
    logger.raw &"   {entry.physicalStart:>11x}{hex()}"
    logger.raw &"   {bytesToBinSize(entry.physicalStart):>10}"
    logger.raw &"   {bytesToBinSize(entry.numberOfPages * PageSize):>10} {dim()}({entry.numberOfPages}){undim()}"
    logger.raw "\n"
    prevEnd = entry.physicalStart + entry.numberOfPages * PageSize

