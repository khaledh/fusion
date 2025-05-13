#[
  Virtual Memory Space Manager (64-bit)

  The 64-bit virtual memory address space is divided into three parts:
    - user space:    occupies the lower part of the address space
    - canonical gap: occupies the middle of the address space
    - kernel space:  occupies the upper part of the address space

  We're using 48-bit virtual addresses (as opposed to 57-bit), which means that
  the lower and upper parts are 128 TiB each.

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

  Notes:
  - The kernel and user spaces are represented as `VmSpace` objects.
  - This manager keeps track of allocations using a separate free list for each
    space.
  - Allocations are done in terms of contiguous pages (4 KiB each).
  - A `VmRegion` is a contiguous region of virtual memory allocated within a
    space. It has no concept of mapping to physical memory, which is handled by
    the VMM.
]#
import std/strformat

import freelist

let
  logger = DebugLogger(name: "vmspace")

type
  VmSpace* = object
    ## A disjoint part of the virtual memory address space.
    base*: VAddr    ## Base address of the space
    limit*: VAddr   ## Limit address of the space

  VmRegion* = object
    ## A contiguous region of virtual memory allocated within a space.
    slice: AllocatedSlice  # private (see `base` and `npages` public templates)
  
  OutOfVirtualMemoryError* = object of CatchableError
    ## An error raised when a region of virtual memory cannot be allocated.

proc size*(space: VmSpace): uint64 {.inline.} = space.limit -! space.base + 1

template base*(region: VmRegion): VAddr = region.slice.start.VAddr
template npages*(region: VmRegion): uint64 = region.slice.size div PageSize

const
  uvspace = VmSpace(
    base: 0x0000000000001000'u64.VAddr,  # exclude the first page to trap null pointer dereferences
    limit: 0x00007fffffffffff'u64.VAddr,
  )
  kvspace = VmSpace(
    base: 0xffff800000000000'u64.VAddr,
    limit: 0xffffffffffffefff'u64.VAddr,  # exclude the last page to avoid address overflow/wraparound
  )

var
  kFreeList* = newFreeList(kvspace.base.uint64, kvspace.size)
  uFreeList* = newFreeList(uvspace.base.uint64, uvspace.size)

proc kvalloc*(npages: uint64): VmRegion =
  ## Allocate a region of virtual memory space in the kernel space.
  ## 
  ## Note: This does not map
  let slice = kFreeList.alloc(npages * PageSize)
  result = VmRegion(slice: slice)

proc uvalloc*(npages: uint64): VmRegion =
  ## Allocate a region of virtual memory space in the user space.
  let slice = uFreeList.alloc(npages * PageSize)
  result = VmRegion(slice: slice)

proc kvreserve*(vaddr: VAddr, npages: uint64): VmRegion =
  ## Reserve a region of memory space in the kernel space at a specific address.
  assert vaddr.uint64 mod PageSize == 0, "vaddr must be page-aligned"
  let slice = kFreeList.reserve(vaddr.uint64, npages * PageSize)
  result = VmRegion(slice: slice)

proc uvreserve*(vaddr: VAddr, npages: uint64): VmRegion =
  ## Reserve a region of memory space in the user space at a specific address.
  assert vaddr.uint64 mod PageSize == 0, "vaddr must be page-aligned"
  let slice = uFreeList.reserve(vaddr.uint64, npages * PageSize)
  result = VmRegion(slice: slice)

proc kvfree*(region: VmRegion) =
  ## Free a region of memory space in the kernel space.
  kFreeList.free(region.slice)

proc uvfree*(region: VmRegion) =
  ## Free a region of memory space in the user space.
  uFreeList.free(region.slice)

proc dump*() =
  ## Dump the free list to the console.
  # logger.raw "\n"
  # logger.info "user free list"
  # uFreeList.dump()

  logger.raw "\n"
  logger.info "kernel free list"
  kFreeList.dump()
  logger.raw "\n"
