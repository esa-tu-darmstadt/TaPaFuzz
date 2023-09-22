ENTRY(_start)
MEMORY
{
	imem (xai!rw) : ORIGIN = 0x40000000, LENGTH = 64K
	dmem (wa!rxi) : ORIGIN = 0x40800000, LENGTH = 64K
}
SECTIONS
{
	__stack_size = 4K;
	
	. = 0x40000000;
	.text.init : {
			* (.text.init);
	}
	.text : {
	      * (.text);
	}
	. = 0x40800000;
	.data : {
	      * (.data);
	}
	.srodata : {
	      * (.srodata);
	}
	.rodata : {
	      * (.rodata);
	}
	.bss : {
	     * (.bss);
	}
	
	.stack ORIGIN(dmem) + LENGTH(dmem) - __stack_size :
	{
		. = __stack_size;
		PROVIDE( _sp = . );
	}
}
