#!/bin/bash

# Directories
FSM_CONFIG_FILE=fsm-settings.properties
VERILOGDIR=${BLUESPECDIR}/Verilog
BSC_MACRO_FILE=bsc_macros.txt

ifndef BLUESPECDIR
	$(error BLUESPECDIR is not set)
endif

BUILDDIR?=build
VDIR?=verilog

# Loglevels
# Defined in Logging.bsv; for custom logs: "export FUZZER_LOG_TYPES=L_EXAMPLE"
# These are our default log settings:
FUZZER_LOG_TYPES?="L_ERROR, L_WARNING, L_CF_StateAndFSM"

override BSC_MACROS+= $(shell cat ${BSC_MACRO_FILE}) -D FUZZER_LOG_TYPES=$(FUZZER_LOG_TYPES) -bdir $(BUILDDIR) -simdir $(BUILDDIR) -vdir $(VDIR) -check-assert
BSC_SRC_DIRS=./axi:./cf:./wrappers

showBscMacro:
	echo $(BSC_MACROS)

packageCore_%_hbm: buildFuzzerCoreWrapper_% 
	vivado -nolog -nojournal -mode batch -source ../tcl/fuzzer_ip.tcl -tclargs $*_hbm
	rm -rf dummy*
packageCore_%: buildFuzzerCoreWrapper_% 
	vivado -nolog -nojournal -mode batch -source ../tcl/fuzzer_ip.tcl -tclargs $*
	rm -rf dummy*

Test%: clean builddir
	clear
	bsc $(BSC_MACROS) -u -sim -g mk$@ $@.bsv
	bsc $(BSC_MACROS) -sim -o $@ -e mk$@
	./$@
	rm -f $@

build%: builddir
	# Always rebuild FuzzerCore.bo in case of changes in BSC_MACROS.
	rm -f build/FuzzerCore.bo
	bsc $(BSC_MACROS) -p $(BSC_INCLUDES):$(BSC_SRC_DIRS):+ -u -verilog -show-range-conflict -g mk$* ./wrappers/$*.bsv
	mkdir -p IP
	rm -f IP/mk*.v
	cp -f $(VDIR)/mk$*.v IP/
	cp $(VERILOGDIR)/RegFile.v $(VERILOGDIR)/RevertReg.v $(VERILOGDIR)/SizedFIFO.v $(VERILOGDIR)/BRAM1.v $(VERILOGDIR)/BRAM2.v  $(VERILOGDIR)/FIFO2.v $(VERILOGDIR)/FIFO1.v IP/


builddir:
	mkdir -p $(BUILDDIR)
	mkdir -p $(VDIR)

clean:
	@rm -rf IP $(BUILDDIR) $(VDIR)
	@rm -f dump.vcd
	@rm -f *.ba *.*o *.h *.cxx *.v
	@rm -rf .Xil
	@find . -maxdepth 1 -type f -executable -delete
	@echo "make clean successful"
