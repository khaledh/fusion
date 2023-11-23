type
  EfiStatus = uint
  EfiHandle = pointer
  EFiSystemTable = object # to be defined later

proc efiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  return 0
