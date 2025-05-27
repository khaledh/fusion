#[
  I/O APIC
]#
import acpi

let
  logger = DebugLogger(name: "ioapic")

type
  Ioapic* = ref object
    id: uint8
    address: uint32
    registerSelect: ptr uint32
    registerData: ptr uint32
    gsiBase: uint32

var
  ioapic*: Ioapic

proc ioapicInit*(madt: ptr Madt)
proc setRedirEntry*(ioapic: Ioapic, irq: uint8, vector: uint8)

###############################################################################
# private
###############################################################################

type
  IoapicIdRegister {.packed.} = object
    reserved1 {.bitsize: 24.}: uint32
    id        {.bitsize:  4.}: uint32
    reserved2 {.bitsize:  4.}: uint32

  IoapicVersionRegister {.packed.} = object
    version       {.bitsize: 8.}: uint32
    reserved1     {.bitsize: 8.}: uint32
    maxRedirEntry {.bitsize: 8.}: uint32
    reserved2     {.bitsize: 8.}: uint32

  IoapicRedirectionEntry {.packed.} = object
    vector          {.bitsize:  8.}: uint64
    deliveryMode    {.bitsize:  3.}: uint64
    destinationMode {.bitsize:  1.}: uint64
    deliveryStatus  {.bitsize:  1.}: uint64
    polarity        {.bitsize:  1.}: uint64
    remoteIrr       {.bitsize:  1.}: uint64
    triggerMode     {.bitsize:  1.}: uint64
    mask            {.bitsize:  1.}: uint64
    reserved        {.bitsize: 39.}: uint64
    destination     {.bitsize:  8.}: uint64

proc ioapicInit*(madt: ptr Madt) =
  for entry in madt.ioapics:
    # only one ioapic is supported for now
    ioapic = Ioapic(
      id: entry.id,
      address: entry.address,
      registerSelect: cast[ptr uint32](entry.address.uint64),
      registerData: cast[ptr uint32](entry.address.uint64 + 0x10),
      gsiBase: entry.gsiBase,
    )
    break

  if ioapic == nil:
    raise newException(Exception, "No IOAPIC found")

  logger.info &"  ioapic id: {ioapic.id}, address: {ioapic.address:#x}, gsiBase: {ioapic.gsiBase}"

proc readRegister(ioapic: Ioapic, index: int): uint32 =
  ioapic.registerSelect[] = index.uint32
  result = ioapic.registerData[]

proc writeRegister(ioapic: Ioapic, index: uint32, value: uint32) =
  ioapic.registerSelect[] = index
  ioapic.registerData[] = value

proc setRedirEntry(ioapic: Ioapic, irq: uint8, vector: uint8) =
  # TODO: support other options
  let entry = IoapicRedirectionEntry(
    vector: vector,
    deliveryMode: 0,    # Fixed
    destinationMode: 0, # Physical
    deliveryStatus: 0,
    polarity: 0,        # ActiveHigh
    remoteIrr: 0,
    triggerMode: 0,     # Edge
    mask: 0,            # Enabled
    destination: 0,     # Lapic ID 0
  )
  let regIndex = 0x10 + (irq * 2)
  ioapic.writeRegister(regIndex + 0, cast[uint32](cast[uint64](entry) and 0xffff))
  ioapic.writeRegister(regIndex + 1, cast[uint32](cast[uint64](entry) shr 32))
