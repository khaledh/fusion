#[
  Stopwatch for measuring elapsed time in the kernel.

  Implementation notes:
    - Uses getCurrentTicks from lapic module to get the current TSC ticks
    - Uses a typestate pattern to ensure the correct usage of the stopwatch
    - The stopwatch can be in one of three states: Idle, Running, Stopped
    - State machine:
        <init>: Idle

        Idle    --start-->   Running

        Running --split-->   Running
        Running --stop-->    Stopped

        Stopped --reset-->   Idle
]#

import lapic

type
  StopwatchState* = enum
    Idle, Running, Stopped

  Stopwatch*[State: static StopwatchState] = object
    case state: StopwatchState
    of Idle: discard
    of Running, Stopped:
      startTicks: uint64
      lastTicks: uint64

proc newStopwatch*(): Stopwatch[Idle] =
  Stopwatch[Idle](state: Idle)

proc start*(s: Stopwatch[Idle]): Stopwatch[Running] =
  ## Starts the stopwatch
  let currentTicks = getCurrentTicks()
  Stopwatch[Running](
    state: Running,
    startTicks: currentTicks,
    lastTicks: currentTicks,
  )

proc split*(s: var Stopwatch[Running]): uint64 =
  ## Returns the elapsed time since the last split
  let currentTicks = getCurrentTicks()
  let elapsedTicks = currentTicks - s.lastTicks
  s.lastTicks = currentTicks
  return elapsedTicks

proc stop*(s: Stopwatch[Running]): Stopwatch[Stopped] =
  ## Stops the stopwatch
  let currentTicks = getCurrentTicks()
  Stopwatch[Stopped](
    state: Stopped,
    startTicks: s.startTicks,
    lastTicks: currentTicks,
  )

proc reset*(s: Stopwatch[Stopped]): Stopwatch[Idle] =
  ## Resets the stopwatch and returns it to the idle state
  newStopwatch()

proc elapsed*(s: Stopwatch[Running]): uint64 =
  ## Returns the elapsed time since the stopwatch was started
  return getCurrentTicks() - s.startTicks

proc elapsed*(s: Stopwatch[Stopped]): uint64 =
  ## Returns the elapsed ticks between the start and stop ticks
  return s.lastTicks - s.startTicks
