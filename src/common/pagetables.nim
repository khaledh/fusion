#[
  x86_64 paging structures
]#

type
  # CR3 register
  CR3* {.packed.} = object
    ignored1*     {.bitsize:  3.}: uint64 # bits  2: 0
    writeThrough* {.bitsize:  1.}: uint64 # bit      3
    cacheDisable* {.bitsize:  1.}: uint64 # bit      4
    ignored*      {.bitsize:  7.}: uint64 # bit  11: 5
    physAddress*  {.bitsize: 40.}: uint64 # bits 51:12 (-> PML4Table)
    reserved1*    {.bitsize:  9.}: uint64 # bits 60:52
    lam57enable*  {.bitsize:  1.}: uint64 # bit     61 (User Linear Address Masking: bits 62:57 are masked)
    lam48enable*  {.bitsize:  1.}: uint64 # bit     62 (User Linear Address Masking: bits 62:48 are masked)
    reserved2*    {.bitsize:  1.}: uint64 # bit     63

  # Page Map Level 4 Entry (maps 1 PDPTable = 512 GiB of virtual memory)
  PML4Entry* {.packed.} = object
    present*      {.bitsize:  1.}: uint64     # bit      0
    write*        {.bitsize:  1.}: uint64     # bit      1
    user*         {.bitsize:  1.}: uint64     # bit      2
    writeThrough* {.bitsize:  1.}: uint64     # bit      3
    cacheDisable* {.bitsize:  1.}: uint64     # bit      4
    accessed*     {.bitsize:  1.}: uint64     # bit      5
    ignored1*     {.bitsize:  1.}: uint64     # bit      6
    reserved1*    {.bitsize:  1.}: uint64     # bit      7
    ignored2*     {.bitsize:  4.}: uint64     # bits 11: 8
    physAddress*  {.bitsize: 40.}: uint64     # bits 51:12  (-> PDPTable)
    osdata*       {.bitsize: 11.}: uint64     # bits 62:52  OS-specific data (ignored by MMU)
    xd*           {.bitsize:  1.}: uint64     # bit     63

  # Page Directory Pointer Table Entry (maps 1 PDTablel = 1 GiB of virtual memory)
  PDPTEntry* {.packed.} = object
    present*      {.bitsize:  1.}: uint64     # bit      0
    write*        {.bitsize:  1.}: uint64     # bit      1
    user*         {.bitsize:  1.}: uint64     # bit      2
    writeThrough* {.bitsize:  1.}: uint64     # bit      3
    cacheDisable* {.bitsize:  1.}: uint64     # bit      4
    accessed*     {.bitsize:  1.}: uint64     # bit      5
    ignored1*     {.bitsize:  1.}: uint64     # bit      6
    pageSize*     {.bitsize:  1.}: uint64 = 0 # bit      7
    ignored2*     {.bitsize:  4.}: uint64     # bits 11: 8
    physAddress*  {.bitsize: 40.}: uint64     # bits 51:12  (-> PDTable)
    osdata*       {.bitsize: 11.}: uint64     # bits 62:52  OS-specific data (ignored by MMU)
    xd*           {.bitsize:  1.}: uint64     # bit     63

  # Page Directory Pointer Table Entry (maps a single 1 GiB page)
  PDPTEntry1GB* {.packed.} = object
    present*      {.bitsize:  1.}: uint64     # bit      0
    write*        {.bitsize:  1.}: uint64     # bit      1
    user*         {.bitsize:  1.}: uint64     # bit      2
    writeThrough* {.bitsize:  1.}: uint64     # bit      3
    cacheDisable* {.bitsize:  1.}: uint64     # bit      4
    accessed*     {.bitsize:  1.}: uint64     # bit      5
    dirty*        {.bitsize:  1.}: uint64     # bit      6
    pageSize*     {.bitsize:  1.}: uint64 = 1 # bit      7
    global*       {.bitsize:  1.}: uint64     # bit      8  (no TLB flush on PCID switch)
    ignored2*     {.bitsize:  3.}: uint64     # bits 11: 9
    pat*          {.bitsize:  1.}: uint64     # bit     12
    reserved*     {.bitsize: 17.}: uint64     # bit  29:13
    physAddress*  {.bitsize: 22.}: uint64     # bits 51:30  -> 1 GiB page, or VMO id (if present=0)
    osdata*       {.bitsize: 11.}: uint64     # bits 62:52  OS-specific data (ignored by MMU)
    xd*           {.bitsize:  1.}: uint64     # bit     63

  # Page Directory Entry (maps 1 PTable = 2 MiB of virtual memory)
  PDEntry* {.packed.} = object
    present*      {.bitsize:  1.}: uint64     # bit      0
    write*        {.bitsize:  1.}: uint64     # bit      1
    user*         {.bitsize:  1.}: uint64     # bit      2
    writeThrough* {.bitsize:  1.}: uint64     # bit      3
    cacheDisable* {.bitsize:  1.}: uint64     # bit      4
    accessed*     {.bitsize:  1.}: uint64     # bit      5
    ignored1*     {.bitsize:  1.}: uint64     # bit      6
    pageSize*     {.bitsize:  1.}: uint64 = 0 # bit      7
    ignored2*     {.bitsize:  4.}: uint64     # bits 11: 8
    physAddress*  {.bitsize: 40.}: uint64     # bits 51:12  (-> PTable)
    osdata*       {.bitsize: 11.}: uint64     # bits 62:52  OS-specific data (ignored by MMU)
    xd*           {.bitsize:  1.}: uint64     # bit     63

  # Page Directory Entry (maps a single 2 MiB page)
  PDEntry2M* {.packed.} = object
    present*      {.bitsize:  1.}: uint64     # bit      0
    write*        {.bitsize:  1.}: uint64     # bit      1
    user*         {.bitsize:  1.}: uint64     # bit      2
    writeThrough* {.bitsize:  1.}: uint64     # bit      3
    cacheDisable* {.bitsize:  1.}: uint64     # bit      4
    accessed*     {.bitsize:  1.}: uint64     # bit      5
    dirty*        {.bitsize:  1.}: uint64     # bit      6
    pageSize*     {.bitsize:  1.}: uint64 = 1 # bit      7
    global*       {.bitsize:  1.}: uint64     # bit      8  (no TLB flush on PCID switch)
    ignored2*     {.bitsize:  3.}: uint64     # bits 11: 9
    pat*          {.bitsize:  1.}: uint64     # bit     12
    reserved*     {.bitsize:  8.}: uint64     # bit  20:13
    physAddress*  {.bitsize: 31.}: uint64     # bits 51:21  -> 2 MiB page, or VMO id (if present=0)
    osdata*       {.bitsize: 11.}: uint64     # bits 62:52  OS-specific data (ignored by MMU)
    xd*           {.bitsize:  1.}: uint64     # bit     63

  # Page Table Entry (maps a single 4 KiB page)
  PTEntry* {.packed.} = object
    present*      {.bitsize:  1.}: uint64     # bit      0
    write*        {.bitsize:  1.}: uint64     # bit      1
    user*         {.bitsize:  1.}: uint64     # bit      2
    writeThrough* {.bitsize:  1.}: uint64     # bit      3
    cacheDisable* {.bitsize:  1.}: uint64     # bit      4
    accessed*     {.bitsize:  1.}: uint64     # bit      5
    dirty*        {.bitsize:  1.}: uint64     # bit      6
    pat*          {.bitsize:  1.}: uint64     # bit      7
    global*       {.bitsize:  1.}: uint64     # bit      8  (no TLB flush on PCID switch)
    ignored2*     {.bitsize:  3.}: uint64     # bits 11: 9
    physAddress*  {.bitsize: 40.}: uint64     # bits 51:12  -> 4 KiB page, or VMO id (if present=0)
    osdata*       {.bitsize: 11.}: uint64     # bits 62:52  OS-specific data (ignored by MMU)
    xd*           {.bitsize:  1.}: uint64     # bit     63

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

