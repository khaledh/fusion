#[
  System calls
]#

import common/serde
import channels
import cpu
import gdt
import sched
import task
import taskmgr

import syslib/syscalldef

type
  SyscallHandler = proc (args: ptr SyscallArgs): int

  SyscallArgs = object
    num: uint64   # rdi
    arg1: uint64  # rsi
    arg2: uint64  # rdx
    arg3: uint64  # r8
    arg4: uint64  # r9
    arg5: uint64  # r10

  SyscallError* = enum
    InvalidSyscall = -99
    InvalidArg     = -1
    None           = 0

const
  UserAddrSpaceEnd* = 0x00007FFFFFFFFFFF'u64
  MaxMessageBatchSize* = 1024

let
  logger = DebugLogger(name: "syscall")

var
  syscallTable: array[1024, SyscallHandler]
  currentTask {.importc.}: Task


###############################################################################
# Syscall entry point
###############################################################################

proc syscallEntry() {.asmNoStackFrame.} =
  asm """
    # save user stack pointer
    mov %0, rsp

    # switch to kernel stack
    mov rsp, %1

    push r11  # user rflags
    push rcx  # user rip

    # create SyscallArgs on the stack
    push r10
    push r9
    push r8
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
    pop r8
    pop r9
    pop r10

    # prepare for sysretq
    pop rcx  # user rip
    pop r11  # user rflags

    # switch to user stack
    mov rsp, %0

    sysretq
    : "+r"(`currentTask`->rsp)
    : "m"(`currentTask`->kstack.bottom)
    : "rcx", "r11", "rdi", "rsi", "rdx", "r8", "r9", "r10"
  """

proc syscall(args: ptr SyscallArgs): int {.exportc.} =
  if args.num > syscallTable.high.uint64 or syscallTable[args.num] == nil:
    return InvalidSyscall.int
  result = syscallTable[args.num](args)


###############################################################################
# Syscalls
###############################################################################

###
# Get Task ID
###
proc getTaskId*(args: ptr SyscallArgs): int =
  ##
  ## Get the current task ID.
  ##
  ## Arguments:
  ##   None
  ##
  ## Returns:
  ##   The task ID.
  ##
  ## Side effects:
  ##   None
  ##
  logger.info &"[tid:{getCurrentTask().id}] getTaskId"
  result = getCurrentTask().id.int

###
# Yield
###
proc `yield`*(args: ptr SyscallArgs): int =
  ##
  ## Yield the CPU to another task.
  ##
  ## Arguments:
  ##   None
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   The current task is moved to the ready queue.
  ##
  logger.info &"[tid:{getCurrentTask().id}] yield"
  schedule()

###
# Suspend
###
proc suspend*(args: ptr SyscallArgs): int =
  ##
  ## Suspend the current task.
  ##
  ## Arguments:
  ##   None
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   The current task is suspended. It can only be resumed by another task.
  ##
  logger.info &"[tid:{getCurrentTask().id}] suspend"
  suspend()

###
# Sleep
###
proc sleep*(args: ptr SyscallArgs): int =
  ##
  ## Sleep for a given number of milliseconds.
  ##
  ## Arguments:
  ##  arg1 (in): number of milliseconds to sleep
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##  The current task will be suspended for the given number of milliseconds.
  ##
  logger.info &"[tid:{getCurrentTask().id}] sleep: ms={args.arg1}"
  sleep(args.arg1)

###
# Exit
###
proc exit*(args: ptr SyscallArgs): int =
  ##
  ## Exit the current task.
  ##
  ## Arguments:
  ##   arg1 (in): exit code
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   The current task will be terminated.
  ##
  logger.info &"[tid:{getCurrentTask().id}] exit: code={args.arg1}"
  terminate()

