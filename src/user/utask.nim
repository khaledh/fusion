#[
  This is an example of a user task.
]#
import std/[strformat, strutils]

import common/[debugcon, libc, malloc]
import syslib/[channels, io, os]

const
  ConsoleChannelId = 0
  KernelTestChannelId = 1

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

  if open(cid = ConsoleChannelId, mode = ChannelMode.Write) >= 0:
    send(cid = ConsoleChannelId, data = &"Hello from task {tid}\n")
  else:
    debugln &"Failed to open console channel"

  if open(cid = KernelTestChannelId, mode = ChannelMode.Write) < 0:
    exit(1)
  
  var dataIn: string

  if recv[string](cid = KernelTestChannelId, dataIn) < 0:
    close(cid = KernelTestChannelId)
    exit(1)
  
  print(dataIn)

  if dataIn.startsWith(">>"):
    sleep(100)
    send(cid = KernelTestChannelId, data = "<< \e[93mpong from task " & $tid & "\e[0m")
    sleep(100)
    if recv[string](cid = KernelTestChannelId, dataIn) < 0:
      close(cid = KernelTestChannelId)
      exit(1)
    print(dataIn)

  elif dataIn.startsWith("<<"):
    print(dataIn)
    sleep(100)
    send(cid = KernelTestChannelId, data = ">> \e[93mping from task " & $tid & "\e[0m")

  close(cid = KernelTestChannelId)

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
