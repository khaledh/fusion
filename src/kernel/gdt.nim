type
  CodeSegmentDescriptor* {.packed.} = object
    limit00: uint16 = 0xffff
    base00: uint16 = 0
    base16: uint8 = 0
    accessed* {.bitsize: 1.}: uint8 = 0
    readable* {.bitsize: 1.}: uint8 = 1
    conforming* {.bitsize: 1.}: uint8 = 0
    code {.bitsize: 1.}: uint8 = 1
    s {.bitsize: 1.}: uint8 = 1
    dpl* {.bitsize: 2.}: uint8
    p* {.bitsize: 1.}: uint8 = 1
    limit16 {.bitsize: 4.}: uint8 = 0xf
    avl* {.bitsize: 1.}: uint8 = 0
    l {.bitsize: 1.}: uint8 = 1
    d {.bitsize: 1.}: uint8 = 0
    g {.bitsize: 1.}: uint8 = 0
    base24: uint8 = 0

  DataSegmentDescriptor* {.packed.} = object
    limit00: uint16 = 0xffff
    base00: uint16 = 0
    base16: uint8 = 0
    accessed* {.bitsize: 1.}: uint8 = 0
    writable* {.bitsize: 1.}: uint8 = 1
    expandDown* {.bitsize: 1.}: uint8 = 0
    code {.bitsize: 1.}: uint8 = 0
    s {.bitsize: 1.}: uint8 = 1
    dpl* {.bitsize: 2.}: uint8
    p* {.bitsize: 1.}: uint8 = 1
    limit16 {.bitsize: 4.}: uint8 = 0xf
    avl* {.bitsize: 1.}: uint8 = 0
    l {.bitsize: 1.}: uint8 = 0
    b {.bitsize: 1.}: uint8 = 0
    g {.bitsize: 1.}: uint8 = 0
    base24: uint8 = 0

  TaskStateSegmentDescriptor {.packed.} = object
    limit00: uint16
    base00: uint16
    base16: uint8
    `type`* {.bitsize: 4.}: uint8 = 0b1001  # 64-bit TSS
    s {.bitsize: 1.}: uint8 = 0  # System segment
    dpl* {.bitsize: 2.}: uint8
    p* {.bitsize: 1.}: uint8 = 1
    limit16 {.bitsize: 4.}: uint8
    avl* {.bitsize: 1.}: uint8 = 0
    zero1 {.bitsize: 1.}: uint8 = 0
    zero2 {.bitsize: 1.}: uint8 = 0
    g {.bitsize: 1.}: uint8 = 0
    base24: uint8
    base32: uint32
    reserved1: uint8 = 0
    zero3 {.bitsize: 5.}: uint8 = 0
    reserved2 {.bitsize: 19.}: uint32 = 0

  SegmentDescriptorValue = distinct uint32

  SegmentDescriptor =
    CodeSegmentDescriptor |
    DataSegmentDescriptor |
    SegmentDescriptorValue

  TaskStateSegment {.packed.} = object
    reserved0: uint32
    rsp0*: uint64
    rsp1: uint64
    rsp2: uint64
    reserved1: uint64
    ist1: uint64
    ist2: uint64
    ist3: uint64
    ist4: uint64
    ist5: uint64
    ist6: uint64
    ist7: uint64
    reserved2: uint64
    reserved3: uint16
    iomapBase: uint16

  GdtDescriptor* {.packed.} = object
    limit*: uint16
    base*: pointer

const
  NullSegmentDescriptor* = SegmentDescriptorValue(0)

proc value*(sd: SegmentDescriptor): uint64 =
  result = cast[uint64](sd)

###############################################################################
# GDT initialization
###############################################################################

const
  KernelCodeSegmentSelector* = 0x08
  DataSegmentSelector* = 0x10 or 3     # RPL = 3
  UserCodeSegmentSelector* = 0x18 or 3 # RPL = 3
  TaskStateSegmentSelector* = 0x20


var
  tss* = TaskStateSegment()

  tssDescriptor = TaskStateSegmentDescriptor(
    dpl: 0,
    base00: cast[uint16](tss.addr),
    base16: cast[uint8](cast[uint64](tss.addr) shr 16),
    base24: cast[uint8](cast[uint64](tss.addr) shr 24),
    base32: cast[uint32](cast[uint64](tss.addr) shr 32),
    limit00: cast[uint16](sizeof(tss) - 1),
    limit16: cast[uint8]((sizeof(tss) - 1) shr 16)
  )
  tssDescriptorLo = cast[uint64](tssDescriptor)
  tssDescriptorHi = (cast[ptr uint64](cast[uint64](tssDescriptor.addr) + 8))[]

  gdtEntries = [
    NullSegmentDescriptor.value,
    CodeSegmentDescriptor(dpl: 0).value, # Kernel code segment
    DataSegmentDescriptor(dpl: 3).value, # Data segment
    CodeSegmentDescriptor(dpl: 3).value, # User code segment
    tssDescriptorLo,                     # Task state segment (low 64 bits)
    tssDescriptorHi,                     # Task state segment (high 64 bits)
  ]

  gdtDescriptor = GdtDescriptor(
    limit: sizeof(gdtEntries) - 1,
    base: gdtEntries.addr
  )


proc gdtInit*() {.asmNoStackFrame.} =
  # Ideally we would use a far jump here to reload the CS register, but support
  # for 64-bit far jumps (`JMP m16:64`) is not supported by the LLVM integrated
  # assembler. It's also only supported by Intel processors, not AMD. So we use
  # a far return instead.
  asm """
    lgdt %0

    mov ax, %3
    ltr ax

    # reload CS using a far return
    lea rax, [rip + 1f]
    push %1    # cs
    push rax   # rip
    retfq

  1:
    # reload data segment registers
    mov rax, %2
    mov ds, rax
    mov es, rax
    mov fs, rax
    mov gs, rax

    # set SS to NULL
    xor rax, rax
    mov ss, rax
    :
    : "m"(`gdtDescriptor`),
      "i"(`KernelCodeSegmentSelector`),
      "i"(`DataSegmentSelector`),
      "i"(`TaskStateSegmentSelector`)
    : "rax" 
  """
