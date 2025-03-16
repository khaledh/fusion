set dotenv-load

nimflags := (
  "--os:any" +
  if os() == "macos" { " -d:macosx" } else { "" }
)

export PATH := (
  if os() == "macos" {
    `brew --prefix llvm` + "/bin:" + env_var('PATH')
  } else {
    env_var('PATH')
  }
)

boot_nim := "src/boot/bootx64.nim"
boot_out := "bootx64.efi"

kernel_nim := "src/kernel/main.nim"
kernel_out := "kernel.bin"

user_nim := "src/user/utask.nim"
user_out := "utask.bin"

ovmf_code := "ovmf/OVMF_CODE.fd"
ovmf_vars := "ovmf/OVMF_VARS.fd"

disk_image_dir := "diskimg"

bootloader:
  nim c {{nimflags}} --out:build/boot/{{boot_out}} {{boot_nim}}

kernel:
  nim c {{nimflags}} --out:build/kernel/{{kernel_out}} {{kernel_nim}}

user:
  nim c {{nimflags}} --out:build/user/{{user_out}} {{user_nim}}

build: bootloader kernel user

run *QEMU_ARGS: bootloader kernel user
  mkdir -p {{disk_image_dir}}/efi/boot
  mkdir -p {{disk_image_dir}}/efi/fusion
  cp build/boot/{{boot_out}} {{disk_image_dir}}/efi/boot/{{boot_out}}
  cp build/kernel/{{kernel_out}} {{disk_image_dir}}/efi/fusion/{{kernel_out}}
  cp build/user/{{user_out}} {{disk_image_dir}}/efi/fusion/{{user_out}}

  @git restore ovmf/OVMF_VARS.fd

  @echo ""
  -qemu-system-x86_64 \
    -drive if=pflash,format=raw,file={{ovmf_code}},readonly=on \
    -drive if=pflash,format=raw,file={{ovmf_vars}} \
    -drive format=raw,file=fat:rw:{{disk_image_dir}} \
    -machine q35 \
    -net none \
    -no-reboot \
    -debugcon stdio {{QEMU_ARGS}}

  @git restore ovmf/OVMF_VARS.fd

test:
  testament --megatest:off all
  # clean up executable test files
  @find tests -type f -perm +100 -delete

clean:
  git restore ovmf/OVMF_VARS.fd
  rm -rf build
  rm -rf {{disk_image_dir}}/efi/boot/{{boot_out}}
  rm -rf {{disk_image_dir}}/efi/fusion/{{kernel_out}}
  rm -rf {{disk_image_dir}}/efi/fusion/{{user_out}}
