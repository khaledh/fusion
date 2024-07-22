#[
  Stopwatch for measuring elapsed time in the kernel.

  Implementation notes:
    - Uses getCurrentTicks from lapic module to get the current TSC ticks
    - The stopwatch can be in one of three states: Idle, Running, Stopped
    - The `split` method returns the elapsed time since the last split
    - The {.cast(uncheckedAssign).} pragma is needed to assign to the state field
]#

import lapic

type
  StopwatchState = enum
    Idle, Running, Stopped

  Stopwatch* = object
    case state: StopwatchState
    of Idle: discard
    of Running, Stopped:
      startTicks: uint64
      lastTicks: uint64

proc newStopwatch*(): Stopwatch =
  Stopwatch(state: Idle)

proc start*(s: var Stopwatch) =
  ## Starts the stopwatch
  case s.state
  of Idle:
    let currentTicks = getCurrentTicks()
    {.cast(uncheckedAssign).}:
      s.state = Running
      s.startTicks = currentTicks
      s.lastTicks = currentTicks
  else: discard

proc split*(s: var Stopwatch): uint64 =
  ## Returns the elapsed time since the last split
  case s.state
  of Running:
    let currentTicks = getCurrentTicks()
    let elapsedTicks = currentTicks - s.lastTicks
    s.lastTicks = currentTicks
    elapsedTicks
  else: 0

proc stop*(s: var Stopwatch) =
  ## Stops the stopwatch
  case s.state
  of Running:
    let currentTicks = getCurrentTicks()
    {.cast(uncheckedAssign).}:
      s.state = Stopped
      s.lastTicks = currentTicks
  else: discard

proc reset*(s: var Stopwatch) =
  ## Resets the stopwatch and returns it to the idle state
  {.cast(uncheckedAssign).}:
    s.state = Idle

proc elapsed*(s: Stopwatch): uint64 =
  ## Returns the elapsed time since the stopwatch was started
  case s.state
  of Running: getCurrentTicks() - s.startTicks
  of Stopped: s.lastTicks - s.startTicks
  else: 0
