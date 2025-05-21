import std/[strformat, strutils]

import common/pagetables
import idt
import cpu
import task
import vmdefs, vmpagetbl

let
  logger = DebugLogger(name: "pageflt")

type
  PageFaultP* = enum
    pfPageNonPresent = (0, "Page non present")
    pfPageLevelProtectionViolation = (1, "")

  PageFaultRW* = enum
    pfReadAccess = (0, "Read")
    pfWriteAccess = (1, "Write")

  PageFaultUS* = enum
    pfSupervisorAccess = (0, "Supervisor")
    pfUserAccess = (1, "User")
  
  PageFaultRSVD* = enum
    pfReservedOK = (0, "")
    pfReservedBitSet = (1, "Reserved bit set")

  PageFaultID* = enum
    pfDataAccess = (0, "")
    pfInstructionFetch = (1, "Instruction fetch")

  PageFaultErrorCode* = object
    p {.bitsize: 1.}: PageFaultP
    rw {.bitsize: 1.}: PageFaultRW
    us {.bitsize: 1.}: PageFaultUS
    rsvd {.bitsize: 1.}: PageFaultRSVD
    inst {.bitsize: 1.}: PageFaultID

proc `$`*(errorCode: PageFaultErrorCode): string =
  var parts: seq[string]
  parts &= $errorCode.us
  if errorCode.p == pfPageNonPresent:
    parts &= $errorCode.p
  if errorCode.rw == pfWriteAccess or (errorCode.rw == pfReadAccess and errorCode.inst != pfInstructionFetch):
    parts &= $errorCode.rw
  if errorCode.inst != pfDataAccess:
    parts &= $errorCode.inst
  if errorCode.rsvd != pfReservedOK:
    parts &= $errorCode.rsvd
  result = parts.join(", ")

var
  currentTask {.importc.}: Task
  pageFaultCount: uint64
  defaultPageFaultHandler: Option[InterruptHandlerWithErrorCode]

proc terminate() {.importc.}

proc printRegisters(frame: ptr InterruptFrame) {.inline.} =
  logger.info "  Interrupt Frame:"
  logger.info &"      IP: {frame.ip:#018x}"
  logger.info &"      CS: {frame.cs:#018x}"
  logger.info &"   Flags: {frame.flags:#018x}"
  logger.info &"      SP: {frame.sp:#018x}"
  logger.info &"      SS: {frame.ss:#018x}"
  logger.info ""

