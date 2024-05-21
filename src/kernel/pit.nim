import ports

type
  ReadBackCommand {.packed, size: 1.} = object
    reserved {.bitsize: 1.} = 0
    channel0 {.bitsize: 1.} = 0
    channel1 {.bitsize: 1.} = 0
    channel2 {.bitsize: 1.} = 0
    latchStatus {.bitsize: 1.} = 1
    latchCount {.bitsize: 1.} = 1
    alwaysOnes {.bitsize: 2.} = 0b11

  StatusByte* {.packed, size: 1.} = object
    bcdMode* {.bitsize: 1.} = 0
    operatingMode* {.bitsize: 3.} = 0
    accessMode* {.bitsize: 2.} = 0
    nullCount* {.bitsize: 1.} = 0
    outputPinState* {.bitsize: 1.} = 0

const
  PitFrequency* = 1_193_182  # Hz
  PortChannel0 = 0x40
  PortCommand = 0x43

  CmdChannel0   = 0b00_00_000_0  # (bits 7-6) channel 0
  CmdAccessLoHi = 0b00_11_000_0  # (bits 5-4) read/write lsb/msb
  CmdOpMode0    = 0b00_00_000_0  # (bits 3-1) mode 0 (interrupt on terminal count)
  CmdOpMode3    = 0b00_00_011_0  # (bits 3-1) mode 3 (square wave generator)
  CmdBinaryMode = 0b00_00_000_0  # (bit 0) binary counter (not BCD)

  ReadBackChannel0Status = ReadBackCommand(latchStatus: 0, channel0: 1)  # latchStatus is inverted bit

proc startOneShot*(divisor: uint16) =
  # send command (mode 3)
  portOut8(PortCommand, CmdChannel0 or CmdAccessLoHi or CmdOpMode0 or CmdBinaryMode)
  # send divisor
  portOut8(PortChannel0, uint8(divisor and 0xff))
  portOut8(PortChannel0, uint8((divisor shr 8) and 0xff))

# proc stop*() =
#   # send command (mode 0)
#   portOut8(PortCommand, CmdChannel0 or CmdAccessLoHi or CmdOpMode0 or CmdBinaryMode)
#   # send divisor
#   portOut8(PortChannel0, 0)
#   portOut8(PortChannel0, 0)

proc readCounter*(): uint16 =
  portOut8(PortCommand, CmdChannel0)
  result = portIn8(PortChannel0).uint16 or (portIn8(PortChannel0).uint16 shl 8)

proc readStatus*(): StatusByte =
  portOut8(PortCommand, cast[uint8](ReadBackChannel0Status))
  result = cast[StatusByte](portIn8(PortChannel0))
