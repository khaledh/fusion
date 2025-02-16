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
  SysChannelOpen* = 301
  SysChannelClose* = 302
  SysChannelSend* = 303
  SysChannelRecv* = 304
  SysChannelAlloc* = 305
