#[
  CPU related functions and constants
]#

import debugcon

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

proc readTSC*(): uint64 =
  var eax, edx: uint32
  asm """
    rdtsc
    : "=a"(`eax`), "=d"(`edx`)
  """
  result = (edx.uint64 shl 32) or eax

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

########################################################
# CPUID
########################################################

proc cpuid*(eax, ebx, ecx, edx: ptr uint32) =
  asm """
    cpuid
    :"+a"(*`eax`), "=b"(*`ebx`), "=c"(*`ecx`), "=d"(*`edx`)
  """

type
  CpuIdFeaturesEcx {.packed.} = object
    sse3        {.bitsize: 1.}: uint32  #  0: SSE3 Extensions
    pclmulqdq   {.bitsize: 1.}: uint32  #  1: PCLMULQDQ Instruction (Carryless Multiplication)
    dtes64      {.bitsize: 1.}: uint32  #  2: 64-bit DS Area
    monitor     {.bitsize: 1.}: uint32  #  3: MONITOR/MWAIT
    dscpl       {.bitsize: 1.}: uint32  #  4: CPL Qualified Debug Store
    vmx         {.bitsize: 1.}: uint32  #  5: Virtual Machine eXtensions
    smx         {.bitsize: 1.}: uint32  #  6: Safer Mode Extensions
    eist        {.bitsize: 1.}: uint32  #  7: Enhanced Intel SpeedStep Technology
    tm2         {.bitsize: 1.}: uint32  #  8: Thermal Monitor 2
    ssse3       {.bitsize: 1.}: uint32  #  9: Supplemental SSE3 Instructions
    cnxtid      {.bitsize: 1.}: uint32  # 10: L1 Context ID
    sdbg        {.bitsize: 1.}: uint32  # 11: IA32_DEBUG_INTERFACE MSR for silicon debug
    fma         {.bitsize: 1.}: uint32  # 12: Fused Multiply Add (FMA) extensions using YMM state
    cmpxchg16b  {.bitsize: 1.}: uint32  # 13: CMPXCHG16B Available
    xtprupdctl  {.bitsize: 1.}: uint32  # 14: XTPR Update Control
    pdcm        {.bitsize: 1.}: uint32  # 15: PerfMon and Debug Capability MSR
    res1        {.bitsize: 1.}: uint32  # 16: Reserved
    pcid        {.bitsize: 1.}: uint32  # 17: Process-context identifiers
    dca         {.bitsize: 1.}: uint32  # 18: Direct Cache Access (prefetch data from a memory mapped device)
    sse41       {.bitsize: 1.}: uint32  # 19: SSE4.1 Extensions
    sse42       {.bitsize: 1.}: uint32  # 20: SSE4.2 Extensions
    x2apic      {.bitsize: 1.}: uint32  # 21: x2APIC
    movbe       {.bitsize: 1.}: uint32  # 22: MOVBE instruction
    popcnt      {.bitsize: 1.}: uint32  # 23: POPCNT instruction
    tscdeadline {.bitsize: 1.}: uint32  # 24: APIC Timer TSC Deadline
    aesni       {.bitsize: 1.}: uint32  # 25: AESNI instruction extensions
    xsave       {.bitsize: 1.}: uint32  # 26: XSAVE/XRSTOR, XSETBV/XGETBV instructions, and XCR0
    osxsave     {.bitsize: 1.}: uint32  # 27: OS has set CR4.OSXSAVE to enable XSETBV/XGETBV to access XCR0
    avx         {.bitsize: 1.}: uint32  # 28: AVX instruction extensions
    f16c        {.bitsize: 1.}: uint32  # 29: 16-bit floating-point conversion instructions
    rdrand      {.bitsize: 1.}: uint32  # 30: RDRAND instruction
    unused      {.bitsize: 1.}: uint32  # 31: Not Used (always returns 0)

  CpuIdFeaturesEdx {.packed.} = object
    fpu         {.bitsize: 1.}: uint32  #  0: Floating-Point Unit On-Chip
    vme         {.bitsize: 1.}: uint32  #  1: Virtual 8086 Mode Enhancements
    de          {.bitsize: 1.}: uint32  #  2: Debugging Extensions
    pse         {.bitsize: 1.}: uint32  #  3: Page Size Extensions
    tsc         {.bitsize: 1.}: uint32  #  4: Time Stamp Counter
    msr         {.bitsize: 1.}: uint32  #  5: Model-Specific Registers RDMSR/WRMSR Instructions
    pae         {.bitsize: 1.}: uint32  #  6: Physical Address Extension
    mce         {.bitsize: 1.}: uint32  #  7: Machine Check Exception
    cx8         {.bitsize: 1.}: uint32  #  8: CMPXCHG8B Instruction
    apic        {.bitsize: 1.}: uint32  #  9: APIC On-Chip
    res1        {.bitsize: 1.}: uint32  # 10: Reserved
    sep         {.bitsize: 1.}: uint32  # 11: SYSENTER and SYSEXIT Instructions
    mtrr        {.bitsize: 1.}: uint32  # 12: Memory Type Range Registers
    pge         {.bitsize: 1.}: uint32  # 13: Page Global Bit
    mca         {.bitsize: 1.}: uint32  # 14: Machine Check Architecture
    cmov        {.bitsize: 1.}: uint32  # 15: Conditional Move Instructions
    pat         {.bitsize: 1.}: uint32  # 16: Page Attribute Table
    pse36       {.bitsize: 1.}: uint32  # 17: 36-Bit Page Size Extension
    psn         {.bitsize: 1.}: uint32  # 18: Processor Serial Number
    clfsh       {.bitsize: 1.}: uint32  # 19: CLFLUSH Instruction
    res2        {.bitsize: 1.}: uint32  # 20: Reserved
    ds          {.bitsize: 1.}: uint32  # 21: Debug Store
    acpi        {.bitsize: 1.}: uint32  # 22: Thermal Monitor and Software Controlled Clock Facilities
    mmx         {.bitsize: 1.}: uint32  # 23: Intel MMX Technology
    fxsr        {.bitsize: 1.}: uint32  # 24: FXSAVE and FXSTOR Instructions
    sse         {.bitsize: 1.}: uint32  # 25: SSE Extensions
    sse2        {.bitsize: 1.}: uint32  # 26: SSE2 Extensions
    ss          {.bitsize: 1.}: uint32  # 27: Self Snoop
    htt         {.bitsize: 1.}: uint32  # 28: Max APIC IDs reserved field is valid
    tm          {.bitsize: 1.}: uint32  # 29: Thermal Monitor
    res3        {.bitsize: 1.}: uint32  # 30: Reserved
    pbe         {.bitsize: 1.}: uint32  # 31: Pending Break Enable

