#[
  System calls
]#

import channels
import cpu
import gdt
import sched
import taskdef
import taskmgr

import syslib/syscalldef

type
  SyscallHandler = proc (args: ptr SyscallArgs): int {.cdecl.}
  SyscallArgs = object
    num: uint64
    arg1, arg2, arg3, arg4, arg5: uint64
  SyscallError* = enum
    InvalidArg     = -2
    InvalidSyscall = -1
    None           = 0

const
  UserAddrSpaceEnd* = 0x00007FFFFFFFFFFF'u64

var
  syscallTable: array[1024, SyscallHandler]
  currentTask {.importc.}: Task

proc syscallEntry() {.asmNoStackFrame.} =
  asm """
    # save user stack pointer
    mov %0, rsp

    # switch to kernel stack
    mov rsp, %1

    push r11  # user rflags
    push rcx  # user rip

    # create SyscallArgs on the stack
    push r9
    push r8
    push rcx
    push rdx
    push rsi
    push rdi

    # rsp is now pointing to SyscallArgs, pass it to syscall
    mov rdi, rsp
    call syscall

    # pop SyscallArgs
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop r8
    pop r9

    # prepare for sysretq
    pop rcx  # user rip
    pop r11  # user rflags

    # switch to user stack
    mov rsp, %0

    sysretq
    : "+r"(`currentTask`->rsp)
    : "m"(`currentTask`->kstack.bottom)
    : "rcx", "r11", "rdi", "rsi", "rdx", "rcx", "r8", "r9", "rax"
  """

proc syscall(args: ptr SyscallArgs): int {.exportc.} =
  # debugln &"syscall: num={args.num}"
  if args.num > syscallTable.high.uint64 or syscallTable[args.num] == nil:
    return InvalidSyscall.int
  result = syscallTable[args.num](args)

###############################################################################
# Syscalls
###############################################################################

###
# Get Task ID
###
proc getTaskId*(args: ptr SyscallArgs): int {.cdecl.} =
  debugln &"syscall: getTaskId"
  result = getCurrentTask().id.int

###
# Yield
###
proc `yield`*(args: ptr SyscallArgs): int {.cdecl.} =
  debugln &"syscall: yield"
  schedule()

###
# Suspend
###
proc suspend*(args: ptr SyscallArgs): int {.cdecl.} =
  debugln &"syscall: suspend"
  suspend()

###
# Exit
###
proc exit*(args: ptr SyscallArgs): int {.cdecl.} =
  debugln &"syscall: exit: code={args.arg1}"
  terminate()


###
# ChannelSend
###
proc channelSend*(args: ptr SyscallArgs): int {.cdecl.} =
  let chid = args.arg1
  let data = args.arg2
  debugln &"syscall: channelSend: chid={chid}, data={data}"
  send(chid.int, data.int)

###
# ChannelRecv
###
proc channelRecv*(args: ptr SyscallArgs): int {.cdecl.} =
  let chid = args.arg1
  debugln &"syscall: channelRecv: chid={chid}"
  result = recv(chid.int)
  debugln &"syscall: channelRecv: result={result}"

###
# Print
###
proc print*(args: ptr SyscallArgs): int {.cdecl.} =
  debugln &"syscall: print"
  # debugln &"syscall: print: arg1.len = {cast[ptr uint64](args.arg1)[]}"
  # debugln &"syscall: print: arg1.p   = {cast[ptr uint64](args.arg1 + 8)[]:#x}"
  if args.arg1 > UserAddrSpaceEnd:
    # debugln "syscall: print: Invalid pointer"
    return InvalidArg.int

  let s = cast[ptr string](args.arg1)
  debugln s[]

  result = 0

proc syscallInit*() =
  # set up syscall table
  syscallTable[SysGetTaskId] = getTaskId
  syscallTable[SysYield] = `yield`
  syscallTable[SysSuspend] = suspend
  syscallTable[SysExit] = exit

  syscallTable[SysChannelSend] = channelSend
  syscallTable[SysChannelRecv] = channelRecv

  syscallTable[SysPrint] = print

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
