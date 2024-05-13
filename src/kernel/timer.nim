#[
  Timer interrupt handler
]#

import idt
import lapic
import sched

const
  TimerVector = 0x20

proc timerHandler*(frame: ptr InterruptFrame)
  {. cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#" .} =
  # ack the interrupt
  lapic.eoi()

  # debug "."
  schedule()

proc timerInit*() =
  idt.installHandler(TimerVector, timerHandler)
  lapic.setTimer(TimerVector)
