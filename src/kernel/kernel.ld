SECTIONS
{
  . = 0xffffffff80100000;  /* Upper 2 GiB of the address space */
  .text   : {
    *start*.o(.*text.kstart)
    *start*.o(.*text.*)
    *(.*text*)
  }
  .rodata : { *(.*rodata*) }
  .data   : { *(.*data) *(.*bss) }
  .shstrtab : { *(.shstrtab) }
  /DISCARD/ : { *(*) }
}
