// See LICENSE for license details.

	.section .text.init
	.globl _start
	.type _start,@function

_start:
	lui x1, 0x00100 #NOTE: Only for regular tapasco-riscv
	addi x1, x1, 0x00C #NOTE: Only for regular tapasco-riscv
	jr x1 #NOTE: Only for regular tapasco-riscv
	.cfi_startproc
	.cfi_undefined ra
.option push
.option norelax
	la gp, __global_pointer$
.option pop
	la sp, _sp

	/* Clear bss section */
	la a0, __bss_start
	la a1, _end
	bgeu a0, a1, 2f
1:
	sw zero, (a0)
	addi a0, a0, 4
	bltu a0, a1, 1b
2:

	/* Call global constructors */
	la a0, __libc_fini_array
	call atexit
	call __libc_init_array

	auipc ra, 0
	addi sp, sp, -16
	sw ra, 8(sp)

	lui t0, 0x11000
	li t1, 1 #NOTE: Only for regular tapasco-riscv
	sw t1, 0x10(t0) #NOTE: Only for regular tapasco-riscv. Set default return status 'crash' - [0x11000010]=1.
	lw a0, 0x30(t0) #FuzzerCore arg1: argument size
	lw a1, 0x40(t0) #FuzzerCore arg2: argument data
	call fuzz_main
main_ret:
	lui x1, 0x11000
	li x2, 1
	#NOTE: For FuzzerCore, use this for IRQ:
	#sw x2, 0x80(x1) #Set IRQ: [0x11000070]=1
	li x3, 0
	sw x3, 0x010(x1) #NOTE: Only for regular tapasco-riscv. Set return status 'success' - [0x11000010]=0.
	lui x1, 0x11004
	sw x2, 0x000(x1) #NOTE: Only for regular tapasco-riscv. Request end - [0x11004000]=1.
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
	
	.cfi_endproc