# Ideally we shouldn't need to define an `entries` array field within each object,
# and we could just define the tables directly as arrays, like so:
#
# PML4Table* {.align(PageSize).} = array[512, PML4Entry]
#
# Then we could access the table by indexing directly into its variable, e.g.
# pml4[i], instead of pml4.entries[i]. Unfortunately Nim doesn't support type-level
# alignment (yet). (See this RFC https://github.com/nim-lang/RFCs/issues/545).
#
# So, as a workaround, we define index operators for each table type, which just
# forward the indexing to the entries array.

proc `[]`*(pml4: ptr PML4Table; index: uint64): var PML4Entry {.inline.} = pml4.entries[index]
proc `[]`*(pdpt: ptr PDPTable; index: uint64): var PDPTEntry {.inline.} = pdpt.entries[index]
proc `[]`*(pd: ptr PDTable; index: uint64): var PDEntry {.inline.} = pd.entries[index]
proc `[]`*(pt: ptr PTable; index: uint64): var PTEntry {.inline.} = pt.entries[index]

proc len*(pml4: PML4Table): int {.inline.} = pml4.entries.len
proc len*(pdpt: PDPTable): int {.inline.} = pdpt.entries.len
proc len*(pd: PDTable): int {.inline.} = pd.entries.len
proc len*(pt: PTable): int {.inline.} = pt.entries.len

## CR3 get/set

proc getCR3*(): CR3 {.inline.} =
  var reg: uint64
  asm """
    mov %0, cr3
    : "=r"(`reg`)
  """
  result = cast[CR3](reg)

proc setCR3*(cr3: CR3) {.inline.} =
  asm """
    mov r15, cr3
    cmp r15, %0
    jz .done
    mov cr3, %0
  .done:
    :
    : "r"(`cr3`)
    : "r15"
  """

proc newCR3*(pml4addr: PAddr): CR3 {.inline.} =
  result = CR3(physAddress: pml4addr.uint64 shr 12)

proc pml4addr*(cr3: CR3): PAddr {.inline.} =
  result = PAddr(cr3.physAddress.uint64 shl 12)

proc paddr*(entry: PML4Entry | PDPTEntry | PDEntry | PTEntry): PAddr {.inline.} =
  result = PAddr(entry.physAddress.uint64 shl 12)

proc paddr*(entry: ptr PML4Entry | ptr PDPTEntry | ptr PDEntry | ptr PTEntry): PAddr {.inline.} =
  result = PAddr(entry.physAddress.uint64 shl 12)

proc `paddr=`*(e: var PML4Entry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: ptr PML4Entry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: var PDPTEntry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: ptr PDPTEntry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: var PDEntry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: ptr PDEntry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: var PTEntry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
proc `paddr=`*(e: ptr PTEntry, paddr: PAddr | uint64) {.inline.} = e.physAddress = paddr.uint64 shr 12
