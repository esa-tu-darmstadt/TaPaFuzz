unsigned int storage[16];

int fuzz_main(unsigned int arglen, unsigned char *argdata)
{
	unsigned int *outptr = 0;
	if (arglen >= 3)
	{
		//Index to storage should be limited to [0,15].
		outptr = &storage[argdata[0] & 15];
	}
	//Should trigger a write access fault if outptr is still null.
	*outptr = arglen;
	return 0;
}
