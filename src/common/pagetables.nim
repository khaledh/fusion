#[
  x86_64 paging structures
]#

type
  # Page Map Level 4 Entry
  PML4Entry* {.packed.} = object
    present* {.bitsize: 1.}: uint64      # bit      0
    write* {.bitsize: 1.}: uint64        # bit      1
    user* {.bitsize: 1.}: uint64         # bit      2
    writeThrough* {.bitsize: 1.}: uint64 # bit      3
    cacheDisable* {.bitsize: 1.}: uint64 # bit      4
    accessed* {.bitsize: 1.}: uint64     # bit      5
    ignored1* {.bitsize: 1.}: uint64     # bit      6 (ignored by CPU)
    reserved1* {.bitsize: 1.}: uint64    # bit      7
    ignored2* {.bitsize: 4.}: uint64     # bits 11: 8 (ignored by CPU)
    physAddress* {.bitsize: 40.}: uint64 # bits 51:12
    ignored3* {.bitsize: 11.}: uint64    # bits 62:52 (ignored by CPU)
    xd* {.bitsize: 1.}: uint64           # bit     63

  # Page Directory Pointer Table Entry
  PDPTEntry* {.packed.} = object
    present* {.bitsize: 1.}: uint64      # bit      0
    write* {.bitsize: 1.}: uint64        # bit      1
    user* {.bitsize: 1.}: uint64         # bit      2
    writeThrough* {.bitsize: 1.}: uint64 # bit      3
    cacheDisable* {.bitsize: 1.}: uint64 # bit      4
    accessed* {.bitsize: 1.}: uint64     # bit      5
    ignored1* {.bitsize: 1.}: uint64     # bit      6 (ignored by CPU)
    pageSize* {.bitsize: 1.}: uint64     # bit      7
    ignored2* {.bitsize: 4.}: uint64     # bits 11: 8 (ignored by CPU)
    physAddress* {.bitsize: 40.}: uint64 # bits 51:12
    ignored3* {.bitsize: 11.}: uint64    # bits 62:52 (ignored by CPU)
    xd* {.bitsize: 1.}: uint64           # bit     63

  # Page Directory Entry
  PDEntry* {.packed.} = object
    present* {.bitsize: 1.}: uint64      # bit      0
    write* {.bitsize: 1.}: uint64        # bit      1
    user* {.bitsize: 1.}: uint64         # bit      2
    writeThrough* {.bitsize: 1.}: uint64 # bit      3
    cacheDisable* {.bitsize: 1.}: uint64 # bit      4
    accessed* {.bitsize: 1.}: uint64     # bit      5
    ignored1* {.bitsize: 1.}: uint64     # bit      6 (ignored by CPU)
    pageSize* {.bitsize: 1.}: uint64     # bit      7
    ignored2* {.bitsize: 4.}: uint64     # bits 11: 8 (ignored by CPU)
    physAddress* {.bitsize: 40.}: uint64 # bits 51:12
    ignored3* {.bitsize: 11.}: uint64    # bits 62:52 (ignored by CPU)
    xd* {.bitsize: 1.}: uint64           # bit     63

  # Page Table Entry
  PTEntry* {.packed.} = object
    present* {.bitsize: 1.}: uint64      # bit      0
    write* {.bitsize: 1.}: uint64        # bit      1
    user* {.bitsize: 1.}: uint64         # bit      2
    writeThrough* {.bitsize: 1.}: uint64 # bit      3
    cacheDisable* {.bitsize: 1.}: uint64 # bit      4
    accessed* {.bitsize: 1.}: uint64     # bit      5
    dirty* {.bitsize: 1.}: uint64        # bit      6
    pat* {.bitsize: 1.}: uint64          # bit      7
    global* {.bitsize: 1.}: uint64       # bit      8
    kflags* {.bitsize: 3.}: uint64       # bits 11: 9 (ignored by CPU)
    physAddress* {.bitsize: 40.}: uint64 # bits 51:12
    ignored3* {.bitsize: 11.}: uint64    # bits 62:52 (ignored by CPU)
    xd* {.bitsize: 1.}: uint64           # bit     63

  # Page Map Level 4 Table
  PML4Table* = object
    entries* {.align(PageSize).}: array[512, PML4Entry]

  # Page Directory Pointer Table
  PDPTable* = object
    entries* {.align(PageSize).}: array[512, PDPTEntry]

  # Page Directory
  PDTable* = object
    entries* {.align(PageSize).}: array[512, PDEntry]

  # Page Table
  PTable* = object
    entries* {.align(PageSize).}: array[512, PTEntry]

  PageAccess* = enum
    paRead = 0
    paReadWrite = 1

  PageMode* = enum
    pmSupervisor = 0
    pmUser = 1


proc `[]`*(pml4: ptr PML4Table; index: uint64): var PML4Entry {.inline.} = pml4.entries[index]
proc `[]`*(pdpt: ptr PDPTable; index: uint64): var PDPTEntry {.inline.} = pdpt.entries[index]
proc `[]`*(pd: ptr PDTable; index: uint64): var PDEntry {.inline.} = pd.entries[index]
proc `[]`*(pt: ptr PTable; index: uint64): var PTEntry {.inline.} = pt.entries[index]
