#[
  PS/2 keyboard driver.
]#
import std/strformat

import ports
import kernel/channels
import kernel/idt
import kernel/ioapic
import kernel/lapic

let
  logger = DebugLogger(name: "kbd")

const
  KbdInterruptVector = 0x21'u8

  kbdUs = [
    '\0', '\x1B', '1',  '2',  '3',  '4',  '5',  '6',  # 00-07
    '7',  '8',    '9',  '0',  '-',  '=',  '\b', '\t', # 08-0f
    'q',  'w',    'e',  'r',  't',  'y',  'u',  'i',  # 10-17
    'o',  'p',    '[',  ']',  '\n', '\0', 'a',  's',  # 18-1f
    'd',  'f',    'g',  'h',  'j',  'k',  'l',  ';',  # 20-27
    '\'', '`',    '\0', '\\', 'z',  'x',  'c',  'v',  # 28-2f
    'b',  'n',    'm',  ',',  '.',  '/',  '\0', '*',  # 30-37
    '\0', ' ',    '\0', '\0', '\0', '\0', '\0', '\0', # 38-3f
    '\0', '\0',   '\0', '\0', '\0', '\0', '\0', '7',  # 40-47
    '8',  '9',    '-',  '4',  '5',  '6',  '+',  '1',  # 48-4f
    '2',  '3',    '0',  '.',  '\0', '\0', '\0', '\0', # 50-57
    '\0',                                             # 58-5f
  ]
  kbdUsShift = [
    '\0', '\x1B', '!',  '@',  '#',  '$',  '%',  '^',  # 00-07
    '&',  '*',  '(',  ')',    '_',  '+',  '\b', '\t', # 08-0f
    'Q',  'W',  'E',  'R',    'T',  'Y',  'U',  'I',  # 10-17
    'O',  'P',  '{',  '}',    '\n', '\0', 'A',  'S',  # 18-1f
    'D',  'F',  'G',  'H',    'J',  'K',  'L',  ':',  # 20-27
    '"',  '~',  '\0', '|',    'Z',  'X',  'C',  'V',  # 28-2f
    'B',  'N',  'M',  '<',    '>',  '?'
  ]

type
  KeyEventType* = enum
    KeyDown = (0, "KeyDown")
    KeyUp = (1, "KeyUp")
  KeyEvent* = object
    eventType*: KeyEventType
    scanCode: uint8
    ch*: char
    shift*: bool
    ctrl*: bool
    alt*: bool

var
  shift, ctrl, alt = false
  kbdChId: int

proc `$`*(evt: KeyEvent): string =
  result.add($evt.eventType)
  if evt.ch == '\0':
    result.add("(NUL)")
  elif evt.ch == '\x1B':
    result.add("(ESC)")
  elif evt.ch == '\n':
    result.add("(LF)")
  elif evt.ch == '\t':
    result.add("(TAB)")
  elif evt.ch == '\b':
    result.add("(BS)")
  elif evt.ch == '\r':
    result.add("(CR)")
  elif evt.ch == ' ':
    result.add("(SP)")
  elif evt.scanCode == 0x48:
    result.add("(UP)")
  elif evt.scanCode == 0x50:
    result.add("(DOWN)")
  elif evt.scanCode == 0x4b:
    result.add("(LEFT)")
  elif evt.scanCode == 0x4d:
    result.add("(RIGHT)")
  else:
    result.add("('" & $evt.ch & "')")
  result.add(&" scanCode={evt.scanCode:0>2x}h")
  if evt.shift: result.add(" shift")
  if evt.ctrl: result.add(" ctrl")
  if evt.alt: result.add(" alt")

proc kbdInterruptHandler*(intFrame: ptr InterruptFrame)
    {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".}=

  var scanCode = portIn8(0x60)
  # logger.info &"scanCode = {scanCode:0>2x}h"

  if (scanCode and 0x80) == 0:
    # key press down
    case scanCode
      of 0x2a, 0x36: shift = true
      of 0x1d: ctrl = true
      of 0x38: alt = true
      else:
        var ch: char = '\0'
        if shift and scanCode < kbdUsShift.len:
          ch = kbdUsShift[scanCode]
        elif scanCode < kbdUs.len:
          ch = kbdUs[scanCode]
        let keyEvent = KeyEvent(
          eventType: KeyDown, ch: ch, scanCode: scanCode,
          shift: shift, ctrl: ctrl, alt: alt
        )
        # logger.info "keyEvent = ", $keyEvent
        discard channels.send(kbdChId, keyEvent)
  else:
    # key release
    scanCode = scanCode and (not 0x80'u8)
    case scanCode
      of 0x2a, 0x36: shift = false
      of 0x1d: ctrl = false
      of 0x38: alt = false
      else:
        var ch: char = '\0'
        if shift and scanCode < kbdUsShift.len:
          ch = kbdUsShift[scanCode]
        elif scanCode < kbdUs.len:
          ch = kbdUs[scanCode]
        let keyEvent = KeyEvent(
          eventType: KeyUp, ch: ch, scanCode: scanCode,
          shift: shift, ctrl: ctrl, alt: alt
        )
        # logger.info "keyEvent = ", $keyEvent
        # discard channels.send(kbdChId, keyEvent)

  lapic.eoi()

proc kbdInit*(): int =
  ## Initialize the keyboard driver and return the channel id for key events.

  # create a channel to send key events
  kbdChId = channels.createKernelChannel[KeyEvent](mode = ChannelMode.Write)
  logger.info &"created keyboard channel id = {kbdChId} for key events"

  # install the keyboard interrupt handler: interrupt input 1 => vector 21h
  idt.installHandler(KbdInterruptVector, kbdInterruptHandler)
  ioapic.setRedirEntry(irq = 1, vector = KbdInterruptVector)
  logger.info &"installed keyboard interrupt handler ({KbdInterruptVector:0>2x}h)"

  result = kbdChId
