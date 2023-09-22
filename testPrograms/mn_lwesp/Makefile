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


TARGET_NAME = lwesp_fuzzer
TARGET = elf/$(TARGET_NAME)
C_CXX_FLAGS += -O3 -fno-builtin-printf

FUZZLWESP_BASE = $(shell pwd)

# Library core sources
C_SRCS += \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_dhcp.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_dns.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_hostname.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_ping.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_utils.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_ap.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_buff.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_conn.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_debug.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_evt.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_input.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_int.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_mdns.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_mem.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_parser.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_pbuf.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_server.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_sntp.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_sta.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_threads.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_timeout.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_unicode.c \
    $(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_wps.c
    #$(FUZZLWESP_BASE)/lwesp/lwesp/src/lwesp/lwesp_cli.c
# API sources
C_SRCS += $(FUZZLWESP_BASE)/lwesp/lwesp/src/api/lwesp_netconn.c
# HTTP server app sources
#C_SRCS += \
#    lwesp/lwesp/src/apps/http_server/lwesp_http_server.c \
#    lwesp/lwesp/src/apps/http_server/lwesp_http_server_fs.c
# MQTT app sources
#C_SRCS += \
#    lwesp/lwesp/src/apps/mqtt/lwesp_mqtt_client.c \
#    lwesp/lwesp/src/apps/mqtt/lwesp_mqtt_client_api.c \
#    lwesp/lwesp/src/apps/cayenne/lwesp_cayenne.c \
#    lwesp/lwesp/src/apps/cayenne/lwesp_cayenne_evt.c
# CLI app sources
#C_SRCS += \
#    lwesp/lwesp/src/cli/cli.c \
#    lwesp/lwesp/src/cli/cli_input.c

# Fuzzer stub platform for lwesp.
C_SRCS += \
    $(FUZZLWESP_BASE)/lwesp_sys_fuzz.c \
    $(FUZZLWESP_BASE)/lwesp_ll_fuzz.c

C_SRCS += $(FUZZLWESP_BASE)/main.c

INCLUDES += -I$(FUZZLWESP_BASE)/lwesp/lwesp/src/include
INCLUDES += -I$(FUZZLWESP_BASE)

PREDEPS = lwesp elf
BSP_BASE = ../platform
include $(BSP_BASE)/common.mk

lwesp:
	git clone https://github.com/MaJerle/lwesp lwesp_tmp
	cd lwesp_tmp && git checkout 25d840e4836eb7f1ef0613211237d2589785dad6
	mv lwesp_tmp lwesp
elf:
	mkdir -p elf

bin/%.bin: elf/%
	mkdir -p bin
	$(OBJCOPY) -O binary $< $@

build: lwesp bin/$(TARGET_NAME).bin
all: build

clean::
#	rm -rf lwesp_tmp
#	rm -rf lwesp
	rm -f bin/$(TARGET_NAME).bin
