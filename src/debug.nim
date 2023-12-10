import uefi
import ports

# var conOut: ptr SimpleTextOutput

# proc init*(outputInterface: ptr SimpleTextOutput) =
#   conOut = outputInterface

# proc printws*(wstr: WideCString) =
#   discard conOut.outputString(conOut, wstr[0].addr)

# proc print*(str: string) =
#   discard conOut.outputString(conOut, (newWideCString(str).toWideCString)[0].addr)

# proc println*(str: string) =
#   print(str & "\r\n")

proc debug*(msgs: varargs[string]) =
  for msg in msgs:
    for ch in msg:
      portOut8(0x402, ch.uint8)

proc debugln*(msgs: varargs[string]) =
  debug(msgs)
  debug("\r\n")
