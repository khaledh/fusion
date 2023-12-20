import ports

const DebugConPort = 0xe9

proc debug*(msgs: varargs[string]) =
  ## Send debug messages to the debug console port.
  for msg in msgs:
    for ch in msg:
      portOut8(DebugConPort, ch.uint8)

proc debugln*(msgs: varargs[string]) =
  ## Send debug messages to the debug console port. A newline is appended at the end.
  debug(msgs)
  debug("\r\n")
