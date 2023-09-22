void loop_body()
{
	//Do nothing
}

int fuzz_main(unsigned int arglen, unsigned char *argdata)
{
	for (unsigned int i = 0; i < 2; ++i)
		loop_body();
	return 0;
}
