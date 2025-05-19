#[
  This is an example of a user task.
]#
import std/[strformat, strutils]

import common/[debugcon, libc, malloc]
import syslib/[channels, io, os]

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

  print(&"Hello from syscall (task: {tid})")


  # if open(cid = 0, mode = ChannelMode.Write) < 0:
  #   exit(1)
  
  # var dataIn: string

  # if recv[string](cid = 0, dataIn) < 0:
  #   close(cid = 0)
  #   exit(1)
  
  # print(dataIn)

  # if dataIn.startsWith(">>"):
  #   # sleep(100)
  #   # send(cid = 0, data = "<< \e[93mpong from task " & $tid & "\e[0m")
  #   # sleep(100)
  #   # if recv[string](cid = 0, dataIn) < 0:
  #   #   close(cid = 0)
  #   #   exit(1)
  #   print(dataIn)

  # elif dataIn.startsWith("<<"):
  #   print(dataIn)
  #   # sleep(100)
  #   # send(cid = 0, data = ">> \e[93mping from task " & $tid & "\e[0m")

  # close(cid = 0)

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
