Simple libc stub wrapper platform to enable basic functionality for bare-metal software.  
Provides a startup routine that calls into fuzz_main(uint32_t size, uint8_t* data).  
Supports malloc within the heap region [_end, _heap_end] set by the linker script, but ignores free.

Contains hardcoded memory/MMIO addresses in start.S and platform.h.

Based on SiFive Freedom E SDK legacy v1_0 (https://github.com/sifive/freedom-e-sdk/tree/v1_0).
All of the used components are licensed under the Apache License Version 2.0.
