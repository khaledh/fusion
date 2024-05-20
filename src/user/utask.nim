#[
  This is an example of a user task.
]#

import std/strformat

import common/[libc, malloc]
import syslib/[channels, io, os]

let NewLine = "\n"

proc NimMain() {.importc.}

proc UserMain*(param: int) {.exportc.} =
  NimMain()

  let paramMsg = "[task] param: "
  print(paramMsg.addr)
  let paramStr = $param
  print(paramStr.addr)

  let tid = os.getTaskId()

  let data = recv(chid = 0)
  let datastr = $data
  print(datastr.addr)

  if data == 1010:
    for j in 0..1000000:
      discard
    send(chid = 0, data = 2020)

  # let msg = $tid
  # for i in 0..50:
  #   print(msg.addr)
  #   for j in 0..1000000:
  #     discard

  # # if tid == 1:
  # #   print(newline.addr)
  # #   suspend()

  # for i in 0..50:
  #   print(msg.addr)
  #   for j in 0..1000000:
  #     discard

  # print(newline.addr)

  exit(0)
