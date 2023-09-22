#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <string.h>

int main(int argc, char **argv)
{
	if (argc < 2)
		return 1;
	FILE *in_file = fopen(argv[1], "rb");
	if (in_file == NULL)
	{
		printf("fopen %s (err %s)\n", argv[1], strerror(errno));
		return 1;
	}
	fseek(in_file, 0, SEEK_END);
	long in_file_size = ftell(in_file);
	fseek(in_file, 0, SEEK_SET);
	if (in_file_size < 0)
	{
		fclose(in_file);
		printf("fseek, ftell\n");
		return 1;
	}
	if (in_file_size > UINT_MAX) in_file_size = UINT_MAX;
	void *in_data = malloc((size_t)in_file_size);
	if (fread(in_data, in_file_size, 1, in_file) != 1)
	{
		fclose(in_file);
		printf("fread\n");
		return 1;
	}
	fclose(in_file);
	extern int fuzz_main(unsigned int arglen, unsigned char *argdata);
	return fuzz_main((unsigned int)in_file_size, (unsigned char*)in_data);
}
