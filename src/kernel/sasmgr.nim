#[
  Single Address Space (SAS) Manager (64-bit)

  The 64-bit address space is partitioned into three parts:
    - user space:    occupies the lower part of the address space
    - canonical gap: occupies the middle of the address space
    - kernel space:  occupies the upper part of the address space

  We're using 48-bit virtual addresses (as opposed to 57-bit), which
  means that the lower and upper partitions are 128 TiB each.

  0xFFFFFFFFFFFFFFFF   (16 EiB) ┌──────────────────────────────┐
                                │         Kernel Space         │
  0xFFFF800000000000 (-128 TiB) ├──────────────────────────────┤
                                │                              │
                                │      Canonical Address       │
                                │             Gap              │
                                │                              │
  0x00007FFFFFFFFFFF  (128 TiB) ├──────────────────────────────┤
                                │         User Space           │
  0x0000000000000000    (0 TiB) └──────────────────────────────┘

  The SAS manager keeps track of allocations within each partition.
  It does not track which task maps which memory regions. This is
  done by the Virtual Memory Manager (VMM).

  Allocations are done in terms of contiguous pages (4 KiB each).
]#

type
  AddressSpacePartition* = object
    base*: VirtAddr
    limit*: VirtAddr

  ASRegion* = object
    base*: VirtAddr
    npages*: uint64

  OutOfAddressSpaceError* = object of CatchableError

const
  uspace* = AddressSpacePartition(
    base: 0x0000000000000000'u64.VirtAddr,
    limit: 0x00007fffffffffff'u64.VirtAddr,
  )
  kspace* = AddressSpacePartition(
    base: 0xffff800000000000'u64.VirtAddr,
    limit: 0xffffffffffffffff'u64.VirtAddr,
  )

# Keep it simple for now and use a simple bump allocator.
var
  ksnext = kspace.base
  usnext = uspace.base

proc ksalloc*(npages: uint64): VirtAddr =
  ## Allocate a region of memory in the kernel space.
  if (kspace.limit -! ksnext) < (npages * PageSize):
    raise newException(OutOfAddressSpaceError, "Out of kernel address space")
  result = ksnext
  ksnext = ksnext +! npages * PageSize

proc usalloc*(npages: uint64): VirtAddr =
  ## Allocate a region of memory in the user space.
  if (uspace.limit -! usnext) < (npages * PageSize):
    raise newException(OutOfAddressSpaceError, "Out of user address space")
  result = usnext
  usnext = usnext +! npages * PageSize

proc ksfree*(base: VirtAddr) =
  ## Free a region of memory in the kernel space.
  discard

proc usfree*(base: VirtAddr) =
  ## Free a region of memory in the user space.
  discard
