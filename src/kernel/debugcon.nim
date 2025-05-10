#[
  Debug console output
]#
import std/strformat

import ports

type
  DebugLogger* = ref object
    name*: string

# ansi color codes
template dim*(): string = &"\e[38;5;{242}m"
template undim*(): string = "\e[0m"
template dimmed*(s: untyped): string = dim() & s & undim()
template hex*(): string = dimmed("h")

const
  KiB* = 1024
  MiB* = KiB * KiB
  GiB* = KiB * MiB

proc bytesToBinSize*(size: uint64): string =
  ## Convert a size in bytes to a human-readable format.
  if size < 1024:
    &"{size} B"
  elif size < 1024 * 1024:
    &"{size div KiB} KiB"
  elif size < 1024 * 1024 * 1024:
    &"{size div MiB} MiB"
  else:
    &"{size div GiB} GiB"

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
  debug &"{dim()}[{logger.name:>8}] {undim()}"
  debug(msgs)
  debug("\r\n")

proc raw*(logger: DebugLogger; msgs: varargs[string]) =
  ## Send raw messages to the debug console port.
  debug(msgs)
