/* See LICENSE for license details. */
#include <stdint.h>
#include <limits.h>
/* These functions are intended for embedded RV32 systems and are
   obviously incorrect in general. */

#define HEAPCHECKVAL 0xCD

void* __wrap_malloc(unsigned long sz)
{
	extern void* sbrk(long);
	#ifdef HEAP_SIMPLEVALIDATE
	extern void exit(int);
	if (sz+6 >= UINT32_MAX || sz+6 < 6)
		exit(0x8000); //OOM
	void* res = sbrk(sz + 6);
	if ((long)res == -1)
		exit(0x8000); //OOM
	*(uint32_t*)res = sz;
	((uint8_t*)res)[sz + 4] = HEAPCHECKVAL;
	((uint8_t*)res)[sz + 5] = HEAPCHECKVAL;
	res = &((uint8_t*)res)[4];
	#else
	void* res = sbrk(sz);
	if ((long)res == -1)
		return 0;
	#endif
	return res;
}

void __wrap_free(void* ptr)
{
	extern void exit(int);
	extern char _end[];
	extern char _heap_end[];
	if (!ptr) return;
	#ifdef HEAP_SIMPLEVALIDATE
	{
		uint32_t sz;
		
		if ((uintptr_t)ptr > (uintptr_t)&_heap_end[0] - 2) exit(0x8001); //Invalid ptr
		if ((uintptr_t)ptr < (uintptr_t)&_end[4]) exit(0x8001); //Invalid ptr
		
		sz = *(uint32_t*)((uintptr_t)ptr - 4);
		
		if (sz == (uint32_t)-1) exit(0x8002); //Double free
		if (sz > (uint8_t*)&_heap_end[0] - 2 - (uint8_t*)ptr) exit(0x8003); //Corruption
		if (((uint8_t*)ptr)[sz] != HEAPCHECKVAL
		    || ((uint8_t*)ptr)[sz+1] != HEAPCHECKVAL)
			exit(0x8003); //Corruption
		
		//Mark as freed.
		*(uint32_t*)((uintptr_t)ptr - 4) = (uint32_t)-1;
	}
	#endif
}