###
# ChannelCreate
###
proc channelCreate*(args: ptr SyscallArgs): int =
  ##
  ## Create a channel for a task.
  ##
  ## Arguments:
  ##   arg1 (in): mode (0 = read, 1 = write)
  ##   arg2 (in): message size
  ## 
  ## Returns:
  ##   The channel id
  ##   -1 on error
  ##
  ## Side effects:
  ##   A channel will be created.
  ##
  let currentTask = getCurrentTask()
  let mode = args.arg1.int
  if mode < ChannelMode.low.int or mode > ChannelMode.high.int:
    return InvalidArg.int
  let chMode = ChannelMode(mode)
  let msgSize = args.arg2.int
  logger.info &"[tid:{currentTask.id}] channelCreate: mode={mode}, msgSize={msgSize}"
  let ret = channels.createUserChannel(currentTask, chMode, msgSize = msgSize)
  if ret < 0:
    return InvalidArg.int
  args.arg1 = ret.uint64

###
# ChannelOpen
###
proc channelOpen*(args: ptr SyscallArgs): int =
  ##
  ## Open a channel for a task in a specific mode. Map the buffer to the task's address space.
  ##
  ## Arguments:
  ##   arg1 (in): channel id
  ##   arg2 (in): mode (0 = read, 1 = write)
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   The channel buffer will be mapped to the task's address space.
  ##
  let chid = args.arg1.int
  let mode = args.arg2.int
  if mode < ChannelMode.low.int or mode > ChannelMode.high.int:
    return InvalidArg.int
  
  let chMode = ChannelMode(mode)

  let currentTask = getCurrentTask()
  logger.info &"[tid:{currentTask.id}] channelOpen: chid={chid}, mode={mode}"
  let ret = openUserChannel(chid, currentTask, chMode)
  if ret < 0:
    return InvalidArg.int

###
# ChannelClose
###
proc channelClose*(args: ptr SyscallArgs): int =
  ##
  ## Close a channel for a task. Unmap the buffer from the task's address space.
  ##
  ## Arguments:
  ##   arg1 (in): channel id
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   The channel buffer will be unmapped from the task's address space.
  ##
  let chid = args.arg1.int
  logger.info &"[tid:{getCurrentTask().id}] channelClose: chid={chid}"
  let ret = close(chid, getCurrentTask())
  if ret < 0:
    return InvalidArg.int

###
# ChannelAlloc
###
proc channelAlloc*(args: ptr SyscallArgs): int =
  ##
  ## Allocate memory in a channel buffer.
  ##
  ## Arguments:
  ##   arg1 (in): channel id
  ##   arg2 (in): size to allocate
  ##   arg3 (out): pointer to the allocated memory
  ##
  ## Returns:
  ##   The address of the allocated memory
  ##   -1 on error
  ##
  ## Side effects:
  ##   A block of memory will be allocated in the channel buffer.
  ##
  let chid = args.arg1.int
  let len = args.arg2.int
  logger.info &"[tid:{getCurrentTask().id}] channelAlloc: chid={chid}, len={len}"
  let p = channels.alloc(chid, len)
  if p.isNil:
    # TODO: return proper error code
    return InvalidArg.int
  args.arg3 = cast[uint64](p)

###
# ChannelSend
###
proc channelSend*(args: ptr SyscallArgs): int =
  ##
  ## Send data to a channel
  ## 
  ## Arguments:
  ##   arg1 (in): channel id
  ##   arg2 (in): data pointer
  ##   arg3 (in): data length
  ##
  ## Returns:
  ##  0 on success
  ## -1 on error
  ##
  ## Side effects:
  ##   If the channel is full, the task will be blocked until there is space in the channel.
  ##
  let chid = args.arg1.int
  let data = cast[pointer](args.arg2)
  let len = args.arg3.int

  logger.info &"[tid:{getCurrentTask().id}] channelSend: chid={chid}, len={len}, data @ {cast[uint64](data):#x}"
  let ret = send(chid, len, data)
  if ret < 0:
    return InvalidArg.int

###
# ChannelSendBatch
###
proc channelSendBatch*(args: ptr SyscallArgs): int =
  ##
  ## Send data to a channel in a batch
  ## Arguments:
  ##   arg1 (in): channel id
  ##   arg2 (in): pointer to a MessageBatch object
  ##   arg3 (in): length of the MessageBatch object
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   If the channel is full, the task will be blocked until there is space in the channel.
  ##
  let chid = args.arg1.int
  let batch = cast[ptr MessageBatch](args.arg2)
  let len = args.arg3.int
  if batch.isNil or len > MaxMessageBatchSize:
    return InvalidArg.int

  # send each message in the batch
  for i in 0 ..< batch.count:
    let msg = batch.messages[i]
    let ret = send(chid, msg.len, msg.data)
    if ret < 0:
      return InvalidArg.int

