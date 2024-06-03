#[
  VMWare SVGA II driver
]#

import common/pagetables
import pci
import kernel/ports
import kernel/vmm

{.experimental: "codeReordering".}

let
  logger = DebugLogger(name: "vmsvga")

const
  PortIndex = 0
  PortValue = 1

  VersionMagic = 0x900000'u32

  FifoMin = 0
  FifoMax = 1
  FifoNextCmd = 2
  FifoStop = 3

  CmdUpdateValue = 1'u32
  CmdRectFillValue = 2'u32

let
  VersionId0 = ((VersionMagic shl 8) or 0)
  VersionId1 = ((VersionMagic shl 8) or 1)
  VersionId2 = ((VersionMagic shl 8) or 2)

type
  Reg = enum
    Id = 0
    Enable = 1
    Width = 2
    Height = 3
    MaxWidth = 4
    MaxHeight = 5
    Depth = 6
    BitsPerPixel = 7  # current bpp in the guest
    PseudoColor = 8
    RedMask = 9
    GreenMask = 10
    BlueMask = 11
    BytesPerLine = 12
    FbStart = 13
    FbOffset = 14
    VramSize = 15
    FbSize = 16
    Capabilities = 17
    MemStart = 18     # deprecated
    MemSize = 19
    ConfigDone = 20   # set when memory area is configured
    Sync = 21
    Busy = 22
    GuestId = 23
    CursorId = 24     # deprecated
    CursorX = 25      # deprecated
    CursorY = 26      # deprecated
    CursorOn = 27     # deprecated
    HostBitsPerPixel = 28  # deprecated
    ScratchSize = 29  # number of scratch registers
    MemRegs = 30      # number of FIFO registers
    NumDisplays = 31  # deprecated
    PitchLock = 32    # fixed pitch for all modes
    IrqMask = 33      # interrupt mask

type
  CmdUpdate {.packed.} = object
    x: uint32
    y: uint32
    width: uint32
    height: uint32

  CmdRectFill {.packed.} = object
    color: uint32
    x: uint32
    y: uint32
    width: uint32
    height: uint32

  Region* = object
    x*: uint32
    y*: uint32
    width*: uint32
    height*: uint32

var
  ioBase: uint16
  fbPhysAddr: uint64
  fbSize: uint32
  fb: ptr UncheckedArray[uint32]
  fifoPhysAddr: uint64
  fifoSize: uint32
  fifo: ptr UncheckedArray[uint32]
  vramSize: uint32
  capabilities: uint32
  pitch: uint32
  nextCmdOffset: uint32 = 0

proc readRegister(index: uint32): uint32 =
  portOut32(ioBase + PortIndex, index)
  return portIn32(ioBase + PortValue)

template readRegister*(index: Reg): uint32 =
  readRegister(index.uint32)

proc writeRegister(index: uint32, value: uint32) =
  portOut32(ioBase + PortIndex, index)
  portOut32(ioBase + PortValue, value)

template writeRegister*(index: Reg, value: uint32) =
  writeRegister(index.uint32, value)

