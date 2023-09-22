void loop_body()
{
	//Do nothing
}

int fuzz_main(unsigned int arglen, unsigned char *argdata)
{
	int n = 0;
	if (arglen < 3)
	{
		//Should trigger a read access fault (assuming it is no data memory address).
		n = *(int*)0x0F000000;
	}
	else 
	{
		n = argdata[3] & 0x0F;
	}
	for (int i = 0; i < n; ++i)
		loop_body();
	return 0;
}
