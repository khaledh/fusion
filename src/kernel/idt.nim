#[
  x86_64 Interrupt Descriptor Table (IDT)
]#

import gdt

type
  InterruptGate {.packed.} = object
    offset00: uint16
    selector: uint16 = KernelCodeSegmentSelector
    ist {.bitsize: 3.}: uint8 = 0
    zero0 {.bitsize: 5.}: uint8 = 0
    `type` {.bitsize: 4.}: uint8 = 0b1110
    zero1 {.bitsize: 1.}: uint8 = 0
    dpl {.bitsize: 2.}: uint8 = 0
    present {.bitsize: 1.}: uint8 = 1
    offset16: uint16
    offset32: uint32
    reserved: uint32 = 0

  IdtDescriptor {.packed.} = object
    limit: uint16
    base: pointer

  InterruptHandler = proc (frame: ptr InterruptFrame) {.cdecl.}
  InterruptHandlerWithErrorCode = proc (frame: ptr InterruptFrame, errorCode: uint64) {.cdecl.}

  InterruptFrame* {.packed.} = object
    ip*: uint64
    cs*: uint64
    flags*: uint64
    sp*: uint64
    ss*: uint64

var
  idtEntries: array[256, InterruptGate]

let
  idtDescriptor = IdtDescriptor(
    limit: uint16(sizeof(idtEntries) - 1),
    base: idtEntries.addr
  )

proc newInterruptGate(handler: pointer, dpl: uint8 = 0): InterruptGate =
  let offset = cast[uint64](handler)
  result = InterruptGate(
    offset00: uint16(offset),
    offset16: uint16(offset shr 16),
    offset32: uint32(offset shr 32),
    dpl: dpl,
  )

proc installHandler*(vector: uint8, handler: InterruptHandler, dpl: uint8 = 0) =
  idtEntries[vector] = newInterruptGate(handler, dpl)

proc installHandlerWithErrorCode*(vector: uint8, handler: InterruptHandlerWithErrorCode, dpl: uint8 = 0) =
  idtEntries[vector] = newInterruptGate(handler, dpl)

proc cpuPageFaultHandler*(frame: ptr InterruptFrame, errorCode: uint64)
  {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
  debugln ""
  debugln &"CPU Exception: Page Fault (Error Code: {errorCode:#x})"
  # get the faulting address
  var cr2: uint64
  asm """
    mov %0, cr2
    : "=r"(`cr2`)
  """
  debugln &"    Faulting address: {cr2:#018x}"
  debugln ""
  debugln getStackTrace()
  quit()

proc cpuGeneralProtectionFaultHandler*(frame: ptr InterruptFrame, errorCode: uint64)
  {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
  debugln ""
  debugln &"CPU Exception: General Protection Fault (Error Code: {errorCode:#x})"
  debugln ""
  debugln "  Interrupt Frame:"
  debugln &"    IP: {frame.ip:#018x}"
  debugln &"    CS: {frame.cs:#018x}"
  debugln &"    Flags: {frame.flags:#018x}"
  debugln &"    SP: {frame.sp:#018x}"
  debugln &"    SS: {frame.ss:#018x}"
  debugln ""
  debugln getStackTrace()
  quit()


template createHandler*(name: untyped, msg: string) =
  proc name*(frame: ptr InterruptFrame) {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
    debugln ""
    debugln "CPU Exception: ", msg
    debugln ""
    debugln getStackTrace()
    quit()

template createHandlerWithErrorCode*(name: untyped, msg: string) =
  proc name*(frame: ptr InterruptFrame, errorCode: uint64)
    {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
    debugln ""
    debugln &"CPU Exception: ", msg, " (Error Code: {errorCode})"
    debugln ""
    debugln getStackTrace()
    quit()

createHandler(cpuDivideErrorHandler, "Divide Error")
createHandler(cpuDebugErrorHandler, "Debug Exception")
createHandler(cpuNmiInterruptHandler, "NMI Interrupt")
createHandler(cpuBreakpointHandler, "Breakpoint")
createHandler(cpuOverflowHandler, "Overflow")
createHandler(cpuBoundRangeExceededHandler, "Bound Range Exceeded")
createHandler(cpuInvalidOpcodeHandler, "Invalid Opcode")
createHandler(cpuDeviceNotAvailableHandler, "Device Not Available")
createHandlerWithErrorCode(cpuDoubleFaultHandler, "Double Fault")
createHandler(cpuCoprocessorSegmentOverrunHandler, "Coprocessor Segment Overrun")
createHandler(cpuInvalidTssHandler, "Invalid TSS")
createHandlerWithErrorCode(cpuSegmentNotPresentHandler, "Segment Not Present")
createHandlerWithErrorCode(cpuStackSegmentFaultHandler, "Stack Segment Fault")
# General Protection Fault is handled separately
# Page Fault is handled separately
createHandler(cpuX87FloatingPointErrorHandler, "x87 Floating Point Error")
createHandlerWithErrorCode(cpuAlignmentCheckHandler, "Alignment Check")
createHandler(cpuMachineCheckHandler, "Machine Check")
createHandler(cpuSimdFloatingPointExceptionHandler, "SIMD Floating Point Exception")
createHandler(cpuVirtualizationExceptionHandler, "Virtualization Exception")
createHandlerWithErrorCode(cpuControlProtectionExceptionHandler, "Control Protection Exception")

proc idtInit*() =
  installHandler(0, cpuDivideErrorHandler)
  installHandler(1, cpuDebugErrorHandler)
  installHandler(2, cpuNmiInterruptHandler)
  installHandler(3, cpuBreakpointHandler)
  installHandler(4, cpuOverflowHandler)
  installHandler(5, cpuBoundRangeExceededHandler)
  installHandler(6, cpuInvalidOpcodeHandler)
  installHandler(7, cpuDeviceNotAvailableHandler)
  installHandlerWithErrorCode(8, cpuDoubleFaultHandler)
  installHandler(9, cpuCoprocessorSegmentOverrunHandler)
  installHandler(10, cpuInvalidTssHandler)
  installHandlerWithErrorCode(11, cpuSegmentNotPresentHandler)
  installHandlerWithErrorCode(12, cpuStackSegmentFaultHandler)
  installHandlerWithErrorCode(13, cpuGeneralProtectionFaultHandler)
  installHandlerWithErrorCode(14, cpuPageFaultHandler)
  installHandler(16, cpuX87FloatingPointErrorHandler)
  installHandlerWithErrorCode(17, cpuAlignmentCheckHandler)
  installHandler(18, cpuMachineCheckHandler)
  installHandler(19, cpuSimdFloatingPointExceptionHandler)
  installHandler(20, cpuVirtualizationExceptionHandler)
  installHandlerWithErrorCode(21, cpuControlProtectionExceptionHandler)

  asm """
    lidt %0
    :
    : "m"(`idtDescriptor`)
  """
