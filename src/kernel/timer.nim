import idt
import lapic

const
  TimerVector = 0x20

proc timerHandler*(intFrame: pointer)
  {. cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#" .} =

  lapic.eoi()
  debug "."

proc timerInit*() =
  idt.installHandler(TimerVector, timerHandler)
  lapic.setTimer(TimerVector)
