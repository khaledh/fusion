#[
  Timer interrupt handler
]#

import idt
import lapic
import sched

const
  TimerVector = 0x20
  TimerDurationMs = 5  # 5ms

type
  TimerCallback* = proc ()

var
  callbacks: seq[TimerCallback]

proc registerCallback*(callback: TimerCallback) =
  callbacks.add(callback)

proc timerHandler*(frame: ptr InterruptFrame)
  {. cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#" .} =
  # ack the interrupt
  lapic.eoi()

  # debugln "timer"
  # debug "."
  for callback in callbacks:
    callback()

  schedule()

proc timerInit*() =
  idt.installHandler(TimerVector, timerHandler)
  lapic.setTimer(TimerVector, TimerDurationMs)
