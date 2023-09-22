//From https://github.com/AFLplusplus/AFLplusplus/blob/stable/instrumentation/README.persistent_mode.md

__AFL_FUZZ_INIT();

void main() {
	#ifdef __AFL_HAVE_MANUAL_CONTROL
	__AFL_INIT();
	#endif

	unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;

	while (__AFL_LOOP(10000)) {

		int len = __AFL_FUZZ_TESTCASE_LEN;  // don't use the macro directly in a call!

		if (len < 8) continue;  // check for a required/useful minimum input length

		extern int fuzz_main(unsigned int arglen, unsigned char *argdata);
		fuzz_main((unsigned int)len, buf);
	}

	return 0;
}
