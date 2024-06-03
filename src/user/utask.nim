#[
  This is an example of a user task.
]#

import common/[libc, malloc]
import syslib/[channels, io, os]

let NewLine = "\n"

proc NimMain() {.importc.}

proc UserMain*(param: int) {.exportc.} =
  NimMain()

  # let paramMsg = "param: "
  # print(paramMsg.addr)
  # let paramStr = $param
  # print(paramStr.addr)

  # let tid = os.getTaskId()

  var data = recv(chid = 0)
  var datastr = $data
  print(datastr.addr)

  if data == 1010:
    sleep(100)

    send(chid = 0, data = 2020)

    sleep(100)

    data = recv(chid = 0)
    datastr = $data
    print(datastr.addr)

  if data == 2020:
    sleep(100)
    send(chid = 0, data = 3030)

  exit(0)
