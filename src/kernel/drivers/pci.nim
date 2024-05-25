import std/tables

import ../ports

let
  logger = DebugLogger(name: "pci")

const
  PciClassCode = {
    (0x00'u8, 0x00'u8, 0x00'u8): "Existing device except VGA-compatible",
    (0x00'u8, 0x01'u8, 0x00'u8): "VGA-compatible device",

    (0x01'u8, 0x00'u8, 0x00'u8): "SCSI controller",
    (0x01'u8, 0x00'u8, 0x11'u8): "SCSI storage device (SOP/PQI)",
    (0x01'u8, 0x00'u8, 0x12'u8): "SCSI controller (SOP/PQI)",
    (0x01'u8, 0x00'u8, 0x13'u8): "SCSI storage device and SCSI controller (SOP/PQI)",
    (0x01'u8, 0x00'u8, 0x21'u8): "SCSI storage device (SOP/NVMe)",
    (0x01'u8, 0x01'u8, 0x00'u8): "IDE controller",
    (0x01'u8, 0x02'u8, 0x00'u8): "Floppy disk controller",
    (0x01'u8, 0x03'u8, 0x00'u8): "IPI bus controller",
    (0x01'u8, 0x04'u8, 0x00'u8): "RAID controller",
    (0x01'u8, 0x05'u8, 0x20'u8): "ATA controller with ADMA interface - single stepping",
    (0x01'u8, 0x05'u8, 0x30'u8): "ATA controller with ADMA interface - continuous operation",
    (0x01'u8, 0x06'u8, 0x00'u8): "Serial ATA controller",
    (0x01'u8, 0x06'u8, 0x01'u8): "Serial ATA controller - AHCI",
    (0x01'u8, 0x06'u8, 0x02'u8): "Serial Storage Bus Interface",
    (0x01'u8, 0x07'u8, 0x00'u8): "Serial Attached SCSI (SAS) controller",
    (0x01'u8, 0x08'u8, 0x00'u8): "NVM subsystem",
    (0x01'u8, 0x08'u8, 0x01'u8): "NVM subsystem NVMHCI",
    (0x01'u8, 0x08'u8, 0x02'u8): "NVM Express (NVMe) I/O controller",
    (0x01'u8, 0x08'u8, 0x03'u8): "NVM Express (NVMe) administrative controller",
    (0x01'u8, 0x09'u8, 0x00'u8): "Universal Flash Storage (UFS) controller",
    (0x01'u8, 0x09'u8, 0x01'u8): "Universal Flash Storage (UFS) controller - UFSHCI",
    (0x01'u8, 0x80'u8, 0x00'u8): "Other mass storage controller",

    (0x02'u8, 0x00'u8, 0x00'u8): "Ethernet controller",
    (0x02'u8, 0x01'u8, 0x00'u8): "Token Ring controller",
    (0x02'u8, 0x02'u8, 0x00'u8): "FDDI controller",
    (0x02'u8, 0x03'u8, 0x00'u8): "ATM controller",
    (0x02'u8, 0x04'u8, 0x00'u8): "ISDN controller",
    (0x02'u8, 0x05'u8, 0x00'u8): "WorldFip controller",
    (0x02'u8, 0x06'u8, 0x00'u8): "PICMG 2.14 Mutli Computing",
    (0x02'u8, 0x07'u8, 0x00'u8): "InfiniBand controller",
    (0x02'u8, 0x08'u8, 0x00'u8): "Host fabric controller",
    (0x02'u8, 0x80'u8, 0x00'u8): "Other network controller",

    (0x03'u8, 0x00'u8, 0x00'u8): "VGA-compatible controller",
    (0x03'u8, 0x00'u8, 0x01'u8): "8514-compatible controller",
    (0x03'u8, 0x10'u8, 0x00'u8): "XGA controller",
    (0x03'u8, 0x20'u8, 0x00'u8): "3D controller",
    (0x03'u8, 0x80'u8, 0x00'u8): "Other display controller",

    (0x04'u8, 0x00'u8, 0x00'u8): "Video device",
    (0x04'u8, 0x01'u8, 0x00'u8): "Audio device",
    (0x04'u8, 0x02'u8, 0x00'u8): "Computer telephony device",
    (0x04'u8, 0x03'u8, 0x00'u8): "High Definition Audio (HD-A) 1.0 compatible",
    (0x04'u8, 0x03'u8, 0x80'u8): "High Definition Audio (HD-A) 1.0 compatible with extensions",
    (0x04'u8, 0x80'u8, 0x00'u8): "Other multimedia device",

    (0x05'u8, 0x00'u8, 0x00'u8): "RAM",
    (0x05'u8, 0x10'u8, 0x00'u8): "Flash",
    (0x05'u8, 0x80'u8, 0x00'u8): "Other memory controller",

    (0x06'u8, 0x00'u8, 0x00'u8): "Host bridge",
    (0x06'u8, 0x01'u8, 0x00'u8): "ISA bridge",
    (0x06'u8, 0x02'u8, 0x00'u8): "EISA bridge",
    (0x06'u8, 0x03'u8, 0x00'u8): "MCA bridge",
    (0x06'u8, 0x04'u8, 0x00'u8): "PCI-to-PCI bridge",
    (0x06'u8, 0x04'u8, 0x01'u8): "Subtractive Decode PCI-to-PCI bridge",
    (0x06'u8, 0x05'u8, 0x00'u8): "PCMCIA bridge",
    (0x06'u8, 0x06'u8, 0x00'u8): "NuBus bridge",
    (0x06'u8, 0x07'u8, 0x00'u8): "CardBus bridge",
    (0x06'u8, 0x08'u8, 0x00'u8): "RACEway bridge",
    (0x06'u8, 0x09'u8, 0x40'u8): "Semi-transparent PCI-to-PCI bridge with host-facing primary",
    (0x06'u8, 0x09'u8, 0x80'u8): "Semi-transparent PCI-to-PCI bridge with host-facing secondary",
    (0x06'u8, 0x0a'u8, 0x00'u8): "InfiniBand-to-PCI host bridge",
    (0x06'u8, 0x0b'u8, 0x00'u8): "Advanced Switching-to-PCI host bridge - Custom Interface",
    (0x06'u8, 0x0b'u8, 0x01'u8): "Advanced Switching-to-PCI host bridge - ASI-SIG Interface",
    (0x06'u8, 0x80'u8, 0x00'u8): "Other bridge device",

    (0x0c'u8, 0x00'u8, 0x00'u8): "IEEE 1394 (FireWire)",
    (0x0c'u8, 0x00'u8, 0x01'u8): "IEEE 1394 - OpenHCI",
    (0x0c'u8, 0x01'u8, 0x00'u8): "ACCESS.bus",
    (0x0c'u8, 0x02'u8, 0x00'u8): "SSA",
    (0x0c'u8, 0x03'u8, 0x00'u8): "USB - UHCI",
    (0x0c'u8, 0x03'u8, 0x10'u8): "USB - OHCI",
    (0x0c'u8, 0x03'u8, 0x20'u8): "USB2 - EHCI",
    (0x0c'u8, 0x03'u8, 0x30'u8): "USB - xHCI",
    (0x0c'u8, 0x03'u8, 0x40'u8): "USB4 Host Interface",
    (0x0c'u8, 0x03'u8, 0x80'u8): "USB host controller",
    (0x0c'u8, 0x03'u8, 0xfe'u8): "USB device",
    (0x0c'u8, 0x04'u8, 0x00'u8): "Fibre Channel",
    (0x0c'u8, 0x05'u8, 0x00'u8): "SMBus",
    (0x0c'u8, 0x06'u8, 0x00'u8): "InfiniBand (deprecated)",
    (0x0c'u8, 0x07'u8, 0x00'u8): "IPMI SMIC Interface",
    (0x0c'u8, 0x07'u8, 0x01'u8): "IPMI Keyboard Controller Style Interface",
    (0x0c'u8, 0x07'u8, 0x02'u8): "IPMI Block Transfer Interface",
    (0x0c'u8, 0x08'u8, 0x00'u8): "SERCOS Interface Standard",
    (0x0c'u8, 0x09'u8, 0x00'u8): "CANbus",
    (0x0c'u8, 0x0a'u8, 0x00'u8): "MIPI I3C Host Controller Interface",
    (0x0c'u8, 0x80'u8, 0x00'u8): "Other Serial Bus controllers",
  }.toTable

type
  PciDeviceConfig* = object
    bus*: uint8
    slot*: uint8
    fn*: uint8
    vendorId*: uint16
    deviceId*: uint16
    classCode*: uint8
    subClass*: uint8
    progIf*: uint8
    revisionId*: uint8
    bar*: array[6, uint32]
    interruptLine*: uint8
    interruptPin*: uint8
    capabilities*: seq[PciCapability]
    desc*: string

  PciCapability* = enum
    Null
    PowerManagement
    Agp
    VitalProductData
    SlotIdentification
    Msi
    CompactPciHotSwap
    PciX
    HyperTransport
    VendorSpecific
    DebugPort
    CompactPCICentralResourceControl
    PciHotPlug
    PciBrdigeSubsystemVendorId
    Agp8x
    SecureDevice
    PciExpress
    MsiX
    SataDataIndexConfiguration
    AdvancedFeatures
    EnhancedAllocation
    FlatteningPortalBridge

  PciConfigSpaceRegister = enum
    VendorId = 0x00
    DeviceId = 0x02
    Command = 0x04
    Status = 0x06
    RevisionId = 0x08
    ProgIf = 0x09
    SubClass = 0x0a
    ClassCode = 0x0b
    CacheLineSize = 0x0c
    LatencyTimer = 0x0d
    HeaderType = 0x0e
    Bist = 0x0f
    Bar0 = 0x10
    Bar1 = 0x14
    Bar2 = 0x18
    Bar3 = 0x1c
    Bar4 = 0x20
    Bar5 = 0x24
    CardbusCisPointer = 0x28
    SubsystemVendorId = 0x2c
    SubsystemId = 0x2e
    ExpansionRomBaseAddress = 0x30
    CapabilitiesPointer = 0x34
    InterruptLine = 0x3c
    InterruptPin = 0x3d
    MinGrant = 0x3e
    MaxLatency = 0x3f


converter toUInt8(x: PciConfigSpaceRegister): uint8 = x.uint8


proc pciConfigRead32*(bus, slot, fn, offset: uint8): uint32 =
  assert offset mod 4 == 0

  let address: uint32 =
    (1.uint32 shl 31) or
    (bus.uint32 shl 16) or
    (slot.uint32 shl 11) or
    (fn.uint32 shl 8) or
    offset

  portOut32(0xcf8'u16, address)
  result = portIn32(0xcfc)


proc addrOf(bus, slot, fn, offset: uint8): uint32 =
  result = (1.uint32 shl 31) or
    (bus.uint32 shl 16) or
    (slot.uint32 shl 11) or
    (fn.uint32 shl 8) or
    (offset and not 0b11'u8)


proc pciConfigRead16*(bus, slot, fn, offset: uint8): uint16 =
  assert offset mod 2 == 0

  let address: uint32 = addrOf(bus, slot, fn, offset)

  portOut32(0xcf8, address)
  var dword = portIn32(0xcfc) shr ((offset and 0x2) * 8)

  result = dword.uint16


proc pciNextCapability*(bus, slot, fn, offset: uint8): tuple[capValue: uint8, nextOffset: uint8] =
  let
    capReg = pciConfigRead16(bus, slot, fn, offset)
    capValue = (capReg and 0xff).uint8
    nextOffset = (capReg shr 8).uint8

  result = (capValue, nextOffset)


proc getDeviceConfig(bus, slot, fn: uint8): PciDeviceConfig =
  result.bus = bus
  result.slot = slot
  result.fn = fn

  result.vendorId = pciConfigRead16(bus, slot, fn, VendorId)
  result.deviceId = pciConfigRead16(bus, slot, fn, DeviceId)

  if result.vendorId == 0xffff:  # no device function
    return

  let class = pciConfigRead32(bus, slot, fn, RevisionId)
  result.classCode = (class shr 24).uint8
  result.subClass = (class shr 16).uint8
  result.progIF = (class shr 8).uint8

  # Base Address Registers
  result.bar[0] = pciConfigRead32(bus, slot, fn, Bar0)
  result.bar[1] = pciConfigRead32(bus, slot, fn, Bar1)
  result.bar[2] = pciConfigRead32(bus, slot, fn, Bar2)
  result.bar[3] = pciConfigRead32(bus, slot, fn, Bar3)
  result.bar[4] = pciConfigRead32(bus, slot, fn, Bar4)
  result.bar[5] = pciConfigRead32(bus, slot, fn, Bar5)

  let interrupt = pciConfigRead16(bus, slot, fn, InterruptLine)
  result.interruptLine = (interrupt and 0xff).uint8
  result.interruptPin = (interrupt shr 8).uint8

  result.desc = PciClassCode.getOrDefault((result.classCode, result.subClass, result.progIF), "")

  let status = pciConfigRead16(bus, slot, fn, Status)
  if (status and 0x10) == 1:  # has capabilities
    var
      capOffset = pciConfigRead16(bus, slot, fn, CapabilitiesPointer).uint8
      capValue: uint8

    while capOffset != 0:
      (capValue, capOffset) = pciNextCapability(bus, slot, fn, capOffset)
      result.capabilities.add(cast[PciCapability](capValue))


iterator enumeratePciSlot(bus: uint8, slot: uint8): PciDeviceConfig {.closure.} =
  let dev0 = getDeviceConfig(bus, slot, 0)
  if dev0.vendorId == 0xffff:  # no device
    return

  yield dev0

  let headerType = pciConfigRead16(bus, slot, 0, HeaderType)
  let isMultiFunction = (headerType and 0x80) shr 7

  if isMultiFunction == 1:
    for fn in 0.uint8 ..< 8:
      let dev = getDeviceConfig(bus, slot, fn)
      if dev.vendorId != 0xffff:
        yield dev


iterator enumeratePciBus*(bus: uint8): PciDeviceConfig {.closure.} =
  for slot in 0.uint8 ..< 32:
    for devConfig in enumeratePciSlot(bus, slot):
      yield devConfig


proc showPciConfig*() =

  proc showPciDevice(dev: PciDeviceConfig) =
    logger.raw &"  pci {dev.bus:0>2x}:{dev.slot:0>2x}.{dev.fn} -> {dev.vendorId:0>4x}:{dev.deviceId:0>4x}"
    logger.raw &" {dev.classCode:0>2x}h,{dev.subClass:0>2x}h,{dev.progIF:0>2x}h)"
    logger.raw &"  {dev.desc}, interrupt: pin({dev.interruptPin}) line({dev.interruptLine})"

    for cap in dev.capabilities:
        logger.raw &" {cap}"
        # if cap.uint8 == 0x12: # Sata Data-Index Configuration
        #   let revision = pciConfigRead16(bus, dev, fn, capOffset + 2)
        #   logger.raw &" revision={(revision shr 4) and 0xf}.{revision and 0xf}"
        #   let satacr1 = pciConfigRead16(bus, dev, fn, capOffset + 4)
        #   logger.raw &" barloc={satacr1 and 0xf:0>4b}b, barofst={(satacr1 shr 4) and 0xfffff:0>5x}h"

    # logger.info ""
    # logger.info &"    BAR0: {dev.bar[0]:0>8x}h"
    # logger.info &"    BAR1: {dev.bar[1]:0>8x}h"
    # logger.info &"    BAR2: {dev.bar[2]:0>8x}h"
    # logger.info &"    BAR3: {dev.bar[3]:0>8x}h"
    # logger.info &"    BAR4: {dev.bar[4]:0>8x}h"
    # logger.info &"    BAR5: {dev.bar[5]:0>8x}h"

    logger.raw "\n"

  logger.info "pci bus"

  for dev in enumeratePciBus(0):
    showPciDevice(dev)
