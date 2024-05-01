#[
  Timer interrupt handler
]#

import idt
import lapic
import sched

const
  TimerVector = 0x20

proc timerHandler*(intFrame: pointer)
  {. cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#" .} =

  lapic.eoi()
  schedule()

proc timerInit*() =
  idt.installHandler(TimerVector, timerHandler)
  lapic.setTimer(TimerVector)
