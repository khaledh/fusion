#[
    Console support for kernel messages
]#

import framebuffer as fb
import font

let
  logger = DebugLogger(name: "console")

const
  BackgroundColor = 0x2C3E50  # Dark Blue
  ForegroundColor = 0xECF0F1  # Light Gray

var
  maxCols, maxRows = 0
  row, col = 0  # cursor position
  leftPadding, rightPadding = 6
  topPadding, bottomPadding = 6

proc moveCursor*(x, y: int) =
  col = x
  row = y

proc cur2pix*(x, y: int): (int, int) =
  (leftPadding + x * FontWidth, topPadding + y * FontHeight)

proc putChar*(x, y: int, c: char, color: uint32 = ForegroundColor) =
  let glyph = getGlyph(c)
  for i in 0 ..< FontHeight:
    for j in 0 ..< FontWidth:
      # test bit j of glyph[i] starting the most significant bit
      if (glyph[i] and (1.uint8 shl (FontWidth - j - 1))) != 0:
        fb.putPixel(x + j, y + i, color)


proc putString*(x, y: int, s: string, color: uint32 = ForegroundColor): (int, int) =
  for i in 0 ..< s.len:
    putChar(x + i * FontWidth, y, s[i], color)
  (x + s.len * FontWidth, y)

proc write*(s: string, color: uint32 = ForegroundColor) =
  let (x, y) = cur2pix(col, row)
  (col, row) = putString(x, y, s, color)

proc init*() =
  fb.init()
  fb.clear(BackgroundColor)
  maxCols = (fb.getWidth() - leftPadding - rightPadding) div FontWidth
  maxRows = (fb.getHeight() - topPadding - bottomPadding) div FontHeight
  logger.info &"console size: {maxCols} x {maxRows}"
