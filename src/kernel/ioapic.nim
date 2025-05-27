#[
  I/O APIC
]#
import acpi
import vmdefs, vmmgr

let
  logger = DebugLogger(name: "ioapic")

type
  Ioapic = ref object
    id: uint8
    address: VAddr
    registerSelect: ptr uint32
    registerData: ptr uint32
    gsiBase: uint32

var
  ioapic: Ioapic

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
  var ioapicEntry: ptr IoapicEntry
  for entry in madt.ioapics:
    # only one ioapic is supported for now
    ioapicEntry = entry
    break

  if ioapicEntry == nil:
    raise newException(Exception, "No IOAPIC found")

  # map physical address to virtual address
  let physPage = roundDownToPage(ioapicEntry.address.PAddr)
  let offset = offsetInPage(ioapicEntry.address.PAddr)
  let mapping = kvMapAt(
    paddr = physPage,
    npages = 1,
    perms = {pRead, pWrite},
    flags = {vmPrivate},
  )
  let vaddr = mapping.region.start +! offset

  ioapic = Ioapic(
    id: ioapicEntry.id,
    address: vaddr,
    registerSelect: cast[ptr uint32](vaddr),
    registerData: cast[ptr uint32](vaddr +! 0x10.uint64),
    gsiBase: ioapicEntry.gsiBase,
  )

  logger.info &"  ioapic id: {ioapic.id}, gsiBase: {ioapic.gsiBase}, phys: {ioapicEntry.address:#x}, virt: {cast[uint64](vaddr):#x}"

proc readRegister(index: int): uint32 =
  ioapic.registerSelect[] = index.uint32
  result = ioapic.registerData[]

proc writeRegister(index: uint32, value: uint32) =
  ioapic.registerSelect[] = index
  ioapic.registerData[] = value

proc setRedirEntry*(irq: uint8, vector: uint8) =
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
  writeRegister(regIndex + 0, cast[uint32](cast[uint64](entry) and 0xffff))
  writeRegister(regIndex + 1, cast[uint32](cast[uint64](entry) shr 32))
