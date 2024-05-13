#[
  This is an example of a user task.
]#

import std/strformat

import common/[libc, malloc]
import syslib/[io, os]

proc NimMain() {.importc.}

proc UserMain*() {.exportc.} =
  NimMain()

  let tid = os.getTaskId()

  let msg = $tid
  for i in 0..100:
    print(msg.addr)
    for j in 0..1000000:
      discard

  let newline = "\n"
  print(newline.addr)
  # yld()

  # let bye = &"Bye from task {tid}"
  # print(bye.addr)

  exit(0)
