import libc
import uefi

proc writeError(msg: string) =
  let msg = newWideCString(msg).toWideCString
  discard conOut.outputString(conOut, addr msg[0])

proc handleException(e: ref Exception) {.raises: [].} =
  writeError(e.msg)
  quit(1)

proc NimMain() {.importc.}

proc main(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc, raises: [ValueError].} =
  NimMain()

  errorMessageWriter = writeError
  onUnhandledException = writeError
  unhandledExceptionHook = handleException

  conOut = sysTable.conOut
  # discard sysTable.conOut.clearScreen(sysTable.conOut)

  let y = 10
  let x = 10 div y
  writeError($x & "\n")
  # echo "hello"

  raise newException(ValueError, "ValueError")

  # write(syncio.stderr, "Error")
  
  # let msg = newWideCString("Hello, world!").toWideCString
  # discard sysTable.conOut.outputString(sysTable.conOut, addr msg[0])

  # quit(0)
