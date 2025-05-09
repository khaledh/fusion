#[
  OS library functions
]#

include syscalldef

# Note: `rcx` and `r11` are changed by the CPU during the syscall:
# - rcx is used to save return address
# - r11 is used to save the rflags register
#
# That's why we tell the compiler that these registers are clobbered.

proc getTaskId*(): int =
  asm """
    syscall
    : "=a" (`result`)
    : "D" (`SysGetTaskId`)
    : "rcx", "r11", "memory"
  """

proc yld*() =
  asm """
    syscall
    :
    : "D" (`SysYield`)
    : "rcx", "r11", "memory"
  """

proc suspend*() =
  asm """
    syscall
    :
    : "D" (`SysSuspend`)
    : "rcx", "r11", "memory"
  """

proc sleep*(durationMs: uint64) =
  asm """
    syscall
    :
    : "D" (`SysSleep`),
      "S" (`durationMs`)
    : "rcx", "r11", "memory"
  """

proc exit*(code: int = 0) =
  asm """
    syscall
    :
    : "D" (`SysExit`),
      "S" (`code`)
    : "rcx", "r11", "memory"
  """
