const
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
    :"=a"(`eax`), "=d"(`edx`)
    :"c"(`ecx`)
  """
  result = (edx.uint64 shl 32) or eax

proc writeMSR*(ecx: uint32, value: uint64) =
  var eax, edx: uint32
  eax = value.uint32
  edx = (value shr 32).uint32
  asm """
    wrmsr
    :
    :"a"(`eax`), "d"(`edx`), "c"(`ecx`)
  """
