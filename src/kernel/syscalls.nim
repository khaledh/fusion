import std/strformat

import debugcon
import cpu
import gdt
import tasks

type
  SyscallHandler = proc (args: ptr SyscallArgs): uint64 {.cdecl.}
  SyscallArgs = object
    num: uint64
    arg1, arg2, arg3, arg4, arg5: uint64
  SyscallError* = enum
    None
    InvalidSyscall
    InvalidArg

const
  UserAddrSpaceEnd* = 0x00007FFFFFFFFFFF'u64

var
  syscallTable: array[256, SyscallHandler]
  currentTask {.importc.}: Task

proc syscallEntry() {.asmNoStackFrame.} =
  asm """
    # switch to kernel stack
    mov %0, rsp
    mov rsp, %1

    push r11  # user rflags
    push rcx  # user rip

    # create syscall frame
    push r9
    push r8
    push rcx
    push rdx
    push rsi
    push rdi

    mov rdi, rsp
    call syscall

    # pop stack frame
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop r8
    pop r9

    # prepare for sysret
    pop rcx  # rip
    pop r11  # rflags

    # switch to user stack
    mov rsp, %0

    sysretq
    : "+r"(`currentTask`->rsp)
    : "m"(`currentTask`->kstack.bottom)
    : "rcx", "r11", "rdi", "rsi", "rdx", "rcx", "r8", "r9", "rax"
  """

proc syscall(args: ptr SyscallArgs): uint64 {.exportc.} =
  debugln &"syscall: num={args.num}"
  if args.num > syscallTable.high.uint64 or syscallTable[args.num] == nil:
    return InvalidSyscall.uint64
  result = syscallTable[args.num](args)

proc exit*(args: ptr SyscallArgs): uint64 {.cdecl.} =
  debugln &"syscall: exit: code={args.arg1}"
  asm """
    cli
    hlt
  """

proc print*(args: ptr SyscallArgs): uint64 {.cdecl.} =
  debugln "syscall: print"

  if args.arg1 > UserAddrSpaceEnd:
    debugln "syscall: print: Invalid pointer"
    return InvalidArg.uint64

  # debugln &"syscall: print: arg1={args.arg1:#x}"
  # debugln &"syscall: print: arg1[0]={cast[ptr uint64](args.arg1)[]:#x}"
  # debugln &"syscall: print: arg1[1]={cast[ptr uint64](args.arg1 + 8)[]:#x}"

  let s = cast[ptr string](args.arg1)
  debugln s[]

  result = 0


proc syscallInit*() =
  # set up syscall table
  syscallTable[1] = exit
  syscallTable[2] = print

  # enable syscall feature
  writeMSR(IA32_EFER, readMSR(IA32_EFER) or 1)  # Bit 0: SYSCALL Enable

  # set up segment selectors in IA32_STAR (Syscall Target Address Register)
  # note that for SYSCALL:
  #   CS: IA32_STAR[47:32]
  #   SS: IA32_STAR[47:32] + 8
  # and for SYSRET:
  #   CS: IA32_STAR[63:48] + 16
  #   SS: IA32_STAR[63:48] + 8
  # thus, setting both parts of the register to KernelCodeSegmentSelector
  # satisfies both requirements (+0 is kernrel CS, +8 is data segment, +16 is user CS)
  let star = (
    (KernelCodeSegmentSelector.uint64 shl 32) or
    (KernelCodeSegmentSelector.uint64 shl 48)
  )
  writeMSR(IA32_STAR, star)

  # set up syscall entry point
  writeMSR(IA32_LSTAR, cast[uint64](syscallEntry))

  # set up flags mask (should mask interrupt flag to disable interrupts)
  writeMSR(IA32_FMASK, 0x200)  # rflags will be ANDed with the *complement* of this value
