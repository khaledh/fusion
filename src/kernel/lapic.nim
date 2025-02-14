#[
  x86_64 Local APIC
]#

import std/algorithm

import cpu
import pit

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

  TimerMode = enum
    OneShot     = 0b00 shl 17
    Periodic    = 0b01 shl 17
    TscDeadline = 0b10 shl 17

  InterruptMask = enum
    NotMasked = 0 shl 16
    Masked    = 1 shl 16
  
  DeliveryStatus = enum
    Idle        = 0 shl 12
    SendPending = 1 shl 12
  
  SpuriousInterruptVectorRegister {.packed.} = object
    vector: uint8
    apicEnabled {.bitsize: 1.}: uint8
    reserved0 {.bitsize: 7.}: uint8
    reserved1 : uint16

let
  logger = DebugLogger(name: "lapic")

const
  SpuriousInterruptVector = 0xff

var
  baseAddress: uint64

proc getBasePhysAddr*(): uint32 =
  let baseMsr = cast[Ia32ApicBaseMsr](readMSR(IA32_APIC_BASE))
  result = (baseMsr.baseAddress shl 12).uint32

proc readRegister(offset: int): uint32 {.inline.} =
  result = cast[ptr uint32](baseAddress + offset.uint16)[]

template readRegister(offset: LapicOffset): uint32 =
  readRegister(offset.int)

proc writeRegister(offset: int, value: uint32) {.inline.} =
  cast[ptr uint32](baseAddress + offset.uint16)[] = value

template writeRegister(offset: LapicOffset, value: uint32) =
  writeRegister(offset.int, value)

proc eoi*() {.inline.} =
  ## End of Interrupt
  writeRegister(LapicOffset.Eoi, 0)

proc lapicInit*(baseAddr: uint64) =
  baseAddress = baseAddr
  # enable APIC
  let svr = SpuriousInterruptVectorRegister(
    vector: SpuriousInterruptVector,
    apicEnabled: 1,
  )
  writeRegister(LapicOffset.SpuriousInterrupt, cast[uint32](svr))


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
  TimerDivideBy = DivideBy16
  TimerDivisor = 16

var
  timerFreq: uint64
  tscFreq: uint64

proc durationToTicks*(durationMs: uint64): uint64 {.inline.} =
  result = tscFreq * durationMs div 1000

proc ticksToDuration*(ticks: uint64): uint64 {.inline.} =
  result = ticks * 1000 div tscFreq

proc getCurrentTicks*(): uint64 {.inline.} =
  result = readTSC()

proc getFutureTicks*(durationMs: uint64): uint64 {.inline.} =
  result = getCurrentTicks() + durationToTicks(durationMs)


proc calcFrequency(): tuple[timerFreq: uint32, tscFreq: uint64] =
  # estimate the frequency using the PIT timer
  let pitInterval = 50  # ms
  let pitCount = uint16((PitFrequency div 1000) * pitInterval)

  # set the APIC timer to one-shot mode with max count
  writeRegister(LapicOffset.LvtTimer, TimerMode.OneShot.uint32)
  writeRegister(LapicOffset.TimerDivideConfig, TimerDivideBy.uint32)
  writeRegister(LapicOffset.TimerInitialCount, uint32.high)

  # read TSC
  let tscStart = cpu.readTsc()

  # start the PIT timer
  pit.startOneShot(divisor = pitCount)

  # wait for the PIT timer to expire
  while pit.readStatus().outputPinState == 0:
    discard

  # read the APIC timer count
  let apicEndCount = readRegister(LapicOffset.TimerCurrentCount)

  # read TSC
  let tscEnd = cpu.readTsc()

  let apicTickCount = uint32.high - apicEndCount
  let tscTickCount = tscEnd - tscStart

  # calculate the timer frequency
  let timerFreq = (apicTickCount div pitInterval.uint32) * 1000 * TimerDivisor
  # logger.info &"timer frequency: {timerFreq} Hz"

  # calculate TSC frequency
  let tscFreq = (tscTickCount div pitInterval.uint32) * 1000
  # logger.info &"core frequency: {tscFreq} Hz"

  result = (timerFreq, tscFreq)

proc setTimer*(vector: uint8, durationMs: uint32) =
  logger.info "calculating apic timer frequency"

  var timerFreqs: array[5, uint32]
  var tscFreqs: array[5, uint64]
  for i in 0 ..< timerFreqs.len:
    (timerFreqs[i], tscFreqs[i]) = calcFrequency()

  # discard lowest and highest values
  sort(timerFreqs)
  timerFreq = (timerFreqs[1] + timerFreqs[2] + timerFreqs[3]) div 3
  logger.info &"  ...apic timer frequency: {timerFreq} Hz"

  sort(tscFreqs)
  tscFreq = (tscFreqs[1] + tscFreqs[2] + tscFreqs[3]) div 3
  logger.info &"  ...tsc frequency: {tscFreq} Hz"

  logger.info &"  ...setting apic timer interval to {durationMs} ms (vector {vector:#x})"
  let initialCount = uint32((timerFreq * durationMs) div (1000 * TimerDivisor))

  writeRegister(LapicOffset.LvtTimer, vector.uint32 or TimerMode.Periodic.uint32)
  writeRegister(LapicOffset.TimerDivideConfig, TimerDivideBy.uint32)
  writeRegister(LapicOffset.TimerInitialCount, initialCount)
