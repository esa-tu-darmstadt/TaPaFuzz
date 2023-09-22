
void loop_body()
{
	//Do nothing.
}

int readptr(int *pvar)
{
	return *pvar;
}
void writeptr(int *pvar, int val)
{
	*pvar = val;
}

static int storage[16] = {1,3,2,6,5,4,11,8,9,10,7,15,13,12,14};

int fuzz_main(unsigned int arglen, unsigned char *argdata)
{
	if (arglen < 2) return 1;
	//Allow unaligned address: Bit 1 (decimal 2) of offs can be non-zero.
	int offs_read = argdata[0] & 62;
	//Read from the potentially unaligned address.
	int count = readptr((int*)(((char*)storage) + offs_read)) & 0x0F;
	for (int i = 0; i < count; ++i)
		loop_body();
	//Allow unaligned address: Bit 0 (decimal 1) of offs can be non-zero.
	int offs_write = argdata[1] & 61;
	//Write to the potentially unaligned address.
	writeptr((int*)(((char*)storage) + offs_write), count);
	return 0;
}
