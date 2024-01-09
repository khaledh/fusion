import std/strformat

import debugcon
import cpu
import gdt

type
  SyscallFrame = object
    num: uint64
    arg1, arg2, arg3, arg4, arg5: uint64

var
  kernelStack: array[4096, byte]
  kernelStackEnd = cast[uint64](kernelStack.addr) + kernelStack.len.uint64
  userStackPtr: uint64

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
    : "+r"(`userStackPtr`)
    : "m"(`kernelStackEnd`)
    : "rcx", "r11", "rdi", "rsi", "rdx", "rcx", "r8", "r9"
  """

proc syscall(frame: ptr SyscallFrame): uint64 {.exportc.} =
  debugln &"syscall: num={frame.num}"
  let s = cast[ptr string](frame.arg1)
  debugln s[]
  debugln &"syscall: returning"


proc syscallInit*() =
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
