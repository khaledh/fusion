#[
  Debug console output
]#
import std/strformat

import ports

type
  DebugLogger* = ref object
    name*: string

const DebugConPort = 0xe9

proc debug*(msgs: varargs[string]) =
  ## Send debug messages to the debug console port.
  for msg in msgs:
    for ch in msg:
      portOut8(DebugConPort, ch.uint8)

proc debugln*(msgs: varargs[string]) =
  ## Send debug messages to the debug console port. A newline is appended at the end.
  debug(msgs)
  debug("\r\n")


proc info*(logger: DebugLogger; msgs: varargs[string]) =
  ## Send info messages to the debug console port.
  debug &"[{logger.name:>7}] "
  debug(msgs)
  debug("\r\n")

proc raw*(logger: DebugLogger; msgs: varargs[string]) =
  ## Send raw messages to the debug console port.
  debug(msgs)
