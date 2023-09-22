CC = riscv32-unknown-elf-gcc
CXX = riscv32-unknown-elf-g++
OBJCOPY = riscv32-unknown-elf-objcopy
OBJDUMP = riscv32-unknown-elf-objdump

ifneq ($(origin RISCV_CC), undefined)
CC = $(RISCV_CC)
CXX = $(RISCV_CXX)
OBJCOPY = $(RISCV_OBJCOPY)
OBJDUMP = $(RISCV_OBJDUMP)
endif


TARGET_NAME = zstd_fuzzer
TARGET = elf/$(TARGET_NAME)
C_CXX_FLAGS += -Os -fno-builtin-printf

FUZZZSTD_BASE = $(shell pwd)

zstd:
	git clone https://github.com/facebook/zstd zstd_tmp
	cd zstd_tmp && git checkout 7543085013db1a20a848d166e5931edc49e3cc2f
	mv zstd_tmp zstd
	#Download and unzip corpus
	# -> URL: https://github.com/facebook/zstd/releases/download/fuzz-corpora/sequence_compression_api_seed_corpus.zip
	cd zstd/tests/fuzz && make corpora/sequence_compression_api
ifneq "$(wildcard zstd)" ""
LIBZSTD = $(FUZZZSTD_BASE)/zstd/lib
ZSTD_LIB_COMPRESSION = 1
ZSTD_LIB_DECOMPRESSION = 1
ZSTD_LIB_DICTBUILDER = 0
ZSTD_LIB_DEPRECATED = 0
ZSTD_NO_ASM = 1
include $(FUZZZSTD_BASE)/zstd/lib/libzstd.mk

# Library core sources
C_SRCS += $(notdir $(ZSTD_COMMON_FILES)) \
	$(notdir $(ZSTD_COMPRESS_FILES)) \
	$(notdir $(ZSTD_DECOMPRESS_FILES))

# sequence_compression_api fuzz test sources
C_SRCS += $(FUZZZSTD_BASE)/zstd/tests/fuzz/sequence_compression_api.c \
	$(FUZZZSTD_BASE)/zstd/tests/fuzz/fuzz_data_producer.c \
	$(FUZZZSTD_BASE)/zstd/tests/fuzz/fuzz_helpers.c

# Harness sources
C_SRCS += $(FUZZZSTD_BASE)/main.c

INCLUDES += -I$(FUZZZSTD_BASE)/zstd/lib -I$(FUZZZSTD_BASE)/zstd/lib/common
INCLUDES += -I$(FUZZZSTD_BASE)

PREDEPS = zstd elf
BSP_BASE = ../platform
include $(BSP_BASE)/common.mk
elf:
	mkdir -p elf

bin/%.bin: elf/%
	mkdir -p bin
	$(OBJCOPY) -O binary $< $@

build: zstd bin/$(TARGET_NAME).bin
all: build

else
build: zstd
	echo "Build needs to be rerun after cloning zstd in the initial run." 1>&2
	exit 1
all: build
endif

clean::
	rm -f bin/$(TARGET_NAME).bin