proc pageFaultHandler*(frame: ptr InterruptFrame, errorCode: uint64)
  {.cdecl, codegenDecl: "__attribute__ ((interrupt)) $# $#$#".} =
  let taskId = if currentTask.isNil: "kernel" else: $currentTask.id

  # get the faulting address
  let cr2 = readCR2()
  logger.info &"Page fault at: {cr2:#010x}, task: {taskId}, error code: [{errorCode:#010b}] {cast[PageFaultErrorCode](errorCode)}"

  # get the page aligned faulting address
  let vaddr = VAddr(cr2 and not 0xfff'u64)

  let vmMappings = if currentTask.isNil: kvmMappings else: currentTask.vmMappings

  # print task vm mappings
  # logger.info &"    Task VM mappings length: {vmMappings.len}"
  # for mapping_debug in vmMappings:
  #   let vmoid = if mapping_debug.vmo.isNil: "nil" else: $mapping_debug.vmo.id
  #   logger.info &"        {mapping_debug.region.start.uint64:#x} - {mapping_debug.region.end.uint64:#x} (VMO ID: {vmoid}) {mapping_debug.permissions}"

  # find the vm mapping that contains the faulting address
  var vmMappingOpt: Option[VmMapping] = none(VmMapping)
  for mapping in vmMappings:
    if vaddr >= mapping.region.start and vaddr < mapping.region.end:
      vmMappingOpt = some(mapping)
      break

  if vmMappingOpt.isNone:
    logger.info &"Page fault at {cr2:#018x} but no VmMapping found for task {taskId}. Terminating task."
    # print the mappings
    for mapping in vmMappings:
      logger.info &"    {mapping.region.start.uint64:#x} - {mapping.region.end.uint64:#x} (VMO ID: {mapping.vmo.id})"
    # TODO: Terminate current task
    printRegisters(frame)
    quit()

  let vmMapping = vmMappingOpt.get
  # logger.info &"    VM mapping found: {vmMapping.region.start.uint64:#x} - {vmMapping.region.end.uint64:#x} (VMO ID: {vmMapping.vmo.id})"

  # Check for protection violation (e.g. writing to a read-only segment)
  let faultErrorCode = cast[PageFaultErrorCode](errorCode)
  if faultErrorCode.rw == pfWriteAccess and not (pWrite in vmMapping.permissions):
    logger.info &"Page fault: Write attempt to read-only mapping at {cr2:#018x} for task {taskId}. Terminating task."
    # print the mappings
    for mapping in vmMappings:
      logger.info &"    {mapping.region.start.uint64:#x} - {mapping.region.end.uint64:#x} (VMO ID: {mapping.vmo.id}) {mapping.permissions}"
    # TODO: Terminate current task
    # For now, quit (i.e. halt)
    printRegisters(frame)
    terminate()

  if faultErrorCode.inst == pfInstructionFetch and not (pExecute in vmMapping.permissions):
    logger.info &"Page fault: Execute attempt at non-executable mapping at {cr2:#018x} for task {taskId}. Terminating task."
    # print the mappings
    for mapping in vmMappings:
      logger.info &"    {mapping.region.start.uint64:#x} - {mapping.region.end.uint64:#x} (VMO ID: {mapping.vmo.id}) {mapping.permissions}"
    # TODO: Terminate current task
    # For now, quit (i.e. halt)
    printRegisters(frame)
    quit()

  # delegate to the VMO to fault in the page
  case vmMapping.vmo.kind:
  of vmObjectPageable, vmObjectElfSegment:
    let offsetInVmo = vaddr.uint64 - vmMapping.region.start.uint64
    # logger.info &"    Offset within VMO: {offsetInVmo:#x}"
    
    # Call the VmObject's pager procedure
    let pagedInPAddr = vmMapping.vmo.pager(vmMapping.vmo, offsetInVmo, 1'u64)

    if pagedInPAddr.uint64 == 0:
        logger.info &"Page fault: VMO.pager failed (returned null PAddr) for {cr2:#018x}, VMO ID {vmMapping.vmo.id}. Terminating task."
        # TODO: Terminate current task
        # For now, quit (i.e. halt)
        # printRegisters(frame)
        quit()

    # Update the page table entry
    let endVAddr = vaddr +! PageSize.uint64 # walkPageTable is exclusive for endVAddr
    
    # let write: uint64 = if pWrite in vmMapping.permissions: 1 else: 0
    # let user: uint64 = if vmMapping.privilege == pUser: 1 else: 0
    # let xd: uint64 = if pExecute in vmMapping.permissions: 0 else: 1
    # let osdata = VmMappingOsData(mapped: 1)

    let pml4 = if currentTask.isNil: kpml4 else: currentTask.pml4
    # Flags other than `present` were already set in the initial mapping
    walkPageTable(pml4, vaddr, endVAddr, PageTableWalker(
      processPTEntry: proc (pte: ptr PTEntry, idx: PageTableIndex) =
        pte.present = 1
        pte.paddr = pagedInPAddr
        # Invalidate the TLB for this page
        let vaddrToInvalidate = indexToVAddr(idx).uint64
        asm """
          invlpg [%0]
          :
          : "r"(`vaddrToInvalidate`)
          : "memory"
        """
        # logger.info &"  PTEntry updated. Present: {pte.present}, PAddr: {pte.paddr.uint64:#x}"
    ))
    # dumpPageTable(currentTask.pml4, maxVaddr = 0x00007f0000000000'u64.VAddr) # After
    # logger.info &"Page fault handled for {cr2:#018x}. Resuming task {taskId}."
    # if cr2 == 0x000000000000fa30:
    #   asm """
    #     cli
    #     hlt
    #   """

  of vmObjectPinned:
    logger.info &"Page fault at {cr2:#018x} for a VmObjectPinned. This should not happen if correctly mapped. VMO ID {vmMapping.vmo.id}"
    # This indicates an issue, as pinned objects should have their pages present.
    # For now, quit (i.e. halt)
    printRegisters(frame)
    quit()


proc initPageFaultHandler*() =
  # Set the page fault handler
  defaultPageFaultHandler = installHandlerWithErrorCode(
    vector = 14,
    handler = pageFaultHandler,
  )
