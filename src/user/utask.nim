#[
  This is an example of a user task.
]#
import std/strformat

import common/[debugcon]
import syslib/[channels, os]

const
  ConsoleChannelId = 0

proc main(param: int): int {.exportc.} =
  let tid = os.getTaskId()

  let ch = channels.open[string](cid = ConsoleChannelId, mode = ChannelMode.Write)
  defer: ch.close()

  if ch.id < 0:
    debugln "Failed to open console channel"
    return 1

  ch.send(&"Hello from task {tid}\n")

  return 0
