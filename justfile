nimfile := "src/bootx64.nim"
outfile := "diskimg/efi/boot/bootx64.efi"

[linux]
compile:
  nim c --os:any --out:{{outfile}} {{nimfile}}

[macos]
compile:
  nim c --os:any -d:macosx --out:{{outfile}} {{nimfile}}

run: kernel compile
  qemu-system-x86_64 \
    -drive if=pflash,format=raw,file=ovmf/OVMF_CODE.fd,readonly=on \
    -drive if=pflash,format=raw,file=ovmf/OVMF_VARS.fd \
    -drive format=raw,file=fat:rw:diskimg \
    -machine q35 \
    -net none \
    -debugcon stdio -global isa-debugcon.iobase=0x402
#    -nographic

kernel:
  # compile kernel
  nim c \
    --os:any \
    -d:macosx \
    --noLinking:on \
    --passC:"-target x86_64-unknown-elf" \
    --outdir:build \
    src/kernel.nim

  # link - kernel object has to be first
  ld.lld \
    --oformat=binary \
    -nostdlib \
    -T src/kernel.ld \
    -Map=kernel.map \
    build/@mkernel.nim.c.o \
    build/@mlibc.nim.c.o \
    build/@mmalloc.nim.c.o \
    build/@mports.nim.c.o \
    build/@muefi.nim.c.o \
    build/@mdebug.nim.c.o \
    build/@m..@s..@s..@s..@s..@s.choosenim@stoolchains@snim-2.0.0@slib@ssystem.nim.c.o \
    build/@m..@s..@s..@s..@s..@s.choosenim@stoolchains@snim-2.0.0@slib@ssystem@sdollars.nim.c.o \
    build/@m..@s..@s..@s..@s..@s.choosenim@stoolchains@snim-2.0.0@slib@sstd@sprivate@sdigitsutils.nim.c.o \
    build/@m..@s..@s..@s..@s..@s.choosenim@stoolchains@snim-2.0.0@slib@ssystem@sexceptions.nim.c.o \
    build/@m..@s..@s..@s..@s..@s.choosenim@stoolchains@snim-2.0.0@slib@sstd@swidestrs.nim.c.o \
    build/@m..@s..@s..@s..@s..@s.choosenim@stoolchains@snim-2.0.0@slib@sstd@sassertions.nim.c.o \
    -o kernel.bin
  
  # copy kernel.bin to disk image
  cp kernel.bin diskimg/efi/fusion/kernel.bin
