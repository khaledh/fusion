#[
  Graphics server
]#

import drivers/bga
import taskmgr

let
  logger = DebugLogger(name: "gfxsrv")

const
  XRes = 1400
  YRes = 1050

proc start*()  {.cdecl.} =
  logger.info "starting graphics server"

  bga.setResolution(XRes, YRes)

  # suspend ourselves for now
  suspend()
