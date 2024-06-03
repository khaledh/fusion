#[
  CPU related functions and constants
]#

const
  IA32_APIC_BASE* = 0x1B'u32

  IA32_EFER* = 0xC0000080'u32

  IA32_STAR* = 0xC0000081'u32
  IA32_LSTAR* = 0xC0000082'u32
  IA32_FMASK* = 0xC0000084'u32

  IA32_FS_BASE* = 0xC0000100'u32
  IA32_GS_BASE* = 0xC0000101'u32
  IA32_KERNEL_GS_BASE* = 0xC0000102'u32


proc readMSR*(ecx: uint32): uint64 =
  var eax, edx: uint32
  asm """
    rdmsr
    : "=a"(`eax`), "=d"(`edx`)
    : "c"(`ecx`)
  """
  result = (edx.uint64 shl 32) or eax

proc writeMSR*(ecx: uint32, value: uint64) =
  var eax, edx: uint32
  eax = value.uint32
  edx = (value shr 32).uint32
  asm """
    wrmsr
    :
    : "c"(`ecx`), "a"(`eax`), "d"(`edx`)
  """

proc cpuid*(eax, ebx, ecx, edx: ptr uint32) =
  asm """
    cpuid
    :"=a"(*`eax`), "=b"(*`ebx`), "=c"(*`ecx`), "=d"(*`edx`)
    :"a"(*`eax`)
  """

proc readTSC*(): uint64 =
  var eax, edx: uint32
  asm """
    rdtsc
    : "=a"(`eax`), "=d"(`edx`)
  """
  result = (edx.uint64 shl 32) or eax

proc getCpuidFreq*(): tuple[tscFreq: uint32, apicFreq: uint32] =
  # get the local apic frequency and tsc frequency
  # on real machines: leaf 0x16
  # on virtual machines: leaf 0x40000010
  var eax, ebx, ecx, edx: uint32
  eax = 0x40000010
  cpuid(addr eax, addr ebx, addr ecx, addr edx)
  result = (
    eax * 1_000,  # TSC frequency (convert KHz to Hz)
    ebx * 1_000,  # APIC frequency (convert KHz to Hz)
  )

proc idle*() {.cdecl.} =
  while true:
    asm """
      sti
      hlt
    """

proc halt*() =
  asm """
  .loop:
    cli
    hlt
    jmp .loop
  """

template pushRegs*() =
  asm """
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
  """

template popRegs*() =
  asm """
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
  """

proc disableInterrupts*() {.inline.} =
  asm "cli"

proc enableInterrupts*() {.inline.} =
  asm "sti"
