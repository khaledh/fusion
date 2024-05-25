#[
  Bochs VGA/VBE Graphics Adapter
]#
import std/strformat

import common/pagetables
import pci
import ../ports
import ../vmm

{.experimental: "codeReordering".}

const
  BgaPortIndex               = 0x1ce
  BgaPortValue               = 0x1cf

  BgaPortIndexId*            = 0x0
  BgaPortIndexXres           = 0x1
  BgaPortIndexYres           = 0x2
  BgaPortIndexBpp            = 0x3
  BgaPortIndexEnable         = 0x4
  # BgaPortIndexBank           = 0x5
  BgaPortIndexVirtWidth*     = 0x6
  BgaPortIndexVirtHeight*    = 0x7
  # BgaPortIndexXOffset        = 0x8
  BgaPortIndexYOffset        = 0x9
  # BgaPortIndexVideoMemory64K = 0xa
  # BgaPortIndexDdc            = 0xb

  # BgaId0                     = 0xB0C0
  # BgaId1                     = 0xB0C1
  # BgaId2                     = 0xB0C2
  # BgaId3                     = 0xB0C3
  # BgaId4                     = 0xB0C4
  # BgaId5                     = 0xB0C5

  # BgaBpp4                    = 0x04
  # BgaBpp8                    = 0x08
  # BgaBpp15                   = 0x0F
  # BgaBpp16                   = 0x10
  # BgaBpp24                   = 0x18
  # BgaBpp32                   = 0x20

  BgaDisabled                = 0x00
  BgaEnabled                 = 0x01
  # BgaGetCaps                 = 0x02
  # Bga8BitDac                 = 0x20
  BgaLfbEnabled              = 0x40
  # BgaNoClearMem              = 0x80

let
  logger = DebugLogger(name: "bga")

var
  fbPhysAddr: uint64
  fbVirtAddr: uint64

proc pciInit*(dev: PciDeviceConfig) =
  logger.info &"initializing Bochs Graphics Adapter"

  let bgaId = bgaReadRegister(BgaPortIndexId)
  fbPhysAddr = dev.bar[0]

  logger.info &"  ...id = {bgaId:0>4x}"
  logger.info &"  ...framebuffer physical address = {fbPhysAddr:0>16x}"

proc bgaWriteRegister(index, value: uint16) =
  portOut16(BgaPortIndex, index)
  portOut16(BgaPortValue, value)

proc bgaReadRegister*(index: uint16): uint16 =
  portOut16(BgaPortIndex, index)
  portIn16(BgaPortValue)

proc bgaSetVideoMode*(width, height, bpp: uint16) =
  bgaWriteRegister(BgaPortIndexEnable, BgaDisabled)
  bgaWriteRegister(BgaPortIndexXres, width)
  bgaWriteRegister(BgaPortIndexYres, height)
  bgaWriteRegister(BgaPortIndexBpp, bpp)
  bgaWriteRegister(BgaPortIndexEnable, BgaEnabled or BgaLfbEnabled)

proc bgaSetYOffset*(offset: uint16) =
  bgaWriteRegister(BgaPortIndexYOffset, offset)

proc setResolution*(xres, yres: uint16) =
  logger.info &"setting video mode to {xres}x{yres}"
  bgaSetVideoMode(xres, yres, 32)

  let virtWidth = bgaReadRegister(BgaPortIndexVirtWidth)
  let virtHeight = bgaReadRegister(BgaPortIndexVirtHeight)
  logger.info &"  ...virtual resolution = {virtWidth}x{virtHeight}"

  let numPages = (xres.uint64 * yres.uint64 * 4 + (PageSize - 1)) div PageSize
  let fbVMRegion = vmalloc(kspace, numPages)
  mapRegion(
    pml4 = getActivePML4(),
    virtAddr = fbVMRegion.start,
    physAddr = fbPhysAddr.PhysAddr,
    pageCount = numPages,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
    noExec = true
  )
  fbVirtAddr = fbVMRegion.start.uint64

  logger.info &"  ...mapped {numPages} pages of video memory @ {fbVirtAddr:#x}"

  var fb = cast[ptr UncheckedArray[uint32]](fbVirtAddr)

  for i in 0 ..< yres.uint32:
    for j in 0 ..< xres.uint32:
      fb[i * xres + j] = 0x608aaf'u32
