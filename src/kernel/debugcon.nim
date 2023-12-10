import ports

const DebugConPort = 0xe9

proc debug*(msgs: varargs[string]) =
  for msg in msgs:
    for ch in msg:
      portOut8(DebugConPort, ch.uint8)

proc debugln*(msgs: varargs[string]) =
  debug(msgs)
  debug("\r\n")
