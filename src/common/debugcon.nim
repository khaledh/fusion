#[
  Debug console output
]#
import std/strformat

type
  DebugLogger* = ref object
    name*: string

const QemuDebugConPort = 0xe9

# ansi color codes
template dim*(): string = &"\e[38;5;{242}m"
template undim*(): string = "\e[0m"
template dimmed*(s: untyped): string = dim() & s & undim()
template hex*(): string = dimmed("h")

type
  BinUnit* = enum
    bDynamic, bThousands, bBytes, bKiB, bMiB, bGiB, bTiB

const
  KiB* = 1024
  MiB* = KiB * KiB
  GiB* = KiB * MiB
  TiB* = KiB * GiB

proc bytesToBinSize*(size: uint64, unit: BinUnit = bDynamic): string =
  ## Convert a size in bytes to a human-readable format.
  if unit == bBytes or (unit == bDynamic and size < KiB or unit == bThousands and size < MiB):
    return &"{size} B"
  elif unit == bKiB or (unit == bDynamic and size < MiB or unit == bThousands and size < GiB):
    return &"{size div KiB} KiB"
  elif unit == bMiB or (unit == bDynamic and size < GiB or unit == bThousands and size < TiB):
    return &"{size div MiB} MiB"
  elif unit == bGiB or (unit == bDynamic and size < TiB or unit == bThousands):
    return &"{size div GiB} GiB"
  else:
    return &"{size div TiB} TiB"

proc portOut8(port: uint16, data: uint8) =
  asm """
    out %0, %1
    :
    :"Nd"(`port`), "a"(`data`)
  """

proc debug*(msgs: varargs[string]) =
  ## Send debug messages to the debug console port.
  for msg in msgs:
    for ch in msg:
      portOut8(QemuDebugConPort, ch.uint8)

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
