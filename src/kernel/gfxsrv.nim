#[
  Graphics server
]#

import drivers/bga
import taskmgr

let
  logger = DebugLogger(name: "gfxsrv")

const
  XRes = 1400  # or 1600
  YRes = 1050  #    1200

  DefaultBackground = 0x608aaf'u32

var
  fb: ptr UncheckedArray[uint32]

proc start*()  {.cdecl.} =
  logger.info "starting graphics server"

  bga.setResolution(XRes, YRes)
  fb = bga.getFramebuffer()

  # clear the framebuffer
  for i in 0 ..< YRes.uint32 * Xres.uint32:
    fb[i] = DefaultBackground

  # suspend ourselves for now
  suspend()
