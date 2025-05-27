#[
  ACPI (Advanced Configuration and Power Interface) utilities.
]#

import vmdefs, vmmgr
 
let
  logger = DebugLogger(name: "acpi")

var
  acpiPhysicalBase: PAddr
  acpiVirtualBase: VAddr
  acpiPages: uint64

proc phys2virt(paddr: PAddr): VAddr =
  assert paddr.uint64 >= acpiPhysicalBase.uint64
  assert paddr.uint64 < acpiPhysicalBase.uint64 + acpiPages * PageSize.uint64
  return VAddr(acpiVirtualBase +! (paddr -! acpiPhysicalBase))

################################################################################
# RSDP (Root System Description Pointer)
################################################################################

type
  Rsdp* = object
    signature*: array[8, uint8]
    checksum*: uint8
    oemId*: array[6, uint8]
    revision*: uint8
    rsdtAddress*: uint32
    length*: uint32
    xsdtAddress*: uint64
    extendedChecksum*: uint8
    reserved*: array[3, uint8]

var
  rsdp: ptr Rsdp

################################################################################
# Table Description Header
################################################################################

type
  TableDescriptionHeader* {.packed.} = object
    signature*: array[4, char]
    length*: uint32
    revision*: uint8
    checksum*: uint8
    oem_id*: array[6, char]
    oem_table_id*: array[8, char]
    oem_revision*: uint32
    creator_id*: array[4, uint8]
    creator_revision*: uint32

################################################################################
# XSDT Table
################################################################################

type
  Xsdt* {.packed.} = object
    hdr: TableDescriptionHeader
    entries: UncheckedArray[uint64]

var
  xsdt: ptr Xsdt

iterator tables*(xsdt: ptr Xsdt): ptr TableDescriptionHeader =
  for i in 0 ..< (xsdt.hdr.length.int - sizeof(TableDescriptionHeader)) div 8:
    yield cast[ptr TableDescriptionHeader](phys2virt(xsdt.entries[i].PAddr))

proc findTableBySignature*(xsdt: ptr Xsdt, sig: array[4, char]): Option[ptr TableDescriptionHeader] =
  for hdr in xsdt.tables():
    if hdr.signature == sig:
      return some(hdr)

################################################################################
# MADT (Multiple APIC Description Table)
################################################################################

type
  MultipleApicFlag {.size: sizeof(uint32).} = enum
    PcAtCompat  = "PC/AT Compatible PIC"
  MultipleApicFlags = set[MultipleApicFlag]

  Madt* {.packed.} = object
    hdr: TableDescriptionHeader
    lapicAddress: uint32
    flags: MultipleApicFlags

  InterruptControllerType {.size: sizeof(uint8).} = enum
    ictLocalApic                 = "Local APIC"
    ictIoapic                    = "I/O APIC"
    ictInterruptSourceOverride   = "Interrupt Source Override"
    ictNmiSource                 = "NMI Source"
    ictLocalApicNmi              = "Local APIC NMI"
    ictLocalApicAddressOverride  = "Local APIC Address Override"
    ictIoSapic                   = "I/O SAPIC"
    ictLocalSapic                = "Local SAPIC"
    ictPlatformInterruptSources  = "Platform Interrupt Sources"
    ictLocalx2Apic               = "Local x2APIC"
    ictLocalx2ApicNmi            = "Local x2APIC NMI"
    ictGicCpuInterface           = "GIC CPU Interface (GICC)"
    ictGicDistributor            = "GIC Distributor (GICD)"
    ictGicMsiFrame               = "GIC MSI Frame"
    ictGicRedistributor          = "GIC Redistributor (GICR)"
    ictGicInterruptTranslationService = "GIC Interrupt Translation Service (ITS)"
    ictMultiprocessorWakeup      = "Multiprocessor Wakeup"

  InterruptControllerHeader {.packed.} = object
    typ: InterruptControllerType
    len: uint8

  LocalApic {.packed.} = object
    hdr: InterruptControllerHeader
    processorUid: uint8
    lapicId: uint8
    flags: LocalApicFlags
  LocalApicFlag {.size: sizeof(uint32).} = enum
    laEnabled        = "Enabled"
    laOnlineCapable  = "Online Capable"
  LocalApicFlags = set[LocalApicFlag]

  Ioapic* {.packed.} = object
    hdr: InterruptControllerHeader
    id*: uint8
    reserved: uint8
    address*: uint32
    gsiBase*: uint32

  InterruptSourceOverride {.packed.} = object
    hdr: InterruptControllerHeader
    bus: uint8
    source: uint8
    gsi: uint32
    flags: MpsIntInFlags
  InterruptPolarity {.size: 2.} = enum
    ipBusConformant  = (0b00, "Bus Conformant")
    ipActiveHigh     = (0b01, "Active High")
    ipResreved       = (0b10, "Reserved")
    ipActiveLow      = (0b11, "Active Low")
  InterruptTriggerMode {.size: 2.} = enum
    itBusConformant  = (0b00, "Bus Conformant")
    itEdgeTriggered  = (0b01, "Edge-Triggered")
    itResreved       = (0b10, "Reserved")
    itLevelTriggered = (0b11, "Level-Triggered")
  MpsIntInFlags {.packed.} = object
    polarity    {.bitsize: 2.}: InterruptPolarity
    triggerMode {.bitsize: 2.}: InterruptTriggerMode

  LocalApicNmi {.packed.} = object
    hdr: InterruptControllerHeader
    processorUid: uint8
    flags: MpsIntInFlags
    lintN: uint8

