SECTIONS {
    . = 0x100000;
    .text : {
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