###
# ChannelRecv
###
proc channelRecv*(args: ptr SyscallArgs): int =
  ##
  ## Receive data from a channel
  ##
  ## Arguments:
  ##   arg1 (in): channel id
  ##   arg2 (out): buffer pointer
  ##   arg3 (out): buffer length
  ##
  ## Returns:
  ##   0 on success
  ##  -1 on error
  ##
  ## Side effects:
  ##   If the channel is empty, the task will be blocked until there is data in the channel.
  ##
  let chid = args.arg1.int
  var buf = cast[pointer](args.arg2)
  var len = args.arg3.int
  logger.info &"[tid:{getCurrentTask().id}] channelRecv: chid={chid}"
  let ret = recv(chid, buf, len)
  if ret < 0:
    return InvalidArg.int

###
# Print
###
proc print*(args: ptr SyscallArgs): int =
  ##
  ## Print a string to the console.
  ##
  ## Arguments:
  ##   arg1 (in): pointer to a Nim string object.
  ##
  ## Returns:
  ##   None
  ##
  ## Side effects:
  ##   The string will be printed to the console.
  ##
  logger.info &"[tid:{getCurrentTask().id}] print"
  # logger.info &"print: arg1.len = {cast[ptr uint64](args.arg1)[]}"
  # logger.info &"print: arg1.p   = {cast[ptr uint64](args.arg1 + 8)[]:#x}"
  if args.arg1 > UserAddrSpaceEnd:
    # logger.info "print: Invalid pointer"
    return InvalidArg.int

  let s = cast[ptr string](args.arg1)
  logger.raw "\n"
  logger.raw s[]
  logger.raw "\n"
  logger.raw "\n"


###############################################################################
# Initialization
###############################################################################

proc syscallInit*() =
  # set up syscall table
  syscallTable[SysGetTaskId] = getTaskId
  syscallTable[SysYield] = `yield`
  syscallTable[SysSuspend] = suspend
  syscallTable[SysSleep] = sleep
  syscallTable[SysExit] = exit

  syscallTable[SysChannelCreate] = channelCreate
  syscallTable[SysChannelOpen] = channelOpen
  syscallTable[SysChannelClose] = channelClose
  syscallTable[SysChannelSend] = channelSend
  syscallTable[SysChannelSendBatch] = channelSendBatch
  syscallTable[SysChannelRecv] = channelRecv
  syscallTable[SysChannelAlloc] = channelAlloc

  syscallTable[SysPrint] = print

  # enable syscall feature
  writeMSR(IA32_EFER, readMSR(IA32_EFER) or 1)  # Bit 0: SYSCALL Enable

  # set up segment selectors in IA32_STAR (Syscall Target Address Register)
  #
  # we use KernelCodeSegmentSelector for both parts of the register (47:32 and 63:48)
  # so for SYSCALL, the kernel segment selectors are:
  #   CS: IA32_STAR[47:32]         <-- KernelCodeSegmentSelector
  #   SS: IA32_STAR[47:32] + 8     <-- DataSegmentSelector (shared)
  #
  # and for SYSRET, the user segment selectors are:
  #   CS: IA32_STAR[63:48] + 16    <-- UserCodeSegmentSelector
  #   SS: IA32_STAR[63:48] + 8     <-- DataSegmentSelector (shared)
  #
  # thus, setting both parts of the register to KernelCodeSegmentSelector
  # satisfies both requirements (+0 is kernel CS, +8 is shared data segment, +16 is user CS)
  let star = (
    (KernelCodeSegmentSelector.uint64 shl 32) or
    (KernelCodeSegmentSelector.uint64 shl 48)
  )
  writeMSR(IA32_STAR, star)

  # set up syscall entry point
  writeMSR(IA32_LSTAR, cast[uint64](syscallEntry))

  # set up flags mask (should mask interrupt flag to disable interrupts)
  writeMSR(IA32_FMASK, 0x200)  # rflags will be ANDed with the *complement* of this value
