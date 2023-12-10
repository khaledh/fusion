_KERNEL_BASE = 0x100000;

SECTIONS {
    . = _KERNEL_BASE;
    .text : {
        *kernel*(.text)
        *(.text)
    }
    .data : {
        *(.rodata.str1.1)
        *(.rodata)
        *(.data)
        *(.bss)
    }
    .shstrtab : {
        *(.shstrtab)
    }

    /DISCARD/ : {
        *(*)
    }
}
