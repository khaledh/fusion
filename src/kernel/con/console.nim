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

type
  Console = object
    outChId: int       ## User channel for writing to console output
    inChId: int        ## User channel for reading from console input
    kbdInChId: int     ## Kernel channel for receiving key events from keyboard driver
    lineBuffer: string

const
  BackgroundColor = 0x2C3E50  # Dark Blue
  ForegroundColor = 0xECF0F1  # Light Gray
  TabWidth = 4

var
  con: Console
  maxCols, maxRows = 0
  curRow, curCol = 0  # cursor position
  leftPadding, rightPadding = 6
  topPadding, bottomPadding = 6
  curFont = dina15x7

# Forward declarations
proc hideCursor()
proc showCursor()
proc putChar*(row, col: int, c: char, color: uint32 = ForegroundColor)

proc nextLine*() {.inline.} =
  if curRow < maxRows - 1:
    inc curRow
    curCol = 0
  # TODO: scroll up

proc nextCol*() {.inline.} =
  inc curCol
  if curCol >= maxCols:
    nextLine()

proc prevCol*() {.inline.} =
  if curCol > 0:
    dec curCol

proc nextTab*() =
  # round up to the next multiple of TabWidth
  let curTabOffset = curCol mod TabWidth
  curCol = curCol + TabWidth - curTabOffset

proc cur2px*(row, col: int): (int, int) =
  (leftPadding + col * curFont.width, topPadding + row * curFont.height)

proc drawCursor(row, col: int, color: uint32) =
  let (x, y) = cur2px(row, col)
  for i in 0 ..< curFont.height - 2:
    for j in 0 ..< curFont.width:
      fb.putPixel(x + j, y + i, color)
  for i in curFont.height - 2 ..< curFont.height:
    for j in 0 ..< curFont.width:
      fb.putPixel(x + j, y + i, BackgroundColor)

proc hideCursor() =
  drawCursor(curRow, curCol, BackgroundColor)

proc showCursor() =
  drawCursor(curRow, curCol, ForegroundColor)

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
  hideCursor()
  (curRow, curCol) = putString(curRow, curCol, s, color)
  showCursor()

proc outEventHandler(fs: FString) =
  write($fs.str)

proc keyEventHandler(keyEvent: KeyEvent) =
  # logger.info &"received keyEvent: {keyEvent}"
  if keyEvent.eventType == KeyDown:
    case keyEvent.ch
      of '\b':
        if con.lineBuffer.len > 0:
          hideCursor()
          prevCol()
          con.lineBuffer.setLen(con.lineBuffer.len - 1)
          showCursor()
      of '\t':
        hideCursor()
        nextTab()
        con.lineBuffer.add("\t")
        showCursor() 
      of '\n':
        hideCursor()
        nextLine()
        discard channels.send(con.inChId, con.lineBuffer)
        con.lineBuffer = ""
        showCursor()
      else:
        putChar(curRow, curCol, keyEvent.ch)
        con.lineBuffer.add(keyEvent.ch)
        nextCol()
        showCursor()

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
  let kbdChId = kbd.kbdInit()

  # create a channel to receive messages for display
  let conTaskId = getCurrentTask()
  con = Console(
    outChId: channels.createUserChannel[FString](conTaskId, mode = ChannelMode.Read),
    inChId: channels.createUserChannel[FString](conTaskId, mode = ChannelMode.Write),
    kbdInChId: channels.openKernelChannel(getCurrentTask(), kbdChId, mode = ChannelMode.Read),
  )
  logger.info &"  user output channel id: {con.outChId}"
  logger.info &"  user input channel id: {con.inChId}"
  logger.info &"  kernel keyboard input channel id: {con.kbdInChId}"

  showCursor()

  let keyCh: MessageHandler[KeyEvent] = (id: con.kbdInChId, handler: keyEventHandler)
  let outCh: MessageHandler[FString] = (id: con.outChId, handler: outEventHandler)
  while true:
    discard channels.recvAny(keyCh, outCh)
