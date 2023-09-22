/* See LICENSE of license details. */

#include <unistd.h>
#include <stdint.h>
#include "platform.h"
#include "weak_under_alias.h"

void __wrap_exit(int code)
{
	if (code != 0)
	{
		//Cause an exception, and place the code inside.
		*(uint8_t*)code = 0;
		*(int*)0x78 = code; 
	}
	*FUZZCORE_MMIO_PROGINT = 1; //Notify the fuzzer PE.
	asm volatile(
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
	);
	for (;;);
}
weak_under_alias(exit);
