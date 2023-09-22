# See LICENSE for license details.

ifndef _SIFIVE_MK_COMMON
_SIFIVE_MK_COMMON := # defined

RISCV_ARCH=rv32im
RISCV_ABI=ilp32

.PHONY: all
all: $(TARGET)


ENV_DIR = $(BSP_BASE)


ifeq ($(PE_BRAM),1)
	LINKER_SCRIPT := $(ENV_DIR)/platform_link_bram.ld
else
	LINKER_SCRIPT := $(ENV_DIR)/platform_link.ld
endif

INCLUDES += -I$(ENV_DIR)

TOOL_DIR = $(BSP_BASE)/../toolchain/bin

ifeq ($(USE_STDLIB),1)
  STDLIB_FLAG :=
else
  LDFLAGS += -T $(LINKER_SCRIPT)
  LDFLAGS += -nostartfiles
  ASM_SRCS += $(ENV_DIR)/start.S
  include $(BSP_BASE)/libwrap/libwrap.mk
endif
C_SRCS += $(SRCS_START)

LDFLAGS += -L$(ENV_DIR)
#Commented out, as using newlib-nano causes not yet analyzed issues during program execution.
#LDFLAGS += --specs=nano.specs

ASM_OBJS := $(ASM_SRCS:.S=.o)
C_OBJS := $(C_SRCS:.c=.o)
CXX_OBJS := $(CXX_SRCS:.cpp=.o)

LINK_OBJS += $(ASM_OBJS) $(C_OBJS) $(CXX_OBJS)
LINK_DEPS += $(LINKER_SCRIPT)

CLEAN_OBJS += $(TARGET) $(LINK_OBJS)

C_CXX_FLAGS += -g
PLATFORM_ARCHFLAGS ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -mcmodel=medany
C_CXX_FLAGS += $(PLATFORM_ARCHFLAGS)
CFLAGS += $(C_CXX_FLAGS)
CCFLAGS += $(C_CXX_FLAGS)
CXXFLAGS += -fno-exceptions
CXXFLAGS += $(C_CXX_FLAGS)


$(TARGET): $(PREDEPS) $(LINK_OBJS) $(LINK_DEPS)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(LINK_OBJS) -o $@ $(LDFLAGS)

$(ASM_OBJS): %.o: %.S $(HEADERS)
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

$(C_OBJS): %.o: %.c $(HEADERS)
	$(CC) $(CCFLAGS) $(INCLUDES) -include sys/cdefs.h -c -o $@ $<

$(CXX_OBJS): %.o: %.cpp $(HEADERS)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -include sys/cdefs.h -c -o $@ $<

.PHONY: clean
clean::
	rm -f $(CLEAN_OBJS)

endif # _SIFIVE_MK_COMMON
