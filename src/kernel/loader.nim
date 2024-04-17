import std/options
import std/strformat

import common/pagetables
import debugcon
import vmm
import pmm

type
  ElfHeader = object
    magic: array[4, char]
    class: uint8
    endianness: uint8
    version: uint8
    osabi: uint8
    abiversion: uint8
    pad: array[7, uint8]
    `type`: uint16
    machine: uint16
    version2: uint32
    entry: uint64
    phoff: uint64
    shoff: uint64
    flags: uint32
    ehsize: uint16
    phentsize: uint16
    phnum: uint16
    shentsize: uint16
    shnum: uint16
    shstrndx: uint16

  ElfType = enum
    None = (0'u16, "Unknown")
    Relocatable = (1, "Relocatable")
    Executable = (2, "Executable")
    Shared = (3, "Shared object")
    Core = (4, "Core")
  
  ElfMachine = enum
    None = (0'u16, "None")
    Sparc = (0x02, "Sparc")
    X86 = (0x03, "x86")
    Mips = (0x08, "MIPS")
    PowerPC = (0x14, "PowerPC")
    ARM = (0x28, "Arm")
    Sparc64 = (0x2b, "Sparc64")
    IA64 = (0x32, "IA-64")
    X86_64 = (0x3e, "x86-64")
    AArch64 = (0xb7, "AArch64")
    RiscV = (0xf3, "RISC-V")

  ElfProgramHeader {.packed.} = object
    `type`: ElfProgramHeaderType
    flags: uint32  # can't use ElfProgramHeaderFlags here because sets are limited to 16-bits
    offset: uint64
    vaddr: uint64
    paddr: uint64
    filesz: uint64
    memsz: uint64
    align: uint64

  ElfProgramHeaderType = enum
    Null = (0'u32, "NULL")
    Load = (1, "LOAD")
    Dynamic = (2, "DYNAMIC")
    Interp = (3, "INTERP")
    Note = (4, "NOTE")
    ShLib = (5, "SHLIB")
    Phdr = (6, "PHDR")
    Tls = (7, "TLS")
    GnuEhFrame = (0x6474e550, "GNU_EH_FRAME")
    GnuStack = (0x6474e551, "GNU_STACK")
    GnuRelro = (0x6474e552, "GNU_RELRO")
  
  ElfProgramHeaderFlag {.size: sizeof(uint32).} = enum
    Executable = (1'u32, "Executable")
    Writable = (2, "Writable")
    Readable = (4, "Readable")
  ElfProgramHeaderFlags = set[ElfProgramHeaderFlag]

  ElfSectionHeader {.packed.} = object
    nameoffset: uint32
    `type`: ElfSectionType
    flags: uint64
    vaddr: uint64
    offset: uint64
    size: uint64
    link: uint32
    info: uint32
    addralign: uint64
    entsize: uint64
  
  ElfSectionType = enum
    Null = (0'u32, "NULL")
    ProgBits = (1, "PROGBITS")
    SymTab = (2, "SYMTAB")
    StrTab = (3, "STRTAB")
    Rela = (4, "RELA")
    Hash = (5, "HASH")
    Dynamic = (6, "DYNAMIC")
    Note = (7, "NOTE")
    NoBits = (8, "NOBITS")
    Rel = (9, "REL")
    ShLib = (10, "SHLIB")
    DynSym = (11, "DYNSYM")
    InitArray = (14, "INIT_ARRAY")
    FiniArray = (15, "FINI_ARRAY")
    PreInitArray = (16, "PREINIT_ARRAY")
    Group = (17, "GROUP")
    SymTabShndx = (18, "SYMTAB_SHNDX")
    GnuAttributes = (0x6ffffff5, "GNU_ATTRIBUTES")
    GnuHash = (0x6ffffff6, "GNU_HASH")
    GnuLibList = (0x6ffffff7, "GNU_LIBLIST")
    CheckSum = (0x6ffffff8, "CHECKSUM")
    GnuVerDef = (0x6ffffffd, "GNU_VERDEF")
    GnuVerNeed = (0x6ffffffe, "GNU_VERNEED")
    GnuVerSym = (0x6fffffff, "GNU_VERSYM")

  LoadedElfImage* = object
    vmRegion*: VMRegion
    entryPoint*: pointer


proc applyRelocations(image: ptr UncheckedArray[byte], dynOffset: uint64)

proc load*(imagePhysAddr: PhysAddr, pml4: ptr PML4Table): LoadedElfImage =
  let image = p2v(imagePhysAddr)

  let header = cast[ptr ElfHeader](image)
  if header.magic != [0x7f.char, 'E', 'L', 'F']:
    raise newException(Exception, "Not an ELF file")

  # debugln "ELF header:"
  # debugln &"  Type: {cast[ElfType](header.`type`)}"
  # debugln &"  Machine: {cast[ElfMachine](header.machine)}"
  # debugln &"  Entry: {header.entry:#x}"
  # debugln &"  Program header offset: {header.phoff:#x}"
  # debugln &"  Section header offset: {header.shoff:#x}"
  # debugln &"  Flags: {header.flags:#x}"
  # debugln &"  ELF header size: {header.ehsize}"
  # debugln &"  Program header entry size: {header.phentsize}"
  # debugln &"  Program header entry count: {header.phnum}"
  # debugln &"  Section header entry size: {header.shentsize}"
  # debugln &"  Section header entry count: {header.shnum}"
  # debugln &"  Section header string table index: {header.shstrndx}"

  var dynOffset: int = -1

  let shoff = header.shoff
  let shentsize = header.shentsize
  let shnum = header.shnum
  let shstrndx = header.shstrndx
  let shstrtab = cast[ptr ElfSectionHeader](cast[uint64](image) + shoff + shentsize * shstrndx)
  let shstrtabdata = cast[ptr cstring](cast[uint64](image) + shstrtab.offset)
  for i in 0.uint16 ..< shnum:
    let sh = cast[ptr ElfSectionHeader](cast[uint64](image) + shoff + shentsize * i)
    let name = cast[cstring](cast[uint64](shstrtabdata) + sh.nameoffset)
    # debugln &"Section {i}: {name}"

    if sh.type == ElfSectionType.Dynamic:
      # debugln &"  Dynamic section found at {sh.offset:#x}"
      dynOffset = cast[int](sh.vaddr)

  if dynOffset == -1:
    raise newException(Exception, "No dynamic section found")

  let phoffset = header.phoff
  let phentsize = header.phentsize
  let phnum = header.phnum

  var maxVAddr: uint64 = 0
  var minVAddr: uint64 = uint64.high
  for i in 0.uint16 ..< phnum:
    let ph = cast[ptr ElfProgramHeader](cast[uint64](image) + phoffset + phentsize * i)
    if ph.type == ElfProgramHeaderType.Load:
      if ph.vaddr < minVAddr:
        minVAddr = ph.vaddr
      if ph.vaddr + ph.memsz > maxVAddr:
        maxVAddr = ph.vaddr + ph.memsz
    

  if minVAddr != 0:
    raise newException(Exception, "Expecting a PIE binary with a base address of 0")

  var totalVMSize = maxVAddr
  # debugln &"loader: Total VM size: {totalVMSize}"

  let pageCount = (totalVMSize + PageSize - 1) div PageSize
  let vmRegionOpt = vmalloc(uspace, pageCount)
  if vmRegionOpt.isNone:
    raise newException(Exception, "Failed to allocate memory")
  let vmRegion = vmRegionOpt.get
  debugln &"loader: Allocated {vmRegion.npages} pages at {vmRegion.start.uint64:#x}"

  # map the allocated memory into the page tables
  let newPhysAddr = vmmap(vmRegion, pml4, paReadWrite, pmUser)

  # copy the program segments to their respective locations

  # temporarily map the user image in kernel space
  debugln "loader: Mapping user image in kernel space"
  var kpml4 = getActivePML4()
  mapRegion(
    pml4 = kpml4,
    virtAddr = vmRegion.start,
    physAddr = newPhysAddr,
    pageCount = pageCount,
    pageAccess = paReadWrite,
    pageMode = pmSupervisor,
  )

  for i in 0.uint16 ..< phnum:
    let ph = cast[ptr ElfProgramHeader](cast[uint64](image) + phoffset + phentsize * i)
    # debug &"Program header {i}: {ph.type}"
    # debug &"  Flags: {ph.flags:#b}"
    # debug &"  VAddr: {ph.vaddr:#x}"
    # debug &"  File size: {ph.filesz}"
    # debugln &"  Mem size: {ph.memsz}"
    if ph.type == ElfProgramHeaderType.Load:
      let dest = cast[pointer](vmRegion.start +! ph.vaddr)
      let src = cast[pointer](cast[uint64](image) + ph.offset)
      copyMem(dest, src, ph.filesz)
      if ph.filesz < ph.memsz:
        zeroMem(cast[pointer](cast[uint64](dest) + ph.filesz), ph.memsz - ph.filesz)

  debugln "loader: Applying relocations to user image"
  applyRelocations(
    image = cast[ptr UncheckedArray[byte]](vmRegion.start),
    dynOffset = cast[uint64](dynOffset),
  )

  # unmap the user image from kernel space
  debugln "loader: Unmapping user image from kernel space"
  unmapRegion(
    pml4 = kpml4,
    virtAddr = vmRegion.start,
    pageCount = pageCount,
  )

  result.vmRegion = vmRegion
  result.entryPoint = cast[pointer](vmRegion.start +! header.entry)
  debugln &"loader: Entry point: {cast[uint64](result.entryPoint):#x}"

####################################################################################################
## Relocation
####################################################################################################

type
  DynamicEntry {.packed.} = object
    tag: uint64
    value: uint64

  DynmaicEntryType = enum
    Rela = 7
    RelaSize = 8
    RelaEntSize = 9
    RelaCount = 0x6ffffff9
  
  RelaEntry {.packed.} = object
    offset: uint64
    info: uint64
    addend: int64

  RelaEntryType = enum
    Relative = 8

proc applyRelocations(image: ptr UncheckedArray[byte], dynOffset: uint64) =
  # debugln &"applyRelo: image at {cast[uint64](image):#x}, dynOffset = {dynOffset:#x}"
  ## Apply relocations to the image. Return the entry point address.
  var
    dyn = cast[ptr UncheckedArray[DynamicEntry]](cast[uint64](image) + dynOffset)
    reloffset = 0'u64
    relsize = 0'u64
    relentsize = 0'u64
    relcount = 0'u64

  var i = 0
  # debugln &"dyn[i].tag = {dyn[i].tag:#x}"
  while dyn[i].tag != 0:
    case dyn[i].tag
    of DynmaicEntryType.Rela.uint64:
      reloffset = dyn[i].value
      # debugln &"reloffset = {reloffset:#x}"
    of DynmaicEntryType.RelaSize.uint64:
      relsize = dyn[i].value
      # debugln &"relsize = {relsize:#x}"
    of DynmaicEntryType.RelaEntSize.uint64:
      relentsize = dyn[i].value
      # debugln &"relentsize = {relentsize:#x}"
    of DynmaicEntryType.RelaCount.uint64:
      relcount = dyn[i].value
      # debugln &"relcount = {relcount:#x}"
    else:
      discard

    inc i

  if reloffset == 0 or relsize == 0 or relentsize == 0 or relcount == 0:
    raise newException(Exception, "Invalid dynamic section. Missing .dynamic information.")

  if relsize != relentsize * relcount:
    raise newException(Exception, "Invalid dynamic section. .rela.dyn size mismatch.")

  # rela points to the first relocation entry
  let rela = cast[ptr UncheckedArray[RelaEntry]](cast[uint64](image) + reloffset.uint64)
  # debugln &"rela = {cast[uint64](rela):#x}"

  for i in 0 ..< relcount:
    let relent = rela[i]
    # debugln &"relent = (.offset = {relent.offset:#x}, .info = {relent.info:#x}, .addend = {relent.addend:#x})"
    if relent.info != RelaEntryType.Relative.uint64:
      # raise newException(Exception, "Only relative relocations are supported.")
      debugln "loader: [WARNING] Only relative relocations are supported."
      continue
    # apply relocation
    let target = cast[ptr uint64](cast[uint64](image) + relent.offset)
    let value = cast[uint64](cast[int64](image) + relent.addend)
    # debugln &"target = {cast[uint64](target):#x}, value = {value:#x}"
    target[] = value
