#!/bin/bash

# Directories
VERILOGDIR=${BLUESPECDIR}/Verilog

ifndef BLUESPECDIR
	$(error BLUESPECDIR is not set)
endif

BUILDDIR?=build
VDIR?=verilog

BSC_MACROS+= -bdir $(BUILDDIR) -simdir $(BUILDDIR) -vdir $(VDIR) -check-assert
BSC_SRC_DIRS=./axi:

all: packageCore

showBscMacro:
	echo $(BSC_MACROS)

builddir:
	mkdir -p $(BUILDDIR)
	mkdir -p $(VDIR)

Test%: clean builddir
	clear
	bsc $(BSC_MACROS) -u -sim -g mk$@ $@.bsv
	bsc $(BSC_MACROS) -sim -o $@ -e mk$@
	./$@
	rm -f $@

build: builddir
	bsc $(BSC_MACROS) -p $(BSC_INCLUDES):$(BSC_SRC_DIRS)+ -u -verilog -show-range-conflict -g mkAXIOffsetReset_8_6 ./AXIOffsetReset.bsv
	mkdir -p IP
	rm -f IP/mk*.v
	cp -f $(VDIR)/mkAXIOffsetReset*.v IP/
	cp $(VERILOGDIR)/SizedFIFO.v IP/

packageCore: build 
	vivado -nolog -nojournal -mode batch -source generate_ip.tcl
	@rm -rf dummy*
	@rm -rf ../xgui
	@rm -rf ../component.xml
	@rm -rf ../*.v
	mv IP/* ../
	
clean:
	@rm -rf IP $(BUILDDIR) $(VDIR)
	@rm -f *.ba *.*o
	@rm -rf ../xgui
	@rm -rf ../component.xml
	@rm -rf ../*.v
	@rm -rf .Xil
	@find . -maxdepth 1 -type f -executable -delete
	@echo "make clean successful"
