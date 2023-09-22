ENTRY(_start)
/* Based on linker script retrieved via `riscv32-unknown-linux-gnu-ld --verbose` */
/* Copyright (C) 2014-2022 Free Software Foundation, Inc.
   Copying and distribution of this script, with or without modification,
   are permitted in any medium without royalty provided the copyright
   notice and this notice are preserved.  */
/* Also based on linker script freedom-e-sdk/bsp/env/freedom-e300-hifive1/link.lds, see README.md and LICENSE */
MEMORY
{
	imem (xai!rw) : ORIGIN = 0x40000000, LENGTH = 64K
	dmem (wa!rxi) : ORIGIN = 0x40800000, LENGTH = 64K
}
PHDRS
{
	imem PT_LOAD;
	dmem_init PT_LOAD;
	dmem PT_NULL;
}
SECTIONS
{
	__stack_size = 4K;
	__input_size = 4K;
	
	.text.init : {
		* (.text.init);
	} >imem AT>imem :imem
	.text : {
		*(.text.unlikely .text.unlikely.*)
		*(.text.startup .text.startup.*)
		*(.text .text.*)
		*(.gnu.linkonce.t.*)
	} >imem AT>imem :imem
	.fini           :
	{
		KEEP (*(SORT_NONE(.fini)))
	} >imem AT>imem :imem
	
	PROVIDE (__etext = .);
	PROVIDE (_etext = .);
	PROVIDE (etext = .);
	
	.data : {
		. = ALIGN(4);
		PROVIDE( _data = . );
		*(.data .data.*)
		*(.gnu.linkonce.d.*)
	} >dmem AT>dmem :dmem_init
	.srodata : {
		PROVIDE( __global_pointer$ = . + 0x800 );
		*(.srodata.cst16)
		*(.srodata.cst8)
		*(.srodata.cst4)
		*(.srodata.cst2)
		*(.srodata .srodata.*)
	} >dmem AT>dmem :dmem_init
	.sdata : {
		*(.sdata .sdata.*)
		*(.gnu.linkonce.s.*)
	} >dmem AT>dmem :dmem_init
	.rodata : {
		*(.rdata)
		*(.rodata .rodata.*)
		*(.gnu.linkonce.r.*)
	} >dmem AT>dmem :dmem_init
	
	. = ALIGN(4);

	.preinit_array  :
	{
		PROVIDE_HIDDEN (__preinit_array_start = .);
		KEEP (*(.preinit_array))
		PROVIDE_HIDDEN (__preinit_array_end = .);
	} >dmem AT>dmem :dmem_init

	.init_array     :
	{
		PROVIDE_HIDDEN (__init_array_start = .);
		KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
		KEEP (*(.init_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .ctors))
		PROVIDE_HIDDEN (__init_array_end = .);
	} >dmem AT>dmem :dmem_init

	.fini_array     :
	{
		PROVIDE_HIDDEN (__fini_array_start = .);
		KEEP (*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
		KEEP (*(.fini_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .dtors))
		PROVIDE_HIDDEN (__fini_array_end = .);
	} >dmem AT>dmem :dmem_init

	.ctors          :
	{
		/* gcc uses crtbegin.o to find the start of
		   the constructors, so we make sure it is
		   first.  Because this is a wildcard, it
		   doesn't matter if the user does not
		   actually link against crtbegin.o; the
		   linker won't look for a file to match a
		   wildcard.  The wildcard also means that it
		   doesn't matter which directory crtbegin.o
		   is in.  */
		KEEP (*crtbegin.o(.ctors))
		KEEP (*crtbegin?.o(.ctors))
		/* We don't want to include the .ctor section from
		   the crtend.o file until after the sorted ctors.
		   The .ctor section from the crtend file contains the
		   end of ctors marker and it must be last */
		KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .ctors))
		KEEP (*(SORT(.ctors.*)))
		KEEP (*(.ctors))
	} >dmem AT>dmem :dmem_init

	.dtors          :
	{
		KEEP (*crtbegin.o(.dtors))
		KEEP (*crtbegin?.o(.dtors))
		KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .dtors))
		KEEP (*(SORT(.dtors.*)))
		KEEP (*(.dtors))
	} >dmem AT>dmem :dmem_init

	. = ALIGN(4);
	PROVIDE( _edata = . );
	PROVIDE( edata = . );

	PROVIDE( _fbss = . );
	PROVIDE( __bss_start = . );
	.bss            :
	{
		*(.sbss*)
		*(.gnu.linkonce.sb.*)
		*(.bss .bss.*)
		*(.gnu.linkonce.b.*)
		*(COMMON)
		. = ALIGN(4);
	} >dmem AT>dmem :dmem

    . = ALIGN(8);
    PROVIDE( _end = . );
    PROVIDE( end = . );
	
	. = ORIGIN(dmem) + LENGTH(dmem) - __stack_size - __input_size;
	PROVIDE(_heap_end = .);
	
	.stack ORIGIN(dmem) + LENGTH(dmem) - __stack_size :
	{
		PROVIDE(_input_end = .);
		. = __stack_size;
		PROVIDE( _sp = . );
	} >dmem AT>dmem :dmem
}
