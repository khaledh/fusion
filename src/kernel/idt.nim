#[
  x86_64 Interrupt Descriptor Table (IDT)
]#

import debugcon
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

  InterruptHandler = proc (frame: pointer) {.cdecl.}

var
  idtEntries: array[256, InterruptGate]

let
  idtDescriptor = IdtDescriptor(
    limit: uint16(sizeof(idtEntries) - 1),
    base: idtEntries.addr
  )

proc newInterruptGate(handler: InterruptHandler, dpl: uint8 = 0): InterruptGate =
  let offset = cast[uint64](handler)
  result = InterruptGate(
    offset00: uint16(offset),
    offset16: uint16(offset shr 16),
    offset32: uint32(offset shr 32),
    dpl: dpl,
  )

proc installHandler*(vector: uint8, handler: InterruptHandler, dpl: uint8 = 0) =
  idtEntries[vector] = newInterruptGate(handler, dpl)

proc cpuPageFaultHandler*(frame: pointer) {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
  debugln ""
  debugln "CPU Exception: Page Fault"
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

template createHandler*(name: untyped, msg: string) =
  proc name*(frame: pointer) {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
    debugln ""
    debugln "CPU Exception: ", msg
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
createHandler(cpuDoubleFaultHandler, "Double Fault")
createHandler(cpuCoprocessorSegmentOverrunHandler, "Coprocessor Segment Overrun")
createHandler(cpuInvalidTssHandler, "Invalid TSS")
createHandler(cpuSegmentNotPresentHandler, "Segment Not Present")
createHandler(cpuStackSegmentFaultHandler, "Stack Segment Fault")
createHandler(cpuGeneralProtectionFaultHandler, "General Protection Fault")
createHandler(cpuX87FloatingPointErrorHandler, "x87 Floating Point Error")
createHandler(cpuAlignmentCheckHandler, "Alignment Check")
createHandler(cpuMachineCheckHandler, "Machine Check")
createHandler(cpuSimdFloatingPointExceptionHandler, "SIMD Floating Point Exception")
createHandler(cpuVirtualizationExceptionHandler, "Virtualization Exception")
createHandler(cpuControlProtectionExceptionHandler, "Control Protection Exception")

proc idtInit*() =
  installHandler(0, cpuDivideErrorHandler)
  installHandler(1, cpuDebugErrorHandler)
  installHandler(2, cpuNmiInterruptHandler)
  installHandler(3, cpuBreakpointHandler)
  installHandler(4, cpuOverflowHandler)
  installHandler(5, cpuBoundRangeExceededHandler)
  installHandler(6, cpuInvalidOpcodeHandler)
  installHandler(7, cpuDeviceNotAvailableHandler)
  installHandler(8, cpuDoubleFaultHandler)
  installHandler(9, cpuCoprocessorSegmentOverrunHandler)
  installHandler(10, cpuInvalidTssHandler)
  installHandler(11, cpuSegmentNotPresentHandler)
  installHandler(12, cpuStackSegmentFaultHandler)
  installHandler(13, cpuGeneralProtectionFaultHandler)
  installHandler(14, cpuPageFaultHandler)
  installHandler(16, cpuX87FloatingPointErrorHandler)
  installHandler(17, cpuAlignmentCheckHandler)
  installHandler(18, cpuMachineCheckHandler)
  installHandler(19, cpuSimdFloatingPointExceptionHandler)
  installHandler(20, cpuVirtualizationExceptionHandler)
  installHandler(21, cpuControlProtectionExceptionHandler)

  asm """
    lidt %0
    :
    : "m"(`idtDescriptor`)
  """
