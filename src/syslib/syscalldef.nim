#[
  System call definitions
]#

const
  # OS
  SysGetTaskId* = 101
  SysYield* = 102
  SysSuspend* = 103
  SysSleep* = 104
  SysExit* = 105

  # I/O
  SysPrint* = 201

  # Channels
  SysChannelCreate* = 300
  SysChannelOpen* = 301
  SysChannelClose* = 302
  SysChannelSend* = 303
  SysChannelSendBatch* = 304
  SysChannelRecv* = 305
  SysChannelRecvBatch* = 306
  SysChannelAlloc* = 307
  SysChannelAllocBatch* = 308

type
  Message* = object
    len*: int
    data*: pointer

  MessageBatch* {.packed.} = object
    count*: int
    messages*: UncheckedArray[Message]
