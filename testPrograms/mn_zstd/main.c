#include <stddef.h>
#include <stdint.h>

int fuzz_main(uint32_t size, const uint8_t *data) {
	extern int LLVMFuzzerTestOneInput(const uint8_t* src, size_t size);
	return LLVMFuzzerTestOneInput(data, size);
}
