SECTIONS
{
  . = 0x00000000040000000; /* 1 GiB */
  .text   : {
    *utask*.o(.*text.UserMain)
    *utask*.o(.*text.*)
    *(.*text*)
  }
  .rodata : { *(.*rodata*) }
  .data   : { *(.*data) *(.*bss) }
  .shstrtab : { *(.shstrtab) } /* cannot be discarded */
  /DISCARD/ : { *(*) }
}