const
  CpuIdFeaturesEcxDesc = [
    "SSE3",
    "PCLMULQDQ",
    "64-bit DS Area",
    "MONITOR/MWAIT",
    "CPL Qualified Debug Store",
    "Virtual Machine Extensions",
    "Safer Mode Extensions",
    "Enhanced Intel SpeedStep Technology",
    "Thermal Monitor 2",
    "Supplemental SSE3 Instructions",
    "L1 Context ID",
    "IA32_DEBUG_INTERFACE MSR for silicon debug",
    "Fused Multiply Add (FMA) extensions using YMM state",
    "CMPXCHG16B Available",
    "XTPR Update Control",
    "PerfMon and Debug Capability MSR",
    "",
    "Process-context identifiers",
    "Direct Cache Access (prefetch data from a memory mapped device)",
    "SSE4.1 Extensions",
    "SSE4.2 Extensions",
    "x2APIC",
    "MOVBE instruction",
    "POPCNT instruction",
    "APIC Timer TSC Deadline",
    "AESNI instruction extensions",
    "XSAVE/XRSTOR, XSETBV/XGETBV instructions, and XCR0",
    "OS has set CR4.OSXSAVE to enable XSETBV/XGETBV to access XCR0",
    "AVX instruction extensions",
    "16-bit floating-point conversion instructions",
    "RDRAND instruction",
    "",
  ]

  CpuIdFeaturesEdxDesc = [
    "Floating-Point Unit On-Chip",
    "Virtual 8086 Mode Enhancements",
    "Debugging Extensions",
    "Page Size Extensions",
    "Time Stamp Counter",
    "Model-Specific Registers RDMSR/WRMSR Instructions",
    "Physical Address Extension",
    "Machine Check Exception",
    "CMPXCHG8B Instruction",
    "APIC On-Chip",
    "",
    "SYSENTER and SYSEXIT Instructions",
    "Memory Type Range Registers",
    "Page Global Bit",
    "Machine Check Architecture",
    "Conditional Move Instructions",
    "Page Attribute Table",
    "36-Bit Page Size Extension",
    "Processor Serial Number",
    "CLFLUSH Instruction",
    "",
    "Debug Store",
    "Thermal Monitor and Software Controlled Clock Facilities",
    "Intel MMX Technology",
    "FXSAVE and FXSTOR Instructions",
    "SSE Extensions",
    "SSE2 Extensions",
    "Self Snoop",
    "Max APIC IDs reserved field is valid",
    "Thermal Monitor",
    "",
    "Pending Break Enable",
  ]

