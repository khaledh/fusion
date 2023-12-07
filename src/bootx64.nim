import libc
import uefi

proc writeError(msg: string) =
  # let str = msg.replace("\n", "\r\n")
  let wstr = newWideCString(msg).toWideCString
  discard conOut.outputString(conOut, addr wstr[0])

proc writeError(msg: cstring) =
  writeError($msg)

proc unhandledException(e: ref Exception) {.raises: [].} =
  writeError("\nUnhandled exception: " & e.msg & " [" & $e.name & "]\n\n")
  writeError("Stack trace:\n")
  writeError(getStackTrace(e))
  quit()

errorMessageWriter = writeError
onUnhandledException = writeError
unhandledExceptionHook = unhandledException

proc NimMain() {.importc.}

proc dowork(n: int): int =
  let a = [1, 2, 3]

  if n == 0:
    raise newException(ValueError, "n must be > 0")

  if n > 0:
    return a[n]
  else:
    raise newException(ValueError, "n cannot be negative")


proc InnerEfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus =
  conOut = sysTable.conOut
  discard sysTable.conOut.clearScreen(sysTable.conOut)

  echo "Fusion OS"

  writeError($dowork(-5))

  # nimTestErrorFlag()

  # write(syncio.stderr, "Error")
  
  # let msg = newWideCString("Hello, world!").toWideCString
  # discard sysTable.conOut.outputString(sysTable.conOut, addr msg[0])

  # quit(0)

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  NimMain()
  try:
    return InnerEfiMain(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
    return EfiLoadError
