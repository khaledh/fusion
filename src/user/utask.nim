#[
  This is an example of a user task.
]#
import std/strutils

import common/[libc, malloc]
import syslib/[channels, io, os]

proc NimMain() {.importc.}

proc UserMain*(param: int) {.exportc.} =
  NimMain()

  let tid = os.getTaskId()

  if open(cid = 0, mode = ChannelMode.Write) < 0:
    exit(1)
  
  var dataIn: string

  if recv[string](cid = 0, dataIn) < 0:
    close(cid = 0)
    exit(1)
  
  print(dataIn)

  if dataIn.startsWith("ping"):
    sleep(100)
    send(cid = 0, data = "pong from task " & $tid)
    sleep(100)
    if recv[string](cid = 0, dataIn) < 0:
      close(cid = 0)
      exit(1)
    print(dataIn)

  elif dataIn.startsWith("pong"):
    sleep(100)
    send(cid = 0, data = "pong from task " & $tid)

  close(cid = 0)
  exit(0)
