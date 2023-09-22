// Source: https://github.com/mlouielu/pycflow2dot/blob/19827e89c4fee5c9a443bae744274318f527e893/examples/simple/hello_simple.c
// 2023-09-18: Modified for use in TaPaFuzz as a test program.
// This code file is licensed under the GNU General Public License v3.0, see LICENSE.

/*
 * simple demo for pycflow2dot, use with:
 *    cflow2dot -i hello_simple.c -f png
 * for help:
 *    cflow2dot -h
 */

void myprint(char *s)
{
	// do nothing with string
}

void say_hello(char *s)
{
	myprint(s);
}

void hello_athens()
{
	say_hello("Hello Athens !\n");
}

void take_off()
{
	myprint("Bye bye\n");
}

void cruise()
{
	int res = 0;
	int c = 3;

	switch (c) {
		case 1:
			res = 1+1;
			break;
		case 2 :
			res = 3+3;
			break;
		case 3:
			myprint("Nice blue sky\n");
			break;
	}
}

void land()
{
	int x = 1;
	if (x)
		myprint("I can see you from up here\n");
}

void fly(int num)
{

	for (int i=0; i<num; i++) {
		take_off();
		cruise();
		land();
	}
}

void hello_paris()
{
	say_hello("Hello Paris !\n");
}

void hello_los_angeles()
{
	say_hello("Hello Los Angeles !\n");
}

void back(int num)
{
	fly(num);
}

int fuzz_main(unsigned int arglen, unsigned char *argdata)
{
	if (arglen < 3) return 1;
	hello_athens();
	fly(argdata[0] & 0x0F);
	hello_paris();
	fly(argdata[1] & 0x0F);
	hello_los_angeles();
	back(argdata[2] & 0x0F);
	return 0;
}
