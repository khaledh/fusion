#[
  Graphics server
]#

import drivers/bga
import taskmgr

{.experimental: "codeReordering".}

let
  logger = DebugLogger(name: "gfxsrv")

const
  XRes = 1400  # or 1600
  YRes = 1050  #    1200

  DefaultBackground = 0x608aaf'u32

var
  fb: ptr UncheckedArray[uint32]
  buffer0: ptr UncheckedArray[uint32]
  buffer1: ptr UncheckedArray[uint32]
  backBuffer: ptr UncheckedArray[uint32]

proc start*()  {.cdecl.} =
  logger.info "starting graphics server"

  bga.setResolution(XRes, YRes)
  fb = bga.getFramebuffer()

  buffer0 = fb
  buffer1 = fb +! uint64(XRes * YRes * 4)
  backBuffer = buffer1

  # set the back buffer to the default background color
  for i in 0 ..< YRes.uint32 * Xres.uint32:
    backBuffer[i] = DefaultBackground

  swapBuffers()

  # suspend ourselves for now
  suspend()

proc swapBuffers*() =
  if backBuffer == buffer0:
    bgaSetYOffset(0)
    backBuffer = buffer1
    copyMem(buffer1, buffer0, XRes * YRes * 4)
  else:
    bgaSetYOffset(YRes)
    backBuffer = buffer0
    copyMem(buffer0, buffer1, XRes * YRes * 4)
