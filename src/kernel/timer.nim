#[
  Timer interrupt handler
]#

import idt
import lapic
import sched

const
  TimerVector = 0x20
  TimerDurationMs = 20  # milliseconds

proc timerHandler*(frame: ptr InterruptFrame)
  {. cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#" .} =
  # ack the interrupt
  lapic.eoi()

  # debugln "timer"
  # debug "."
  schedule()

proc timerInit*() =
  idt.installHandler(TimerVector, timerHandler)
  lapic.setTimer(TimerVector, TimerDurationMs)
