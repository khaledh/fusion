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
  SysChannelSend* = 301
  SysChannelRecv* = 302
