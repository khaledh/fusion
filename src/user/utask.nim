import common/[libc, malloc]

{.used.}

let hello = "hello from user mode"

proc UserMain*() {.exportc, stackTrace: off.} =
  # do a syscall
  let saddr = hello.addr
  asm """
    mov rdi, 5
    mov rsi, %0
  .loop1:
    pause
    jmp .loop1
    syscall
    :
    : "r"(`saddr`)
    : "rdi", "rsi"
  """

  asm """
  .loop:
    pause
    jmp .loop
  """

  # asm "hlt"

  # access illegal memory
  # var x = cast[ptr int](0xFFFF800000100000)
  # x[] = 42
  # asm "int 100"
