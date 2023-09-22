#include "lwesp/lwesp.h"
#include "lwesp/lwesp_mem.h"
#include "lwesp/lwesp_input.h"

lwespr_t fuzz_lwesp_event_callback(struct lwesp_evt *evt)
{
	return lwespOK;
}

int fuzz_main(uint32_t size, const uint8_t *data) {
	if (lwesp_init(&fuzz_lwesp_event_callback, 0) != 0)
		return 0;
	lwesp_input_process(data, size);
	return 0;
}
