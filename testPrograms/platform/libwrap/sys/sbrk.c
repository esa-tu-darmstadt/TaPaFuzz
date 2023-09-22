/* See LICENSE of license details. */

#include <stddef.h>
#include "weak_under_alias.h"

void *__wrap_sbrk(ptrdiff_t incr)
{
	extern char _end[];
	extern char _heap_end[];
	static char *curbrk = _end;
	
	incr = (incr + 3) &~ 3; //4 byte align length
	if ((curbrk + incr < _end) || (curbrk + incr > _heap_end))
		return NULL - 1;

	curbrk += incr;
	return curbrk - incr;
}
weak_under_alias(sbrk);
