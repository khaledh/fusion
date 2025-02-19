#[
  Bochs VGA/VBE Graphics Adapter
]#
import std/strformat

import common/pagetables
import pci
import ../ports
import ../vmm

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
  fbNumPages: uint64


proc bgaReadRegister*(index: uint16): uint16

proc pciInit*(dev: PciDeviceConfig) =
  logger.info &"initializing Bochs Graphics Adapter"

  let bgaId = bgaReadRegister(BgaPortIndexId)
  fbPhysAddr = dev.bar[0]

  logger.info &"  ...id = {bgaId:0>4x}"
  logger.info &"  ...framebuffer physical address = {fbPhysAddr:0>16x}"

proc getFramebuffer*(): ptr UncheckedArray[uint32] =
  cast[ptr UncheckedArray[uint32]](fbVirtAddr)

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

proc mapFramebuffer*(width, height: uint32): tuple[virtAddr: uint64, numPages: uint64] =
  let numPages = (width.uint64 * height.uint64 * 4 + (PageSize - 1)) div PageSize
  let vmRegion = vmalloc(kspace, numPages)
  mapRegion(
    region = VMRegion(start: vmRegion.start, npages: numPages),
    physAddr = fbPhysAddr.PhysAddr,
    pml4 = getActivePML4(),
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
    noExec = true
  )
  result = (vmRegion.start.uint64, numPages)

proc unmapFramebuffer*(virtAddr, numPages: uint64) =
    unmapRegion(
      region = VMRegion(start: virtAddr.VirtAddr, npages: numPages),
      pml4 = getActivePML4(),
    )

proc setResolution*(xres, yres: uint16) =
  logger.info &"setting resolution to {xres}x{yres}"
  bgaSetVideoMode(xres, yres, 32)

  let virtWidth = bgaReadRegister(BgaPortIndexVirtWidth)
  let virtHeight = bgaReadRegister(BgaPortIndexVirtHeight)
  logger.info &"  ...virtual resolution = {virtWidth}x{virtHeight}"

  if fbVirtAddr != 0:
    logger.info &"  ...unmapping old framebuffer"
    unmapFramebuffer(fbVirtAddr, fbNumPages)

  (fbVirtAddr, fbNumPages) = mapFramebuffer(virtWidth, virtHeight)
  logger.info &"  ...mapped {fbNumPages} pages of video memory @ {fbVirtAddr:#x}"
