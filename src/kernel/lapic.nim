#[
  x86_64 Local APIC
]#

import std/algorithm

import common/pagetables
import cpu
import idt
import pit
import util
import vmm

type
  IA32ApicBaseMsr {.packed.} = object
    reserved1   {.bitsize:  8.}: uint64
    isBsp       {.bitsize:  1.}: uint64  # Is Bootstrap Processor?
    reserved2   {.bitsize:  2.}: uint64
    enabled     {.bitsize:  1.}: uint64  # APIC Enabled?
    baseAddress {.bitsize: 24.}: uint64  # Physical Base Address (bits 12-35)
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

  SpuriousInterruptVectorRegister {.packed.} = object
    vector                  {.bitsize:  8.}: uint32
    apicEnabled             {.bitsize:  1.}: uint32
    focusProcessorChecking  {.bitsize:  1.}: uint32
    reserved0               {.bitsize:  2.}: uint32
    eoiBroadcastSuppression {.bitsize:  1.}: uint32
    reserved1               {.bitsize: 19.}: uint32

let
  logger = DebugLogger(name: "lapic")

var
  apicBaseAddress: uint64

proc initBaseAddress() =
  let apicBaseMsr = cast[IA32ApicBaseMsr](readMSR(IA32_APIC_BASE))
  let apicPhysAddr = (apicBaseMsr.baseAddress shl 12).PAddr
  # by definition, apicPhysAddr is aligned to a page boundary, so we map it directly
  let apicVMRegion = vmalloc(kspace, 1)
  mapRegion(
    pml4 = kpml4,
    virtAddr = apicVMRegion.start,
    physAddr = apicPhysAddr,
    pageCount = 1,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
    noExec = true
  )
  apicBaseAddress = apicVMRegion.start.uint64

proc readRegister(offset: LapicOffset): uint32 {.inline.} =
  result = cast[ptr uint32](apicBaseAddress + offset.uint16)[]

proc writeRegister(offset: LapicOffset, value: uint32) {.inline.} =
  cast[ptr uint32](apicBaseAddress + offset.uint16)[] = value

proc eoi*() {.inline.} =
  ## End of Interrupt
  writeRegister(LapicOffset.Eoi, 0)

proc spuriousInterruptHandler*(frame: ptr InterruptFrame)
  {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
  # Ignore spurious interrupts and don't send an EOI
  return

proc lapicInit*() =
  initBaseAddress()
  # enable APIC and install spurious interrupt handler
  let sivr = SpuriousInterruptVectorRegister(vector: 0xff, apicEnabled: 1)
  writeRegister(LapicOffset.SpuriousInterrupt, cast[uint32](sivr))
  # install spurious interrupt handler
  installHandler(0xff, spuriousInterruptHandler)

#############
# APIC Timer
#############

type
  LvtTimerRegister {.packed.} = object
    vector         {.bitsize:  8.}: uint8
    reserved0      {.bitsize:  4.}: uint8
    deliveryStatus {.bitsize:  1.}: DeliveryStatus
    reserved1      {.bitsize:  3.}: uint8
    mask           {.bitsize:  1.}: InterruptMask
    mode           {.bitsize:  2.}: TimerMode
    reserved2      {.bitsize: 13.}: uint16

  TimerMode = enum
    OneShot     = 0b00
    Periodic    = 0b01
    TscDeadline = 0b10

  InterruptMask = enum
    NotMasked   = 0
    Masked      = 1
  
  DeliveryStatus = enum
    Idle        = 0
    SendPending = 1
  
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
  let lvtTimer = LvtTimerRegister(mode: TimerMode.OneShot)
  writeRegister(LapicOffset.LvtTimer, cast[uint32](lvtTimer))
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
  logger.info "calibrating tsc and apic timer frequency"

  var timerFreqs: array[5, uint32]
  var tscFreqs: array[5, uint64]
  for i in 0 ..< timerFreqs.len:
    (timerFreqs[i], tscFreqs[i]) = calcFrequency()

  # discard lowest and highest values
  sort(timerFreqs)
  timerFreq = (timerFreqs[1] + timerFreqs[2] + timerFreqs[3]) div 3
  let timerFreqRounded = roundWithTolerance(timerFreq, 100) # 1% tolerance
  logger.info &"  timer frequency: {timerFreqRounded div 1000_000} MHz (measured: {timerFreq} Hz)"

  sort(tscFreqs)
  tscFreq = (tscFreqs[1] + tscFreqs[2] + tscFreqs[3]) div 3
  let tscFreqRounded = roundWithTolerance(tscFreq, 100) # 1% tolerance
  logger.info &"  tsc frequency:   {tscFreqRounded div 1000_000} MHz (measured: {tscFreq} Hz)"

  logger.info &"  setting apic timer interval to {durationMs} ms (vector {vector:#x})"
  let initialCount = uint32((timerFreq * durationMs) div (1000 * TimerDivisor))

  let lvtTimer = LvtTimerRegister(
    vector: vector,
    mask: InterruptMask.NotMasked,
    mode: TimerMode.Periodic,
  )
  writeRegister(LapicOffset.LvtTimer, cast[uint32](lvtTimer))
  writeRegister(LapicOffset.TimerDivideConfig, TimerDivideBy.uint32)
  writeRegister(LapicOffset.TimerInitialCount, initialCount)
