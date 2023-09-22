.section ".text.init"
.globl _start
_start:
	li x1, 0
	li x2, 0
	li x3, 0
	li x4, 0
	li x5, 0
	li x6, 0
	li x7, 0
	li x8, 0
	li x9, 0
	li x10, 0
	li x11, 0
	li x12, 0
	li x13, 0
	li x14, 0
	li x15, 0
	li x16, 0
	li x17, 0
	li x18, 0
	li x19, 0
	li x20, 0
	li x21, 0
	li x22, 0
	li x23, 0
	li x24, 0
	li x25, 0
	li x26, 0
	li x27, 0
	li x28, 0
	li x29, 0
	li x30, 0
	li x31, 0
init_stack:
	la sp, _sp
	lui t0, 0x11000
	lw a0, 0x30(t0) #FuzzerCore arg1: argument size
	lw a1, 0x40(t0) #FuzzerCore arg2: argument data
	jal fuzz_main
main_ret:
	lui x1, 0x11000
	li x2, 1
	sw x2, 0x80(x1) #Set IRQ: [0x11000070]=1
main_pending: #Add some nops so the interrupt has a chance to reach the fuzzer before the jump.
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	j main_pending
