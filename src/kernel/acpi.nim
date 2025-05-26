#[
  ACPI (Advanced Configuration and Power Interface) utilities.
]#

import vmdefs, vmmgr
 
let
  logger = DebugLogger(name: "acpi")

################################################################################
# Helper Functions
################################################################################

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
  logger.info &"  xsdt address: {cast[uint64](rsdp.xsdtAddress):#x}"

  xsdt = cast[ptr Xsdt](phys2virt(rsdp.xsdtAddress.PAddr))
  logger.info &"  xsdt revision: {xsdt.hdr.revision:x}"
  logger.info &"  xsdt length: {xsdt.hdr.length}"

  for hdr in xsdt.tables():
    logger.info &"  xsdt entry: {hdr.signature}"
