nimfile := "src/bootx64.nim"
outfile := "diskimg/efi/boot/bootx64.efi"

[linux]
compile:
  nim c --os:any --out:{{outfile}} {{nimfile}}

[macos]
compile:
  nim c --os:any -d:macosx --out:{{outfile}} {{nimfile}}

run: compile
  qemu-system-x86_64 \
    -drive if=pflash,format=raw,file=ovmf/OVMF_CODE.fd,readonly=on \
    -drive if=pflash,format=raw,file=ovmf/OVMF_VARS.fd \
    -drive format=raw,file=fat:rw:diskimg \
    -machine q35 \
    -net none \
    -nographic