var
  madt: ptr Madt

# Interrupt Controller Structures
iterator intCtrlStructs(madt: ptr Madt): ptr InterruptControllerHeader {.inline.} =
  var intCtrlStruct = cast[ptr InterruptControllerHeader](
    cast[uint64](madt) + sizeof(TableDescriptionHeader).uint64 + 8
  )
  while cast[uint64](intCtrlStruct) - cast[uint64](madt) < madt.hdr.length:
    yield intCtrlStruct
    intCtrlStruct = cast[ptr InterruptControllerHeader](
      cast[uint64](intCtrlStruct) + intCtrlStruct.len
    )

# Local APICs
iterator lapics*(madt: ptr Madt): ptr LocalApic =
  for intCtrlStruct in intCtrlStructs(madt):
    if intCtrlStruct.typ == ictLocalApic:
      yield cast[ptr LocalApic](intCtrlStruct)

# I/O APICs
iterator ioapics*(madt: ptr Madt): ptr Ioapic =
  for intCtrlStruct in intCtrlStructs(madt):
    if intCtrlStruct.typ == ictIoapic:
      yield cast[ptr Ioapic](intCtrlStruct)

# Interrupt Source Overrides
iterator interruptSourceOverrides*(madt: ptr Madt): ptr InterruptSourceOverride =
  for intCtrlStruct in intCtrlStructs(madt):
    if intCtrlStruct.typ == ictInterruptSourceOverride:
      yield cast[ptr InterruptSourceOverride](intCtrlStruct)

# Local APIC NMIs
iterator lapicNMIs*(madt: ptr Madt): ptr LocalApicNmi =
  for intCtrlStruct in intCtrlStructs(madt):
    if intCtrlStruct.typ == ictLocalApicNmi:
      yield cast[ptr LocalApicNmi](intCtrlStruct)

################################################################################
# ACPI Initialization
################################################################################

proc acpiInit*(
  acpiMemoryPhysicalBase: PAddr,
  acpiMemoryPages: uint64,
  acpiRsdpPhysicalAddr: PAddr,
) =
  logger.info &"  mapping acpi memory"
  acpiPages = acpiMemoryPages
  acpiPhysicalBase = acpiMemoryPhysicalBase
  acpiVirtualBase = kvMapAt(
    paddr = acpiMemoryPhysicalBase,
    npages = acpiMemoryPages,
    perms = {pRead},
    flags = {vmPrivate},
  ).region.start

  rsdp = cast[ptr Rsdp](phys2virt(acpiRsdpPhysicalAddr))
  logger.info &"  rsdp revision: {rsdp.revision:x}"

  xsdt = cast[ptr Xsdt](phys2virt(rsdp.xsdtAddress.PAddr))
  logger.info &"  xsdt revision: {xsdt.hdr.revision:x}"
  for hdr in xsdt.tables():
    logger.info &"    table: {hdr.signature}"

  madt = cast[ptr Madt](xsdt.findTableBySignature(['A', 'P', 'I', 'C']).orRaise(
    newException(Exception, "Could not find MADT")
  ))

  logger.info &"  madt revision: {madt.hdr.revision:x}"
  logger.info &"    flags: {madt.flags}"
  logger.info &"    lapic address: {madt.lapicAddress:#x}"
  logger.info &"    lapics:"
  for lapic in madt.lapics():
    logger.info &"      proc: {lapic.processorUid}, id: {lapic.lapicId}, flags: {lapic.flags}"

  logger.info &"    ioapics:"
  for ioapic in madt.ioapics():
    logger.info &"      id: {ioapic.id}, addr: {ioapic.address:#x}, gsiBase: {ioapic.gsiBase}"

  logger.info &"    interrupt source overrides:"
  for iso in madt.interruptSourceOverrides():
    logger.info &"      bus: {iso.bus}, src: {iso.source}, gsi: {iso.gsi}, flags: {iso.flags}"

  logger.info &"    local apic nmis:"
  for nmi in madt.lapicNMIs():
    logger.info &"      proc: {nmi.processorUid}, lint: {nmi.lintN}, flags: {nmi.flags}"

proc getMadt*(): ptr Madt =
  if madt == nil:
    raise newException(Exception, "MADT not initialized")
  result = madt
