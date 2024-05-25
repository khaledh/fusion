#[
  PIT - Programmable Interval Timer

  We use the PIT only to calibrate other timers, e.g. the APIC timer and the
  Timestamp Counter (TSC). It is not used for timekeeping or the timer interrupt.
]#

import ports

type
  SetCounterCommand {.packed, size: 1.} = object
    encoding {.bitsize: 1.}: Encoding
    operatingMode {.bitsize: 3.}: OperatingMode
    accessMode {.bitsize: 2.}: AccessMode
    counter {.bitsize: 2.}: Counter

  Encoding = enum
    Binary = 0
    Bcd = 1

  OperatingMode = enum
    Mode0 = 0  # interrupt on terminal count
    Mode1 = 1  # hardware retriggerable one-shot
    Mode2 = 2  # rate generator
    Mode3 = 3  # square wave generator
    Mode4 = 4  # software triggered strobe
    Mode5 = 5  # hardware triggered strobe

  AccessMode = enum
    Lsb = 1
    Msb = 2
    LsbMsb = 3

  Counter = enum
    Counter0 = 0
    Counter1 = 1
    Counter2 = 2

  ReadBackCommand {.packed, size: 1.} = object
    reserved {.bitsize: 1.} = 0
    counter0 {.bitsize: 1.}: uint8
    counter1 {.bitsize: 1.}: uint8
    counter2 {.bitsize: 1.}: uint8
    latchStatus {.bitsize: 1.}: uint8 = 1  # inverted logic
    latchCount {.bitsize: 1.}: uint8 = 1  # inverted logic
    alwaysOnes {.bitsize: 2.} = 0b11

  StatusByte* {.packed, size: 1.} = object
    encoding* {.bitsize: 1.}: Encoding
    operatingMode* {.bitsize: 3.}: OperatingMode
    accessMode* {.bitsize: 2.}: AccessMode
    nullCount* {.bitsize: 1.}: uint8
    outputPinState* {.bitsize: 1.}: uint8

const
  PitFrequency* = 1_193_182  # Hz
  PortCounter0 = 0x40
  PortCommand = 0x43

  SetCounter0OneShot = SetCounterCommand(
    encoding: Encoding.Binary,
    operatingMode: OperatingMode.Mode0,
    accessMode: AccessMode.LsbMsb,
    counter: Counter.Counter0,
  )
  ReadBackCounter0Status = ReadBackCommand(
    counter0: 1,
    latchStatus: 0,  # inverted logic
  )

proc startOneShot*(divisor: uint16) =
  ## One-shot keeps the output pin state high once the counter reaches zero.
  ## This allows us to test the output pin state in a loop to measure the
  ## time it takes for the counter to reach zero.
  ## 
  ## Note: We cannot rely on reading the count and checking if it is zero,
  ## because the counter will wrap around (even in one-shot mode) so it
  ## could be easily missed.

  # send command
  portOut8(PortCommand, cast[uint8](SetCounter0OneShot))

  # send divisor
  portOut8(PortCounter0, uint8(divisor and 0xff))
  portOut8(PortCounter0, uint8((divisor shr 8) and 0xff))

proc readStatus*(): StatusByte =
  # send read back command
  portOut8(PortCommand, cast[uint8](ReadBackCounter0Status))

  # read status byte
  result = cast[StatusByte](portIn8(PortCounter0))
