# Fusion OS


Fusion is a hobby operating system for x86-64 implemented in Nim. I'm documenting
the process of building it at: [https://0xc0ffee.netlify.app](https://0xc0ffee.netlify.app).

## Screenshots

**UEFI Bootloader**

![UEFI Bootloader](screenshots/bootloader.png)

**GUI** (_Note: This screenshot is from the `graphics` branch, which is still a work-in-progress._)

![Screenshot from the graphics branch](screenshots/graphics.png)

**Booting and Running the Kernel**

![Booting and Running Fusion Kernel](screenshots/kernel-booting.png)

## Features

The following features are currently implemented:

- UEFI Bootloader
- Memory Management
  - Single Address Space
  - Physical Memory Manager
  - Virtual Memory Manager
  - Demand Paging
  - Higher Half Kernel
- Task Management
  - Kernel Tasks
  - User Mode Tasks
  - Preemptive Multitasking
  - Priority-based Scheduling
  - ELF Loader (Demand Paged, Relocation)
- System Calls
  - System Call Interface
  - User Mode Library
- IPC
  - Synchronization Primitives
  - Channel-based IPC
  - Message Passing
- Hardware
  - Timer Interrupts
  - PCI Device Enumeration
  - Bochs Graphics Adapter Driver

#### Planned

- Capability-based Security
- Event-based Task State Machines
- Disk I/O
- File System
- Keyboard/Mouse Input
- Shell
- GUI
- Networking

## Building

To build Fusion, you need to have the following dependencies installed:

- [Nim](https://nim-lang.org)
- [LLVM](https://llvm.org) (clang and lld)
- [Just](https://github.com/casey/just)

The `clang` and `lld` binaries should be in your `PATH`. You can edit the `.env` file to specify the path to the `clang` and `lld` binaries if they are not in your `PATH`.

Build Fusion with the following command:

```sh
just build
```

## Running

Fusion currently runs on [QEMU](https://www.qemu.org), so you'll need to install it first. Launch Fusion with the following command:

```sh
just run
```

## License

MIT
