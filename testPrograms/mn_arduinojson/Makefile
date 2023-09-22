## Depend on System variables
# CC = riscv64-linux-gnu-gcc
CC = riscv32-unknown-elf-gcc
CXX = riscv32-unknown-elf-g++
# OBJCOPY = riscv64-linux-gnu-objcopy
OBJCOPY = riscv32-unknown-elf-objcopy
OBJDUMP = riscv32-unknown-elf-objdump

ifneq ($(origin RISCV_CC), undefined)
CC = $(RISCV_CC)
OBJCOPY = $(RISCV_OBJCOPY)
OBJDUMP = $(RISCV_OBJDUMP)
CXX = $(RISCV_CXX)
endif

TARGET_NAME = json_fuzzer
TARGET = elf/$(TARGET_NAME)
C_CXX_FLAGS += -Os -fno-builtin-printf

CXX_SRCS += json_fuzzer.cpp

INCLUDES += -Iarduinojson/src

PREDEPS = arduinojson elf
BSP_BASE = ../platform
include $(BSP_BASE)/common.mk

arduinojson:
	git clone -b 6.x https://github.com/bblanchon/ArduinoJson arduinojson_tmp
	cd arduinojson_tmp && git checkout 7c2ca773ffa6bd7c018299870e383cd0d5de2fbc
	mv arduinojson_tmp arduinojson
elf:
	mkdir -p elf

bin/%.bin: elf/%
	mkdir -p bin
	$(OBJCOPY) -O binary $< $@

build: arduinojson bin/$(TARGET_NAME).bin
all: build

clean::
#	rm -rf arduinojson_tmp
#	rm -rf arduinojson
	rm -f bin/$(TARGET_NAME).bin
