import cpu

type
  IA32ApicBaseMsr {.packed.} = object
    reserved1   {.bitsize:  8.}: uint64
    isBsp       {.bitsize:  1.}: uint64
    reserved2   {.bitsize:  2.}: uint64
    enabled     {.bitsize:  1.}: uint64
    baseAddress {.bitsize: 24.}: uint64
    reserved3   {.bitsize: 28.}: uint64

  LapicOffset = enum
    LapicId            = 0x020
    LapicVersion       = 0x030
    TaskPriority       = 0x080
    ProcessorPriority  = 0x0a0
    Eoi                = 0x0b0
    LogicalDestination = 0x0d0
    DestinationFormat  = 0x0e0
    SpuriousInterrupt  = 0x0f0
    InService          = 0x100
    TriggerMode        = 0x180
    InterruptRequest   = 0x200
    ErrorStatus        = 0x280
    LvtCmci            = 0x2f0
    InterruptCommandLo = 0x300
    InterruptCommandHi = 0x310
    LvtTimer           = 0x320
    LvtThermalSensor   = 0x330
    LvtPerfMonCounters = 0x340
    LvtLint0           = 0x350
    LvtLint1           = 0x360
    LvtError           = 0x370
    TimerInitialCount  = 0x380
    TimerCurrentCount  = 0x390
    TimerDivideConfig  = 0x3e0

var
  baseAddress: uint64

proc getBasePhysAddr*(): uint32 =
  let baseMsr = cast[Ia32ApicBaseMsr](readMSR(IA32_APIC_BASE))
  result = (baseMsr.baseAddress shl 12).uint32

proc lapicInit*(baseAddr: uint64) =
  baseAddress = baseAddr

proc writeRegister(offset: int, value: uint32) =
  cast[ptr uint32](baseAddress + offset.uint16)[] = value

template writeRegister(offset: LapicOffset, value: uint32) =
  writeRegister(offset.int, value)

proc eoi*() =
  ## End of Interrupt
  writeRegister(LapicOffset.Eoi, 0)


#############
# APIC Timer
#############

type
  LvtTimerDivisor* {.size: 4.} = enum
    DivideBy2   = 0b0000
    DivideBy4   = 0b0001
    DivideBy8   = 0b0010
    DivideBy16  = 0b0011
    DivideBy32  = 0b1000
    DivideBy64  = 0b1001
    DivideBy128 = 0b1010
    DivideBy1   = 0b1011

const
  InitialCount = 500_000

proc setTimer*(vector: uint8) =
  writeRegister(LapicOffset.TimerDivideConfig, DivideBy16.uint32)
  writeRegister(LapicOffset.TimerInitialCount, InitialCount)
  writeRegister(LapicOffset.LvtTimer, vector.uint32 or (1 shl 17))
