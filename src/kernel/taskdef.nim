#[
  Task data structures
]#

import common/pagetables
import vmm

type
  TaskStack* = object
    data*: ptr UncheckedArray[uint64]
    size*: uint64
    bottom*: uint64

  Task* = ref object
    rsp*: uint64  # must be first field (inline assembly in ctxswitch expects this)
    id*: uint64
    state*: TaskState
    # user task fields
    vmRegions*: seq[VMRegion]
    pml4*: ptr PML4Table
    ustack*: TaskStack
    kstack*: TaskStack
    isUser*: bool
  
  TaskState* = enum
    New
    Ready
    Running
    Terminated

  TaskRegs* {.packed.} = object
    r15*, r14*, r13*, r12*, r11*, r10*, r9*, r8*: uint64
    rbp*, rdi*, rsi*, rdx*, rcx*, rbx*, rax*: uint64

  InterruptStackFrame* {.packed.} = object
    rip*, cs*, rflags*, rsp*, ss*: uint64
