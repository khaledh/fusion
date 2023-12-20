import common/malloc
import common/pagetables


####################################################################################################
# Map a single page
####################################################################################################

proc mapPage*(
  pml4: PML4Table,
  virtAddr: uint64,
  physAddr: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode
) =
  var pml4Index = (virtAddr shr 39) and 0x1FF
  var pdptIndex = (virtAddr shr 30) and 0x1FF
  var pdIndex = (virtAddr shr 21) and 0x1FF
  var ptIndex = (virtAddr shr 12) and 0x1FF

  let access = cast[uint64](pageAccess)
  let mode = cast[uint64](pageMode)

  var pdpt: PDPTable
  var pd: PDTable
  var pt: PTable

  # Page Map Level 4 Table
  if pml4.entries[pml4Index].present == 1:
    pdpt = cast[PDPTable](cast[uint64](pml4.entries[pml4Index].physAddress) shl 12)
  else:
    pdpt = new PDPTable
    pml4.entries[pml4Index].physAddress = cast[uint64](pdpt.entries.addr) shr 12
    pml4.entries[pml4Index].write = access
    pml4.entries[pml4Index].user = mode
    pml4.entries[pml4Index].present = 1

  # Page Directory Pointer Table
  if pdpt.entries[pdptIndex].present == 1:
    pd = cast[PDTable](cast[uint64](pdpt.entries[pdptIndex].physAddress) shl 12)
  else:
    pd = new PDTable
    pdpt.entries[pdptIndex].physAddress = cast[uint64](pd.entries.addr) shr 12
    pdpt.entries[pdptIndex].write = access
    pdpt.entries[pdptIndex].user = mode
    pdpt.entries[pdptIndex].present = 1

  # Page Directory
  if pd.entries[pdIndex].present == 1:
    pt = cast[PTable](cast[uint64](pd.entries[pdIndex].physAddress) shl 12)
  else:
    pt = new PTable
    pd.entries[pdIndex].physAddress = cast[uint64](pt.entries.addr) shr 12
    pd.entries[pdIndex].write = access
    pd.entries[pdIndex].user = mode
    pd.entries[pdIndex].present = 1

  # Page Table
  pt.entries[ptIndex].physAddress = physAddr shr 12
  pt.entries[ptIndex].write = access
  pt.entries[ptIndex].user = mode
  pt.entries[ptIndex].present = 1


####################################################################################################
# Map a range of pages
####################################################################################################

proc mapPages*(
  pml4: PML4Table,
  virtAddr: uint64,
  physAddr: uint64,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode
) =
  for i in 0 ..< pageCount:
    mapPage(pml4, virtAddr + i * PageSize, physAddr + i * PageSize, pageAccess, pageMode)

proc identityMapPages*(
  pml4: PML4Table,
  physAddr: uint64,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode
) =
  mapPages(pml4, physAddr, physAddr, pageCount, pageAccess, pageMode)

####################################################################################################
# Install a page table into CR3
####################################################################################################

type
  CR3 = object
    ignored1 {.bitsize: 3.}: uint64 = 0
    writeThrough {.bitsize: 1.}: uint64 = 0
    cacheDisable {.bitsize: 1.}: uint64 = 0
    ignored2 {.bitsize: 7.}: uint64 = 0
    physAddress {.bitsize: 40.}: uint64
    ignored3 {.bitsize: 12.}: uint64 = 0

proc installPageTable*(pml4: PML4Table) =
  let cr3obj = CR3(physAddress: cast[uint64](pml4.entries.addr) shr 12)
  let cr3 = cast[uint64](cr3obj)
  asm """
    mov cr3, %0
    :
    : "r"(`cr3`)
  """
