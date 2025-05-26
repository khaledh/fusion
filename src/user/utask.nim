#[
  This is an example of a user task.
]#
import std/[strformat]

import common/[debugcon, libc, malloc]
import syslib/[channels, os]

const
  ConsoleChannelId = 0

proc NimMain() {.importc.}

proc UserMainInner(param: int)
proc unhandledException*(e: ref Exception)

proc UserMain(param: int) {.exportc.} =
  NimMain()

  try:
    UserMainInner(param)
  except Exception as e:
    unhandledException(e)

  exit(0)

proc UserMainInner(param: int) =

  let tid = os.getTaskId()

  let ch = channels.open[string](cid = ConsoleChannelId, mode = ChannelMode.Write)
  defer: ch.close()

  if ch.id < 0:
    debugln "Failed to open console channel"
    exit(1)

  ch.send(&"Hello from task {tid}\n")


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
