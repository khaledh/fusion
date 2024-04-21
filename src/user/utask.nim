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

  let hello = &"Hello from task {tid}"
  print(hello.addr)

  yld()

  let bye = &"Bye from task {tid}"
  print(bye.addr)

  exit(0)
