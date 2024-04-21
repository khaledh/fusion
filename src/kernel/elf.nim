type
  ElfImage = object
    header: ptr ElfHeader

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
    Executable = (0'u32, "E")
    Writable   = (1, "W")
    Readable   = (2, "R")
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


proc initElfImage(image: ptr uint8): ElfImage =
  result.header = cast[ptr ElfHeader](image)
  if result.header.magic != [0x7f.char, 'E', 'L', 'F']:
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


iterator sections(image: ElfImage): tuple[i: uint16, sh: ptr ElfSectionHeader] =
  let header = image.header

  let shoff = header.shoff
  let shentsize = header.shentsize
  let shnum = header.shnum
  let shstrndx = header.shstrndx
  let shstrtab = cast[ptr ElfSectionHeader](header +! (shoff + shentsize * shstrndx))
  let shstrtabdata = cast[ptr cstring](header +! shstrtab.offset)

  for i in 0.uint16 ..< shnum:
    yield (i, cast[ptr ElfSectionHeader](header +! (shoff + shentsize * i)))

iterator segments(image: ElfImage): tuple[i: uint16, ph: ptr ElfProgramHeader] =
  let header = image.header

  let phoff = header.phoff
  let phentsize = header.phentsize
  let phnum = header.phnum

  for i in 0.uint16 ..< phnum:
    yield (i, cast[ptr ElfProgramHeader](header +! (phoff + phentsize * i)))
