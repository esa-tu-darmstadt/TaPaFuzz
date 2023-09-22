#!/bin/bash

cleanObjects = $(wildcard *_pe) fuzzer_ip .Xil

ifndef TAPASCO_RV_DIR
    $(error TAPASCO_RV_DIR not set)
endif

# Size of the coverage memory
fuzzerMemSize = 0x2000

prep_sim_%: %_pe
	cp fuzzer_ip/esa.informatik.tu-darmstadt.de_fuzzer_$*_pe_fuzzer_1.0.zip testbench/tapasco-pe-tb/tapasco_pe.zip

# Completely build simulation, only one manual step left: run make TEST=<testbench> in tapasco-pe-tb folder
%_sim: prep_sim_% binaries
	clear
	cp testbench/test_riscv.py testbench/tapasco-pe-tb/test_riscv.py
	cp testbench/create_sim_verilog.tcl testbench/tapasco-pe-tb/create_sim_verilog.tcl
	cp testbench/amba.py testbench/tapasco-pe-tb/amba.py
	$(MAKE) -C testbench/tapasco-pe-tb vivado_prj

%_hbm_pe: package_core_%_hbm axi_offset_resetwrap
	vivado -nolog -nojournal -mode batch -source tcl/$*_pe_fuzzer.tcl -tclargs --tapasco_riscv ${TAPASCO_RV_DIR} --fuzzerMemSize ${fuzzerMemSize} --hbm --project_name $*_hbm_pe
%_bram_pe: package_core_% axi_offset_resetwrap
	vivado -nolog -nojournal -mode batch -source tcl/$*_pe_fuzzer.tcl -tclargs --tapasco_riscv ${TAPASCO_RV_DIR} --fuzzerMemSize ${fuzzerMemSize} --bram --project_name $*_bram_pe
%_pe: package_core_% axi_offset_resetwrap
	vivado -nolog -nojournal -mode batch -source tcl/$*_pe_fuzzer.tcl -tclargs --tapasco_riscv ${TAPASCO_RV_DIR} --fuzzerMemSize ${fuzzerMemSize}

showVariables:
	@echo "fuzzerMemSize is "$(fuzzerMemSize)

binaries: 
	$(MAKE) -C testPrograms all_en

package_core_%_hbm:
	cd core && $(MAKE) BSC_MACROS+="-D LOCALMEM_RANGE_EXTENDED=1" packageCore_$*_hbm
package_core_%:
	cd core && $(MAKE) BSC_MACROS+="-D LOCALMEM_RANGE_EXTENDED=0" packageCore_$*


ip/axi_offset_resetwrap/component.xml:
	$(MAKE) -C ip/axi_offset_resetwrap/project
axi_offset_resetwrap: ip/axi_offset_resetwrap/component.xml

### Cleaners ###
cleanTapascoPeTbProject:
	$(MAKE) -C testbench/tapasco-pe-tb clean_viv clean

cleanCore:
	$(MAKE) -C core clean

cleanTestprograms:
	$(MAKE) -C testPrograms all_clean

clean_axi_offset_resetwrap:
	$(MAKE) -C ip/axi_offset_resetwrap/project clean
	rm -f ip/axi_offset_resetwrap/*.zip

### Special Cleaners
cleanTapascoPeTbSimlib:
	$(MAKE) -C testbench/tapasco-pe-tb clean_simlib

cleanCleanObjects:
	rm -rf ${cleanObjects}

## Global Cleaners
clean: cleanCore cleanTestprograms cleanCleanObjects cleanTapascoPeTbProject clean_axi_offset_resetwrap

cleanAll: clean cleanTapascoPeTbSimlib
