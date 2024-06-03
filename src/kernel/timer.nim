#[
  Timer interrupt handler
]#

import cpu
import idt
import lapic
import sched

const
  TimerVector = 0x20
  TimerDurationMs = 10  # milliseconds

type
  TimerCallback* = proc () {.cdecl.}

let
  logger = DebugLogger(name: "timer")

var
  callbacks: array[16, TimerCallback]
  callbacksNextIdx = 0
  lastTickOnEntry: uint64
  currTickOnEntry: uint64
  sliceTicksRemaining: uint64

proc registerCallback*(callback: TimerCallback) =
  if callbacksNextIdx >= callbacks.high:
    raise newException(CatchableError, "Too many timer callbacks")

  callbacks[callbacksNextIdx] = callback
  inc callbacksNextIdx

proc timerHandler*(frame: ptr InterruptFrame)
  {. cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#", stackTrace:off .} =

  currTickOnEntry = cpu.readTSC()
  # let currTickOnEntry2 = cpu.readTSC()

  # let ticksBeforeEoiAck = cpu.readTSC()
  # logger.info &"[tid:{tid}] <- ticks before eoi ack {grouped(ticksBeforeEoiAck)}"
  # ack the interrupt
  lapic.eoi()
  # let ticksAfterEoiAck = cpu.readTSC()
  # logger.info &"[tid:{tid}] <- ticks after eoi ack {grouped(ticksAfterEoiAck)} (took {grouped(ticksAfterEoiAck - ticksBeforeEoiAck)} ticks)"

  # let tid = getCurrentTask().id
  # logger.info &"[tid:{tid}] -> ticks after entry {grouped(currTickOnEntry)}"
  # logger.info &"[tid:{tid}] -> ticks after entry {grouped(currTickOnEntry2)}"

  # let currTickOnEntry3 = cpu.readTSC()
  # let currTickOnEntry4 = cpu.readTSC()
  # logger.info &"[tid:{tid}] -> ticks after entry {grouped(currTickOnEntry3)}"
  # logger.info &"[tid:{tid}] -> ticks after entry {grouped(currTickOnEntry4)}"

  # let currTickOnEntry5 = cpu.readTSC()
  # logger.info &"[tid:{tid}] -> ticks after entry {grouped(currTickOnEntry5)}"
  # let currTickOnEntry6 = cpu.readTSC()
  # logger.info &"[tid:{tid}] -> ticks after entry {grouped(currTickOnEntry6)}"

  # if lastTickOnEntry > 0:
  #   # calculate the time since the last tick
  #   let elapsedTicks = currTickOnEntry - lastTickOnEntry
  #   let elapsedMs = ticksToDuration(elapsedTicks)
  #   logger.info &"[tid:{tid}] -> elapsed ticks: {grouped(elapsedTicks)}, elapsed time: {elapsedMs} ms"

  # lastTickOnEntry = currTickOnEntry

  # debugln "timer"
  # debug "."
  # for i in 0 ..< callbacksNextIdx:
  #   # let beforeCallbackTicks = cpu.readTSC()
  #   # logger.info &"[tid:{tid}] -> calling callback at {grouped(beforeCallbackTicks)}"
  #   callbacks[i]()
  #   # let afterCallbackTicks = cpu.readTSC()
  #   # logger.info &"[tid:{tid}] -> returned from callback {i} at {grouped(afterCallbackTicks)}"
  callbacks[0]()
  schedule()

  # let processingElapsedTicks = cpu.readTSC() - currTickOnEntry
  # let processingMs = ticksToDuration(processingElapsedTicks)
  # logger.info &"[tid:{tid}] <- processing ticks {grouped(processingElapsedTicks)}, processing ms: {processingMs}"


proc timerInit*() =
  idt.installHandler(TimerVector, timerHandler)
  lapic.setTimer(TimerVector, TimerDurationMs)
