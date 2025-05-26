#[
    Console support for kernel messages
]#

import common/serde
import channels
import framebuffer as fb
import font

let
  logger = DebugLogger(name: "console")

const
  BackgroundColor = 0x2C3E50  # Dark Blue
  ForegroundColor = 0xECF0F1  # Light Gray

var
  maxCols, maxRows = 0
  curRow, curCol = 0  # cursor position
  leftPadding, rightPadding = 6
  topPadding, bottomPadding = 6
  curFont = dina13x7

proc moveCursor*(x, y: int) =
  curCol = x
  curRow = y

proc cur2px*(row, col: int): (int, int) =
  (leftPadding + col * curFont.width, topPadding + row * curFont.height)

proc putChar*(row, col: int, c: char, color: uint32 = ForegroundColor) =
  let (x, y) = cur2px(row, col)
  let glyph = getGlyph(curFont, c)
  for i in 0 ..< curFont.height:
    for j in 0 ..< curFont.width:
      if (glyph[i] shr (8 - j - 1) and 1) == 1:
        fb.putPixel(x + j, y + i, color)

proc putString*(row, col: int, s: string, color: uint32 = ForegroundColor): (int, int) =
  var (r, c) = (row, col)
  for i in 0 ..< s.len:
    if s[i] == '\n':
      r += 1
      c = 0
    else:
      putChar(r, c, s[i], color)
      c += 1
  (r, c)

proc write*(s: string, color: uint32 = ForegroundColor) =
  (curRow, curCol) = putString(curRow, curCol, s, color)

proc start*(chid: int) {.cdecl.} =
  ## Start the console task and wait for messages from the channel.
  logger.info &"starting console task with chid: {chid}"
  fb.init()
  fb.clear(BackgroundColor)
  maxCols = (fb.getWidth() - leftPadding - rightPadding) div curFont.width
  maxRows = (fb.getHeight() - topPadding - bottomPadding) div curFont.height
  logger.info &"console size: {maxCols} x {maxRows}"

  while true:
    let msg = channels.recv(chid)
    let data = deserialize(cast[ptr PackedObj](msg.data))
    logger.info &"Received message of length: {data.len}"
    if data.len > 0:
      write(data)
