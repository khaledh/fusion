#[
  This is an example of a user task.
]#

import common/[libc, malloc]
import syslib/[channels, io, os]

proc NimMain() {.importc.}

proc UserMain*(param: int) {.exportc.} =
  NimMain()

  # let paramMsg = "param: "
  # print(paramMsg.addr)
  # let paramStr = $param
  # print(paramStr.addr)

  let tid = os.getTaskId()

  let ret = open(cid = 0, mode = 1)

  if ret < 0:
    exit(1)
  
  var dataIn = recv[ptr uint64](cid = 0)
  if dataIn.isNil:
    close(cid = 0)
    exit(1)
  
  var dataInStr = $dataIn[]
  print(addr dataInStr)

  if dataIn[] == 1010:
    sleep(100)

    var dataOut = 2020
    send(cid = 0, data = addr dataOut)

    sleep(100)

    dataIn = recv[ptr uint64](cid = 0)
    if dataIn.isNil:
      close(cid = 0)
      exit(1)
    dataInStr = $dataIn[]
    print(addr dataInStr)

  if dataIn[] == 2020:
    var dataOut = new(int)
    dataOut[] = 3030
    sleep(100)
    send(cid = 0, data = cast[ptr int](dataOut))

  close(cid = 0)
  exit(0)
