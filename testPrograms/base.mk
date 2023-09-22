## Depend on System variables
CC = riscv64-linux-gnu-gcc
OBJCOPY = riscv64-linux-gnu-objcopy
PLATFORM_ARCHFLAGS ?= -march=rv32im -mabi=ilp32
ifeq ($(PE_BRAM),1)
	PLATFORM_CFLAGS ?= -T ../platform/platform_link_bram.ld ../startup.s
else
	PLATFORM_CFLAGS ?= -T ../platform/platform_link.ld ../startup.s
endif
STDLIB_FLAG ?= -nostdlib

ifneq ($(origin RISCV_CC), undefined)
  CC = $(RISCV_CC)
  OBJCOPY = $(RISCV_OBJCOPY)
endif
ifeq ($(USE_STDLIB),1)
  STDLIB_FLAG :=
endif

BASEFLAGS = $(PLATFORM_ARCHFLAGS) $(STDLIB_FLAG) -g
CFLAGS = $(BASEFLAGS) $(PLATFORM_CFLAGS)
DUMPFLAGS = -O binary -j .text.init -j .text -j .data -j .srodata -j .rodata -j .bss -j .sdata 

SRCS = $(wildcard *.c)
ELFS = $(SRCS:%.c=elf/%)
BINS = $(SRCS:%.c=bin/%.bin)

EXECUTABLES = $(ELFS)

ifneq ($(VERBOSE),)
$(info CC=$(CC))
$(info CFLAGS=$(CFLAGS))
$(info OBJDUMP=$(OBJDUMP))
$(info DUMPFLAGS=$(DUMPFLAGS))
endif

.PHONY: build

all: build

elf/%:
	mkdir -p elf
	$(CC) $(CFLAGS) $*.c $(SRCS_START) -o $@

bin/%.bin: elf/%
	mkdir -p bin
	$(OBJCOPY) $(DUMPFLAGS) $< $@

build: $(EXECUTABLES) $(BINS)

clean:
	-rm -f $(wildcard bin/*.bin)
	-rm -f $(EXECUTABLES)
	
