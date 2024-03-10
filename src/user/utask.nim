import common/[libc, malloc]
import syslib/[io, os]

proc NimMain() {.importc.}

let
  msg = "Hello from user mode!"
  pmsg = msg.addr

proc UserMain*() {.exportc.} =
  NimMain()

  print(pmsg)
  yld()
  exit(0)
