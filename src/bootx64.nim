type
  EfiHandle = uint
  EfiStatus = uint
  EFiSystemTable = object

proc efiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  return 42
