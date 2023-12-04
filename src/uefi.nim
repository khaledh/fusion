type
  EfiStatus* = uint

  EfiHandle* = pointer

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
    stdErr*: pointer
    runtimeServices*: pointer
    bootServices*: pointer
    numTableEntries*: uint
    configTable*: pointer
  
  SimpleTextOutput* = object
    reset*: pointer
    outputString*: proc (this: ptr SimpleTextOutput, str: ptr Utf16Char): EfiStatus {.cdecl, gcsafe, tags: [], raises: [].}
    testString*: pointer
    queryMode*: pointer
    setMode*: proc (this: ptr SimpleTextOutput, modeNum: uint): EfiStatus {.cdecl.}
    setAttribute*: pointer
    clearScreen*: proc (this: ptr SimpleTextOutput): EfiStatus {.cdecl.}
    setCursorPos*: pointer
    enableCursor*: pointer
    mode*: ptr pointer

const
  EfiSuccess* = 0
  EfiLoadError* = 1

var
  conOut*: ptr SimpleTextOutput
