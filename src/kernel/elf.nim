#[
  ELF image support
]#

type
  ElfImage = object
    header: ptr ElfHeader

  ElfHeader {.packed.} = object
    ident: ElfIdent
    `type`: ElfType
    machine: ElfMachine
    version: uint32
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

  ElfIdent {.packed.} = object
    magic: array[4, char]
    class: ElfClass
    endianness: ElfEndianness
    version: ElfVersion
    osabi: uint8
    abiversion: uint8
    pad: array[7, uint8]

  ElfClass = enum
    None = (0, "None")
    Bits32 = (1, "32-bit")
    Bits64 = (2, "64-bit")

  ElfEndianness = enum
    None = (0, "None")
    Little = (1, "Little-endian")
    Big = (2, "Big-endian")

  ElfVersion = enum
    None = (0, "None")
    Current = (1, "Current")

  ElfType {.size: sizeof(uint16).} = enum
    None = (0, "Unknown")
    Relocatable = (1, "Relocatable")
    Executable = (2, "Executable")
    Shared = (3, "Shared object")
    Core = (4, "Core")
  
  ElfMachine {.size: sizeof(uint16).} = enum
    None = (0, "None")
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
    flags: ElfProgramHeaderFlags
    offset: uint64
    vaddr: uint64
    paddr: uint64
    filesz: uint64
    memsz: uint64
    align: uint64

  ElfProgramHeaderType {.size: sizeof(uint32).} = enum
    Null = (0, "NULL")
    Load = (1, "LOAD")
    Dynamic = (2, "DYNAMIC")
    Interp = (3, "INTERP")
    Note = (4, "NOTE")
    ShLib = (5, "SHLIB")
    Phdr = (6, "PHDR")
    Tls = (7, "TLS")
  
  ElfProgramHeaderFlag = enum
    Executable = (0, "E")
    Writable   = (1, "W")
    Readable   = (2, "R")
  ElfProgramHeaderFlags {.size: sizeof(uint32).} = set[ElfProgramHeaderFlag]

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
  
  ElfSectionType {.size: sizeof(uint32).} = enum
    Null = (0, "NULL")
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

  InvalidElfImage = object of CatchableError
  UnsupportedElfImage = object of CatchableError

proc initElfImage(image: pointer): ElfImage =
  result.header = cast[ptr ElfHeader](image)

  if result.header.ident.magic != [0x7f.char, 'E', 'L', 'F']:
    raise newException(InvalidElfImage, "Not an ELF file")

  if result.header.ident.class != ElfClass.Bits64:
    raise newException(UnsupportedElfImage, "Only 64-bit ELF files are supported")

  if result.header.ident.endianness != ElfEndianness.Little:
    raise newException(UnsupportedElfImage, "Only little-endian ELF files are supported")

  if result.header.ident.version != ElfVersion.Current:
    raise newException(UnsupportedElfImage, &"Only ELF version {ElfVersion.Current} is supported.")

  if result.header.type != ElfType.Shared:
    raise newException(UnsupportedElfImage, "Only PIE type ELF files are supported.")

  if result.header.machine != ElfMachine.X86_64:
    raise newException(UnsupportedElfImage, "Only x86-64 ELF files are supported.")

iterator sections(image: ElfImage): tuple[i: uint16, sh: ptr ElfSectionHeader] =
  let header = image.header

  let shoff = header.shoff
  let shentsize = header.shentsize
  let shnum = header.shnum
  # let shstrndx = header.shstrndx
  # let shstrtab = cast[ptr ElfSectionHeader](header +! (shoff + shentsize * shstrndx))
  # let shstrtabdata = cast[ptr cstring](header +! shstrtab.offset)

  for i in 0.uint16 ..< shnum:
    let sh = cast[ptr ElfSectionHeader](header +! (shoff + shentsize * i))
    yield (i, sh)

iterator segments(image: ElfImage): tuple[i: uint16, ph: ptr ElfProgramHeader] =
  let header = image.header

  let phoff = header.phoff
  let phentsize = header.phentsize
  let phnum = header.phnum

  # debugln "loader: Program Headers:"
  # debugln "  #  type           offset     vaddr    filesz     memsz   flags     align"
  for i in 0.uint16 ..< phnum:
    let ph = cast[ptr ElfProgramHeader](header +! (phoff + phentsize * i))
    # debug &"  {i}: {ph.type:11}"
    # debug &"  {ph.offset:>#8x}"
    # debug &"  {ph.vaddr:>#8x}"
    # debug &"  {ph.filesz:>#8x}"
    # debug &"  {ph.memsz:>#8x}"
    # debug &"  {cast[ElfProgramHeaderFlags](ph.flags):>8}"
    # debug &"  {ph.align:>#6x}"
    # debugln ""
    yield (i, ph)
