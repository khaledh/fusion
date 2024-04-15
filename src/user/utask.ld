ENTRY(UserMain)

SECTIONS
{
  .dynamic     : { *(.dynamic) }
  .data.rel.ro : { *(.data.rel.ro) }
  .rela.dyn    : { *(.rela.dyn) }

  .text : {
    *utask*.o(.*text.UserMain)
    *utask*.o(.*text.*)
    *(.*text*)
  }
  .rodata      : { *(.*rodata*) }
  .data        : { *(.*data*) *(.*bss) }

  .strtab      : { *(.strtab) }
  .symtab      : { *(.symtab) }

  .shstrtab    : { *(.shstrtab) } /* cannot be discarded */
  /DISCARD/    : { *(*) }
}
