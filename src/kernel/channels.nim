import std/tables

import debugcon
import queues

type
  Message* = object
    data*: int

  Channel* = ref object
    id*: int
    queue: BlockingQueue[Message]

const
  MaxChannelSize = 256

var
  channels = initTable[int, Channel]()
  nextChannelId = 0

proc newChannel*(): Channel =
  result = Channel(
    id: nextChannelId,
    queue: newBlockingQueue[Message](MaxChannelSize)
  )
  channels[result.id] = result

proc send*(chid: int, data: int) {.stackTrace:off.} =
  if not channels.hasKey(chid):
    debugln &"recv: channel id {chid} not found"
    return

  channels[chid].queue.enqueue(Message(data: data))

proc recv*(chid: int): int {.stackTrace:off.} =
  if not channels.hasKey(chid):
    debugln &"recv: channel id {chid} not found"
    return -1

  result = channels[chid].queue.dequeue().data
  debugln &"recv: dequeued {result}"