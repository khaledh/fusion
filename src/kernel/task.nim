#[
  Task data structures
]#

import common/pagetables
import vmdefs

const
  InitialQuantumMs = 20  # 20ms

type
  TaskStack* = object
    data*: ptr UncheckedArray[uint64]
    size*: uint64
    bottom*: uint64
    vmMapping*: VmMapping

  Task* = ref object
    rsp*: uint64  # must be first field (inline assembly in ctxswitch expects this)
    id*: uint64
    name*: string
    priority*: TaskPriority
    state*: TaskState
    remainingQuantumMs*: uint64 = InitialQuantumMs
    sleepUntil*: uint64  # based on apic timer count
    # user task fields
    vmMappings*: seq[VmMapping]
    pml4*: ptr PML4Table
    ustack*: TaskStack
    kstack*: TaskStack
    isUser*: bool
  
  TaskPriority* = range[-8..7]

  TaskState* = enum
    New
    Ready
    Running
    Suspended
    Sleeping
    Terminated

  TaskRegs* {.packed.} = object
    r15*, r14*, r13*, r12*, r11*, r10*, r9*, r8*: uint64
    rbp*, rdi*, rsi*, rdx*, rcx*, rbx*, rax*: uint64

  InterruptStackFrame* {.packed.} = object
    rip*, cs*, rflags*, rsp*, ss*: uint64


proc `$`*(t: Task): string =
  return $t.id & " \"" & t.name & "\""