proc pciInit*(dev: PciDeviceConfig) =
  logger.info &"initializing vmware svga ii driver"
  logger.info &"  bar[0] = {dev.bar[0]:#010x}"
  logger.info &"  bar[1] = {dev.bar[1]:#010x}"
  logger.info &"  bar[2] = {dev.bar[2]:#010x}"

  ioBase = dev.bar[0].uint16 - 1
  fbPhysAddr = dev.bar[1]
  fifoPhysAddr = dev.bar[2]

  # check the version number
  writeRegister(Reg.Id, VersionId2)
  if (readRegister(Reg.Id) != VersionId2):
    raise newException(Exception, "unsupported version for vmware svga ii driver")

  logger.info &"  version id = {VersionId2 and 0x0f}"
  logger.info &"  width = {readRegister(Reg.Width)}"
  logger.info &"  height = {readRegister(Reg.Height)}"
  logger.info &"  max width = {readRegister(Reg.MaxWidth)}"
  logger.info &"  max height = {readRegister(Reg.MaxHeight)}"
  logger.info &"  bpp = {readRegister(Reg.BitsPerPixel)}"

  vramSize = readRegister(Reg.VramSize)
  logger.info &"  vram size = {vramSize}"

  capabilities = readRegister(Reg.Capabilities)
  logger.info &"  capabilities = {capabilities:#010x}"

  # Read SVGA_REG_FB_START, SVGA_REG_FB_SIZE, SVGA_REG_MEM_START, SVGA_REG_MEM_SIZE.
  fbPhysAddr = readRegister(Reg.FbStart)
  fbSize = readRegister(Reg.FbSize)
  logger.info &"fbPhysAddr = {cast[uint64](fbPhysAddr):#010x}, size = {fbSize}"

  # map the fb memory
  let fbNumPages = (fbSize + (PageSize - 1)) div PageSize
  let fbVMRegion = vmalloc(kspace, fbNumPages)
  logger.info &"  mapping fb memory @ {fbVMRegion.start.uint64:#010x}, pages = {fbNumPages}"
  mapRegion(
    pml4 = getActivePML4(),
    virtAddr = fbVMRegion.start,
    physAddr = (fbPhysAddr).PhysAddr,
    pageCount = fbNumPages,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
    noExec = true
  )
  fb = cast[ptr UncheckedArray[uint32]](fbVMRegion.start)

  fifoPhysAddr = readRegister(Reg.MemStart)
  fifoSize = readRegister(Reg.MemSize)
  logger.info &"fifoMem = {cast[uint64](fifoPhysAddr):#010x}, size = {fifoSize}"

  # map the fifo memory
  let fifoNumPages = (fifoSize + (PageSize - 1)) div PageSize
  let fifoVMRegion = vmalloc(kspace, fifoNumPages)
  logger.info &"  mapping fifo memory @ {fifoVMRegion.start.uint64:#010x}, pages = {fifoNumPages}"
  mapRegion(
    pml4 = getActivePML4(),
    virtAddr = fifoVMRegion.start,
    physAddr = fifoPhysAddr.PhysAddr,
    pageCount = fifoNumPages,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
    noExec = true
  )
  fifo = cast[ptr UncheckedArray[uint32]](fifoVMRegion.start)

  logger.info &"  width = {readRegister(Reg.Width)}"
  logger.info &"  height = {readRegister(Reg.Height)}"

  fifo[FifoMin] = 4 * sizeof(uint32)
  fifo[FifoMax] = fifoSize
  fifo[FifoNextCmd] = fifo[FifoMin]
  fifo[FifoStop] = fifo[FifoMin]
  nextCmdOffset = fifo[FifoNextCmd]

  # enable svga
  logger.info &"enabling svga"
  writeRegister(Reg.Enable, 1)
  writeRegister(Reg.ConfigDone, 1)

  # read pitch
  pitch = readRegister(Reg.BytesPerLine)
  logger.info &"  pitch = {pitch}"

proc setMode*(width, height, bpp: uint32) =
  # disable svga
  writeRegister(Reg.Enable, 0)

  # set mode
  logger.info &"setting mode: {width}x{height} @ {bpp}bpp"
  writeRegister(Reg.Width, width)
  writeRegister(Reg.Height, height)
  writeRegister(Reg.BitsPerPixel, bpp)

  # enable svga
  writeRegister(Reg.Enable, 1)

  # read pitch
  pitch = readRegister(Reg.BytesPerLine)

proc getFrameBuffer*(): ptr UncheckedArray[uint32] {.inline.} =
  return fb

proc update*(r: Region) =
  if nextCmdOffset + sizeof(uint32).uint32 + sizeof(CmdUpdate).uint32 >= fifo[FifoMax]:
    nextCmdOffset = fifo[FifoMin]

  let cmdOffset = nextCmdOffset

  # logger.info &"fifo = {cast[uint64](fifo):#010x}"
  # logger.info &"nextCmdOffset = {nextCmdOffset:#010x}"
  fifo[nextCmdOffset div 4] = CmdUpdateValue
  inc nextCmdOffset, sizeof(uint32)
  # logger.info &"nextCmdOffset = {nextCmdOffset:#010x}"
  var cmd = cast[ptr CmdUpdate](fifo +! nextCmdOffset)
  inc nextCmdOffset, sizeof(CmdUpdate)
  # logger.info &"nextCmdOffset = {nextCmdOffset:#010x}"

  # logger.info &"cmd @ {cast[uint64](cmd):#010x}"

  cmd.x = r.x
  cmd.y = r.y
  cmd.width = r.width
  cmd.height = r.height

  fifo[FifoNextCmd] = cmdOffset

  # dump first 10 dwords of fifo
  # for i in 0 ..< 10:
  #   logger.info &"fifo[{i}] = {fifo[i]:#010x}"

proc rectFill*(x, y, width, height, color: uint32) =
  if nextCmdOffset + sizeof(uint32).uint32 + sizeof(CmdUpdate).uint32 >= fifo[FifoMax]:
    nextCmdOffset = fifo[FifoMin]

  let cmdOffset = nextCmdOffset

  fifo[nextCmdOffset div 4] = CmdRectFillValue
  inc nextCmdOffset, sizeof(uint32)
  var cmd = cast[ptr CmdRectFill](fifo +! nextCmdOffset)
  inc nextCmdOffset, sizeof(CmdRectFill)

  cmd.color = color
  cmd.x = x
  cmd.y = y
  cmd.width = width
  cmd.height = height

  fifo[FifoNextCmd] = cmdOffset

proc sync*() =
  while readRegister(Reg.Busy) != 0:
    discard
