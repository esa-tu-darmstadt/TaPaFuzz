PROJECTS=$(wildcard en_*)
PROJECTS_MANUAL=$(wildcard mn_*)
$(info PROJECTS=$(PROJECTS))

MAKEARGS_FORKSERVER=SRCS_START=../main_forkserver.c PLATFORM_CFLAGS="" USE_STDLIB=1
ifeq ($(BUILD_FORKSERVER),1)
  MAKEARGS += $(MAKEARGS_FORKSERVER)
endif
MAKEARGS_PERSISTENT=SRCS_START=../main_persistent.c PLATFORM_CFLAGS="" USE_STDLIB=1
ifeq ($(BUILD_PERSISTENT),1)
  MAKEARGS += $(MAKEARGS_PERSISTENT)
endif
MAKEARGS_NATIVE=PLATFORM_ARCHFLAGS=""
ifeq ($(BUILD_NATIVE),1)
  MAKEARGS += $(MAKEARGS_NATIVE)
endif


.PHONY: all all_build all_clean clean

all: $(PROJECTS:%=full_%) $(PROJECTS_MANUAL:%=full_%)

all_build: $(PROJECTS:%=build_%) $(PROJECTS_MANUAL:%=build_%)

all_clean: $(PROJECTS:%=clean_%) $(PROJECTS_MANUAL:%=clean_%)

all_en: $(PROJECTS:%=full_%)

full_en_%:
	$(MAKE) $(MAKEARGS) -C $(subst full_,,$@) -f ../base.mk

build_en_%:
	$(MAKE) $(MAKEARGS) -C $(subst build_,,$@) -f ../base.mk build

clean_en_%:
	$(MAKE) $(MAKEARGS) -C $(subst clean_,,$@) -f ../base.mk clean

full_mn_%:
	$(MAKE) $(MAKEARGS) -C $(subst full_,,$@)

build_mn_%:
	$(MAKE) $(MAKEARGS) -C $(subst build_,,$@) build

clean_mn_%:
	$(MAKE) $(MAKEARGS) -C $(subst clean_,,$@) clean

clean:
	rm -rf en*/bin
	rm -rf en*/elf

