#[
  Startup code for Fusion user tasks.
]#
{.used.}
import std/[strformat]

import common/[debugcon, libc, malloc]
import syslib/os

proc main(param: int): int {.importc.}

proc NimMain() {.importc.}
proc unhandledException*(e: ref Exception)

proc FusionStart(param: int) {.exportc.} =
  NimMain()

  var exitCode = 0
  try:
    exitCode = main(param)
  except Exception as e:
    unhandledException(e)

  exit(exitCode)

####################################################################################################
# Report unhandled Nim exceptions
####################################################################################################

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debug getStackTrace(e)
