#[
  Kernel startup
]#
import common/[bootinfo, libc, malloc]
import main

let logger = DebugLogger(name: "start")

proc NimMain() {.importc.}
proc unhandledException(e: ref Exception)

####################################################################################################
# Entry point
####################################################################################################

proc kstart(bootInfo: ptr BootInfo) {.exportc.} =
  NimMain()

  try:
    kmain(bootInfo)
  except Exception as e:
    unhandledException(e)

  quit()

####################################################################################################
# Report unhandled Nim exceptions
####################################################################################################

proc unhandledException(e: ref Exception) =
  logger.info ""
  logger.info &"Unhandled exception: [{e.name}] {e.msg}"
  if e.trace.len > 0:
    logger.info ""
    logger.info "Stack trace:"
    debug getStackTrace(e)
  quit()