proc showCpuid*() =
  var eax, ebx, ecx, edx: uint32

  ## Function 0

  eax = 0
  cpuid(addr eax, addr ebx, addr ecx, addr edx)

  proc registerToString(reg: uint32): string =
    result &= cast[char](reg shr 00)
    result &= cast[char](reg shr 08)
    result &= cast[char](reg shr 16)
    result &= cast[char](reg shr 24)

  var vendor: string
  vendor &= registerToString(ebx)
  vendor &= registerToString(edx)
  vendor &= registerToString(ecx)

  debugln("")
  debugln("CPUID")
  debugln(&"  Vendor:                    {vendor}")
  debugln(&"  Highest Basic Function:    {eax:0>2x}h")

  ## Extended Function 0x80000000

  eax = 0x80000000'u32
  cpuid(addr eax, addr ebx, addr ecx, addr edx)
  debugln(&"  Highest Extended Function: {eax:0>2x}h")

  ## QEMU

  eax = 0x40000000'u32
  cpuid(addr eax, addr ebx, addr ecx, addr edx)
  vendor = registerToString(ebx)
  vendor &= registerToString(edx)
  vendor &= registerToString(ecx)
  debug(&"  Hypervisor:                {vendor}")
  if vendor == "TCGTGTCGCGTC":
    debugln(" (QEMU)")
  elif vendor == "KVMKVMKVM\0\0\0":
    debugln(" (KVM)")
  else:
    debugln("")
  debugln(&"  Heighest HV Function:      {eax:0>2x}h")

  debugln("")

  ## Check invariant TSC. EDX Bit 08: Invariant TSC available if 1.

  eax = 0x80000007'u32
  cpuid(addr eax, addr ebx, addr ecx, addr edx)
  if (edx and (1 shl 8).uint32) != 0:
    debugln(&"  Invariant TSC:             Yes")
  else:
    debugln(&"  Invariant TSC:             No")

  ## Check TSC/core clock ratio using 0x15
  ## If EBX[31:0] is 0, the TSC/”core crystal clock” ratio is not enumerated.
  ## EBX[31:0]/EAX[31:0] indicates the ratio of the TSC frequency and the core crystal clock frequency.
  ## If ECX is 0, the nominal core crystal clock frequency is not enumerated.
  ## “TSC frequency” = “core crystal clock frequency” * EBX/EAX.
  ## The core crystal clock may differ from the reference clock, bus clock, or core clock frequencies.
  ## EAX: Bits 31-00: An unsigned integer which is the denominator of the TSC/”core crystal clock” ratio.
  ## EBX: Bits 31-00: An unsigned integer which is the numerator of the TSC/”core crystal clock” ratio.
  ## ECX: Bits 31-00: An unsigned integer which is the nominal frequency of the core crystal clock in Hz.
  ## EDX: Bits 31-00: Reserved = 0.

  eax = 0x15'u32
  cpuid(addr eax, addr ebx, addr ecx, addr edx)
  if ecx != 0:
    debugln(&"  Core crystal clock freq:   {ecx:0>2x}h Hz")
  else:
    debugln(&"  Core crystal clock freq:   Not enumerated")
  if ebx == 0:
    debugln(&"  TSC/core clock ratio:      Not enumerated")
  else:
    debugln(&"  TSC/core clock ratio:      {ebx:0>2x}h/{eax:0>2x}h")

  ## Processor Frequency Information Leaf (Initial EAX Value = 16H)
  ## 16H EAX Bits 15-00: Processor Base Frequency (in MHz).
  ## Bits 31-16: Reserved =0.
  ## EBX ECX Bits 15-00: Maximum Frequency (in MHz).
  ## Bits 31-16: Reserved = 0.
  ## Bits 15-00: Bus (Reference) Frequency (in MHz).
  ## Bits 31-16: Reserved = 0.
  ## EDX Reserved.

  eax = 0x16'u32
  cpuid(addr eax, addr ebx, addr ecx, addr edx)
  debugln(&"  Processor Base Frequency:  {eax:0>2x}h MHz")
  debugln(&"  Maximum Frequency:         {ebx:0>2x}h MHz")
  debugln(&"  Bus Frequency:             {ecx:0>2x}h MHz")

  ## Function 1

  eax = 1
  cpuid(addr eax, addr ebx, addr ecx, addr edx)

  var procType = (eax shr 12) and 0x3
  var family = eax shr 8 and 0xf
  if family == 0xf:
    family = (eax shr 20 and 0xff) + family
  var model = eax shr 4 and 0xf
  if family in [0x6.uint32, 0xf]:
    model += (eax shr 16 and 0xf) shl 4
  var stepping = eax and 0xf

  debugln("")
  debugln(&"  Processor Type:            {procType:0>2x}h")
  debugln(&"  Family ID:                 {family:0>2x}h")
  debugln(&"  Model ID:                  {model:0>2x}h")
  debugln(&"  Stepping ID:               {stepping:1x}h")

  debugln("")
  # debugln(&"  Feature Info in ECX: {cast[CpuIdFeaturesEcx](ecx)}")
  # debugln(&"  Feature Info in EDX: {cast[CpuIdFeaturesEdx](edx)}")

  for i in 0..31:
    if CpuIdFeaturesEcxDesc[i] == "": continue
    if (ecx and (1 shl i).uint32) != 0:
      # green color
      debugln(&"\e[32m  ✓ {CpuIdFeaturesEcxDesc[i]}\e[0m")
    else:
      # dark grey color
      debugln(&"\e[90m  ✗ {CpuIdFeaturesEcxDesc[i]}\e[0m")

  debugln("")

  for i in 0..31:
    if CpuIdFeaturesEdxDesc[i] == "": continue
    if (edx and (1 shl i).uint32) != 0:
      # green color
      debugln(&"\e[32m  ✓ {CpuIdFeaturesEdxDesc[i]}\e[0m")
    else:
      # dark grey color
      debugln(&"\e[90m  ✗ {CpuIdFeaturesEdxDesc[i]}\e[0m")

  debugln("")
