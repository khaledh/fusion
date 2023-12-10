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
    configTable*: pointer

  SimpleTextOutput* = object
    reset*: pointer
    outputString*: proc (this: ptr SimpleTextOutput, str: WideCString): EfiStatus {.cdecl.}
    testString*: pointer
    queryMode*: pointer
    setMode*: pointer
    setAttribute*: pointer
    clearScreen*: proc (this: ptr SimpleTextOutput): EfiStatus {.cdecl.}
    setCursorPos*: pointer
    enableCursor*: pointer
    mode*: ptr pointer

# typedef enum {
#    AllocateAnyPages,
#    AllocateMaxAddress,
#    AllocateAddress,
#    MaxAllocateType
# } EFI_ALLOCATE_TYPE;

  EfiAllocateType* = enum
    AllocateAnyPages,
    AllocateMaxAddress,
    AllocateAddress,
    MaxAllocateType,

  EfiBootServices* {.byref.} = object
    hdr*: EfiTableHeader
    # task priority services
    raiseTpl*: pointer
    restoreTpl*: pointer
    # memory services
    allocatePages*: proc (allocateType: EfiAllocateType, memoryType: EfiMemoryType, pages: uint,
        memory: ptr EfiPhysicalAddress): EfiStatus {.cdecl.}
    freePages*: pointer
    getMemoryMap*: proc (memoryMapSize: ptr uint, memoryMap: ptr EfiMemoryDescriptor,
        mapKey: ptr uint, descriptorSize: ptr uint, descriptorVersion: ptr uint32): EfiStatus {.cdecl.}
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
    EfiReservedMemoryType,
    EfiLoaderCode,
    EfiLoaderData,
    EfiBootServicesCode,
    EfiBootServicesData,
    EfiRuntimeServicesCode,
    EfiRuntimeServicesData,
    EfiConventionalMemory,
    EfiUnusableMemory,
    EfiACPIReclaimMemory,
    EfiACPIMemoryNVS,
    EfiMemoryMappedIO,
    EfiMemoryMappedIOPortSpace,
    EfiPalCode,
    EfiPersistentMemory,
    EfiUnacceptedMemoryType,
    EfiMaxMemoryType,

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
    openVolume*: proc (this: ptr EfiSimpleFileSystemProtocol, root: ptr ptr EfiFileProtocol): EfiStatus {.cdecl.}

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

  EfiFileSystemInfo* = object
    size*: uint64
    readOnly*: bool
    volumeSize*: uint64
    freeSpace*: uint64
    blockSize*: uint32
    volumeLabel*: array[32, Utf16Char]

  EfiFileInfo* = object
    size*: uint64
    fileSize*: uint64
    physicalSize*: uint64
    createTime*: EfiTime
    lastAccessTime*: EfiTime
    modificationTime*: EfiTime
    attribute*: uint64
    fileName*: array[256, Utf16Char]

# typedef struct {
#  UINT16 Year; // 1900 – 9999
#  UINT8 Month; // 1 – 12
#  UINT8 Day; // 1 – 31
#  UINT8 Hour; // 0 – 23
#  UINT8 Minute; // 0 – 59
#  UINT8 Second; // 0 – 59
#  UINT8 Pad1;
#  UINT32 Nanosecond; // 0 – 999,999,999
#  INT16 TimeZone; // -1440 to 1440 or 2047
#  UINT8 Daylight;
#  UINT8 Pad2;
# } EFI_TIME;

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

  EfiFileModeRead* = 0x0000000000000001
  EfiFileModeWrite* = 0x0000000000000002
  EfiFileModeCreate* = 0x8000000000000000

  EfiLoadedImageProtocolGuid* = EfiGuid(
    data1: 0x5B1B31A1, data2: 0x9562, data3: 0x11d2,
    data4: [0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  EfiSimpleFileSystemProtocolGuid* = EfiGuid(
    data1: 0x964e5b22'u32, data2: 0x6459, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  EfiFileSystemInfoGuid* = EfiGuid(
    data1: 0x9576e93'u32, data2: 0x6d3f, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  EfiFileInfoGuid* = EfiGuid(
    data1: 0x09576e92'u32, data2: 0x6d3f, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

var
  sysTable*: ptr EfiSystemTable


proc `W`*(s: static string): WideCString =
  result = newWideCString(s).toWideCString

proc consoleClear*() =
  assert not sysTable.isNil
  discard sysTable.conOut.clearScreen(sysTable.conOut)

proc consoleOut*(wstr: WideCString) =
  assert not sysTable.isNil
  discard sysTable.conOut.outputString(sysTable.conOut, wstr)

proc consoleOut*(str: string) =
  assert not sysTable.isNil
  let msg = newWideCString(str).toWideCString
  discard sysTable.conOut.outputString(sysTable.conOut, msg)

proc consoleError*(str: string) =
  assert not sysTable.isNil
  let msg = newWideCString(str).toWideCString
  discard sysTable.stdErr.outputString(sysTable.stdErr, msg)
