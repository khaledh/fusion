#[
    Console support for kernel messages
]#

import common/serde
import channels
import framebuffer as fb
import font
import sched
import drivers/kbd

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
  curFont = dina15x7

# Forward declarations
proc putChar*(row, col: int, c: char, color: uint32 = ForegroundColor)

proc moveTo*(x, y: int) =
  curCol = x
  curRow = y

proc nextLine*() =
  curCol = 0
  curRow += 1
  if curRow >= maxRows:
    curRow = 0  # TODO: scroll up

proc nextCol*() =
  curCol += 1
  if curCol >= maxCols:
    nextLine()

proc backspace*() =
  if curCol > 0:
    dec curCol
  elif curRow > 0:
    dec curRow
    curCol = maxCols - 1
  putChar(curRow, curCol, ' ', BackgroundColor)

proc cur2px*(row, col: int): (int, int) =
  (leftPadding + col * curFont.width, topPadding + row * curFont.height)

proc putChar*(row, col: int, c: char, color: uint32 = ForegroundColor) =
  let (x, y) = cur2px(row, col)  
  let glyph = getGlyph(curFont, c)
  for i in 0 ..< curFont.height:
    for j in 0 ..< curFont.width:
      if (glyph[i] shr (8 - j - 1) and 1) == 1:
        fb.putPixel(x + j, y + i, color)
      else:
        fb.putPixel(x + j, y + i, BackgroundColor)

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

proc keyEventHandler(keyEvent: KeyEvent) =
  # logger.info &"received keyEvent: {keyEvent}"
  if keyEvent.eventType == KeyDown:
    case keyEvent.ch
      of '\t': moveTo(curCol + 4, curRow)
      of '\n': nextLine()
      of '\b': backspace()
      else:
        putChar(curRow, curCol, keyEvent.ch, ForegroundColor)
        nextCol()

proc start*(chid: int) {.cdecl.} =
  ## Start the console task and wait for messages from the channel.

  # initialize the framebuffer
  logger.info "init framebuffer"
  fb.init()
  fb.clear(BackgroundColor)
  maxCols = (fb.getWidth() - leftPadding - rightPadding) div curFont.width
  maxRows = (fb.getHeight() - topPadding - bottomPadding) div curFont.height
  logger.info &"console size: {maxCols} x {maxRows}"

  # initialize the keyboard
  logger.info "init keyboard"
  kbd.kbdInit(keyEventHandler)

  # create a channel to receive messages for display
  let cid = channels.create[FString](getCurrentTask(), mode = ChannelMode.Read)
  logger.info &"console channel id: {cid}"

  while true:
    let msgOpt = channels.recv[FString](cid)
    if msgOpt.isSome:
      write(msgOpt.get)
    else:
      logger.info &"received `none` from channel {cid}"
