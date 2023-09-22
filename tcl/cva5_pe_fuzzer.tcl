#*****************************************************************************************
# Vivado (TM) v2019.1 (64-bit)
#
# cva5_pe_fuzzer.tcl: Tcl script for re-creating project 'cva5_pe'
#
# This file contains the Vivado Tcl commands for re-creating the project to the state*
# when this script was generated. In order to re-create the project, please source this
# file in the Vivado Tcl Shell.
#
# * Note that the runs in the created project will be configured the same way as the
#   original project, however they will not be launched automatically. To regenerate the
#   run results please launch the synthesis/implementation runs as needed.
#
#*****************************************************************************************
# NOTE: In order to use this script for source control purposes, please make sure that the
#       following files are added to the source control system:-
#
# 1. This project restoration tcl script (cva5_pe_fuzzer.tcl) that was generated.
#
# 2. The following source(s) files that were local or imported into the original project.
#    (Please see the '$orig_proj_dir' and '$origin_dir' variable setting below at the start of the script)
#
# 3. The following remote source files that were added to the original project:-
#
#    <none>
#
#*****************************************************************************************

# Set the reference directory for source file relative paths (by default the value is script directory path)
set origin_dir "."

# Use origin directory path location variable, if specified in the tcl shell
if { [info exists ::origin_dir_loc] } {
  set origin_dir $::origin_dir_loc
}

# Set the project name
set _xil_proj_name_ "cva5_pe"

# Use project name variable, if specified in the tcl shell
if { [info exists ::user_project_name] } {
  set _xil_proj_name_ $::user_project_name
}

variable script_file
set script_file "cva5_pe_fuzzer.tcl"

# Help information for this script
proc print_help {} {
  variable script_file
  puts "\nDescription:"
  puts "Recreate a Vivado project from this script. The created project will be"
  puts "functionally equivalent to the original project for which this script was"
  puts "generated. The script contains commands for creating a project, filesets,"
  puts "runs, adding/importing sources and setting properties on various objects.\n"
  puts "Syntax:"
  puts "$script_file"
  puts "$script_file -tclargs \[--origin_dir <path>\]"
  puts "$script_file -tclargs \[--project_name <name>\]"
  puts "$script_file -tclargs \[--help\]\n"
  puts "Usage:"
  puts "Name                   Description"
  puts "-------------------------------------------------------------------------"
  puts "\[--origin_dir <path>\]  Determine source file paths wrt this path. Default"
  puts "                       origin_dir path value is \".\", otherwise, the value"
  puts "                       that was set with the \"-paths_relative_to\" switch"
  puts "                       when this script was generated.\n"
  puts "\[--project_name <name>\] Create project with the specified name. Default"
  puts "                       name is the name of the project from where this"
  puts "                       script was generated.\n"
  puts "\[--help\]               Print help information for this script"
  puts "-------------------------------------------------------------------------\n"
  exit 0
}

set enable_bram 0
set enable_hbm 0

if { $::argc > 0 } {
  for {set i 0} {$i < $::argc} {incr i} {
    set option [string trim [lindex $::argv $i]]
    switch -regexp -- $option {
      "--origin_dir"    { incr i; set origin_dir [lindex $::argv $i] }
      "--project_name"  { incr i; set _xil_proj_name_ [lindex $::argv $i] }
      "--tapasco_riscv" { incr i; set tapasco_riscv_dir [lindex $::argv $i] }
      "--fuzzerMemSize" { incr i; set fuzzerMemSize [lindex $::argv $i] }
      "--bram"          { set enable_bram 1 }
      "--hbm"           { set enable_hbm 1 }
      "--help"          { print_help }
      default {
        if { [regexp {^-} $option] } {
          puts "ERROR: Unknown option '$option' specified, please type '$script_file -tclargs --help' for usage info.\n"
          return 1
        }
      }
    }
  }
}
if { $enable_bram == 1 && $enable_hbm == 1 } {
  puts "ERROR: BRAM and HBM modes cannot be enabled simultaneously.\n"
  return 1
}

# Set the directory path for the original project from where this script was exported
set orig_proj_dir "[file normalize "$origin_dir/${_xil_proj_name_}"]"

# Create project
create_project -force ${_xil_proj_name_} ./${_xil_proj_name_} -part xc7z020clg400-1

# Set the directory path for the new project
set proj_dir [get_property directory [current_project]]

# Calculate range of AXI BRAM slave
set program_size 0x00010000
if { $enable_hbm == 1 } {
  set program_size 0x00800000
}

set instr_bram_size $program_size
set data_bram_size $program_size
set addr_width [expr {int(ceil(log10($instr_bram_size+$data_bram_size+$fuzzerMemSize)/log10(2)))}]
set range [expr {int(pow(2, $addr_width))}]

# Set project properties
set obj [current_project]
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "dsa.num_compute_units" -value "60" -objects $obj
set_property -name "ip_cache_permissions" -value "read write" -objects $obj
set_property -name "ip_output_repo" -value "$proj_dir/${_xil_proj_name_}.cache/ip" -objects $obj
set_property -name "part" -value "xc7z020clg400-1" -objects $obj
set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj
set_property -name "xpm_libraries" -value "XPM_CDC XPM_MEMORY" -objects $obj
set_property -name "dsa.accelerator_binary_content" -value "bitstream" -objects $obj
set_property -name "dsa.accelerator_binary_format" -value "xclbin2" -objects $obj
set_property -name "dsa.description" -value "Vivado generated DSA" -objects $obj
set_property -name "dsa.dr_bd_base_address" -value "0" -objects $obj
set_property -name "dsa.emu_dir" -value "emu" -objects $obj
set_property -name "dsa.flash_interface_type" -value "bpix16" -objects $obj
set_property -name "dsa.flash_offset_address" -value "0" -objects $obj
set_property -name "dsa.flash_size" -value "1024" -objects $obj
set_property -name "dsa.host_architecture" -value "x86_64" -objects $obj
set_property -name "dsa.host_interface" -value "pcie" -objects $obj
set_property -name "dsa.platform_state" -value "pre_synth" -objects $obj
set_property -name "dsa.vendor" -value "xilinx" -objects $obj
set_property -name "dsa.version" -value "0.0" -objects $obj
set_property -name "enable_vhdl_2008" -value "1" -objects $obj
set_property -name "mem.enable_memory_map_generation" -value "1" -objects $obj
set_property -name "sim.central_dir" -value "$proj_dir/${_xil_proj_name_}.ip_user_files" -objects $obj

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

# Set IP repository paths
set obj [get_filesets sources_1]
set_property "ip_repo_paths" "[file normalize "$tapasco_riscv_dir/IP/AXIGate"] [file normalize "$tapasco_riscv_dir/IP/axi_offset"] [file normalize "$origin_dir/ip"] [file normalize "$origin_dir/core/IP"]" $obj

# Rebuild user ip_repo's index before adding any source files
update_ip_catalog -rebuild

# Set 'sources_1' fileset object
set obj [get_filesets sources_1]
# Import local files from the original project
#set files [list  \
# [file normalize "${origin_dir}/cva5_pe_wrapper.v" ]\
#]
#set imported_files [import_files -fileset sources_1 $files]
set imported_files [import_files -fileset sources_1]

# Set 'sources_1' fileset file properties for remote files
# None

# Set 'sources_1' fileset file properties for local files
# None

# Set 'sources_1' fileset properties
set obj [get_filesets sources_1]
set_property -name "top" -value "mkCore" -objects $obj

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Set 'constrs_1' fileset object
set obj [get_filesets constrs_1]

# Empty (no sources present)

# Set 'constrs_1' fileset properties
set obj [get_filesets constrs_1]
set_property -name "target_part" -value "xc7z020clg400-1" -objects $obj

# Create 'sim_1' fileset (if not found)
if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

# Set 'sim_1' fileset object
set obj [get_filesets sim_1]
# Empty (no sources present)

# Set 'sim_1' fileset properties
set obj [get_filesets sim_1]
set_property -name "top" -value "cva5_axi" -objects $obj
set_property -name "top_lib" -value "xil_defaultlib" -objects $obj

# Set 'utils_1' fileset object
set obj [get_filesets utils_1]
# Empty (no sources present)

# Set 'utils_1' fileset properties
set obj [get_filesets utils_1]


# Adding sources referenced in BDs, if not already added


# Proc to create BD cva5_pe
proc cr_bd_cva5_pe { _xil_proj_name_ parentCell addr_width range fuzzerMemSize enable_bram enable_hbm } {

  # CHANGE DESIGN NAME HERE
  if { $enable_bram == 1 } {
    set design_name cva5_bram_pe
  } elseif { $enable_hbm == 1 } {
    set design_name cva5_hbm_pe
  } else {
    set design_name cva5_pe
  }

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

  set bCheckIPsPassed 1
  ##################################################################
  # CHECK IPs
  ##################################################################
  set bCheckIPs 1
  if { $bCheckIPs == 1 } {
     set list_check_ips "\ 
  esa.informatik.tu-darmstadt.de:tapasco:AXIGate:1.0\
  esa.informatik.tu-darmstadt.de:axi_offset_resetwrap:axi_offset_resetwrap_8_6:1.0\
  esa.cs.tu-darmstadt.de:axi:axi_offset:0.1\
  xilinx.com:ip:blk_mem_gen:8.4\
  openhwgroup:cva5:cva5:0.1\
  openhwgroup:cva5:cva5_bram:0.1\
  xilinx.com:ip:axi_bram_ctrl:4.1\
  xilinx.com:ip:proc_sys_reset:5.0\
  xilinx.com:ip:smartconnect:1.0\
  "
   if { $enable_hbm == 1 } {
     append list_check_ips "esa.informatik.tu-darmstadt.de:fuzzer:fuzzercore_cva5_hbm:1.0\
     "
   } else {
     append list_check_ips "esa.informatik.tu-darmstadt.de:fuzzer:fuzzercore_cva5:1.0\
     "
   }

   set list_ips_missing ""
   common::send_msg_id "BD_TCL-006" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_msg_id "BD_TCL-115" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

  }

  if { $bCheckIPsPassed != 1 } {
    common::send_msg_id "BD_TCL-1003" "WARNING" "Will not continue with creation of design due to the error(s) above."
    return 3
  }

  variable script_folder

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports

  # set M_AXIS_FUZZ_OUT [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_FUZZOUT ]
  # set_property -dict [ list \
  #  CONFIG.PROTOCOL {AXI4} \
  # ] $M_AXI


  set S_AXI_BRAM [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_BRAM ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH $addr_width \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {1} \
   CONFIG.HAS_CACHE {1} \
   CONFIG.HAS_LOCK {1} \
   CONFIG.HAS_PROT {1} \
   CONFIG.HAS_QOS {1} \
   CONFIG.HAS_REGION {1} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {6} \
   CONFIG.MAX_BURST_LENGTH {256} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.SUPPORTS_NARROW_BURST {1} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
   ] $S_AXI_BRAM

  set S_AXI_CTRL [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_CTRL ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {16} \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {1} \
   CONFIG.HAS_CACHE {1} \
   CONFIG.HAS_LOCK {1} \
   CONFIG.HAS_PROT {1} \
   CONFIG.HAS_QOS {1} \
   CONFIG.HAS_REGION {1} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {0} \
   CONFIG.MAX_BURST_LENGTH {1} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4LITE} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.SUPPORTS_NARROW_BURST {0} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
   ] $S_AXI_CTRL


  # Create ports
  set ARESET_N [ create_bd_port -dir I -type rst ARESET_N ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $ARESET_N
  set CLK [ create_bd_port -dir I -type clk CLK ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S_AXI_BRAM:S_AXI_CTRL} \
 ] $CLK
  set interrupt [ create_bd_port -dir O -type intr interrupt ]

  # Create instance: AXIGate_0, and set properties
  set AXIGate_0 [ create_bd_cell -type ip -vlnv esa.informatik.tu-darmstadt.de:tapasco:AXIGate:1.0 AXIGate_0 ]
  set_property -dict [ list \
   CONFIG.threshold {0x00004000} \
 ] $AXIGate_0

  # Create instance: axi_interconnect_0, and set properties
  set axi_interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0 ]
  set_property -dict [ list \
   CONFIG.NUM_MI {1} \
   CONFIG.NUM_SI {2} \
 ] $axi_interconnect_0

  # Create instance: bmpmem, and set properties
  set bmpmem [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bmpmem ]
  set_property -dict [ list \
   CONFIG.Assume_Synchronous_Clk {true} \
   CONFIG.EN_SAFETY_CKT {false} \
   CONFIG.Memory_Type {Single_Port_RAM} \
 ] $bmpmem

  # Create instance: ps_bmpmem_ctrl, and set properties
  set ps_bmpmem_ctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 ps_bmpmem_ctrl ]
  set_property -dict [ list \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.SINGLE_PORT_BRAM {1} \
 ] $ps_bmpmem_ctrl

  # Create instance: rst_CLK_100M, and set properties
  set rst_CLK_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_CLK_100M ]
  
  if { $enable_bram == 1 } {
	# Create instance: fuzzercore_0, and set properties
	set fuzzercore_0 [ create_bd_cell -type ip -vlnv esa.informatik.tu-darmstadt.de:fuzzer:fuzzercore_cva5:1.0 fuzzercore_0 ]
	
    # Create instance: cva5_0, and set properties
    set cva5_0 [ create_bd_cell -type ip -vlnv openhwgroup:cva5:cva5_bram:0.1 cva5_0 ]
	
    # Create instance: axi_interconnect_1, and set properties
    set axi_interconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_1 ]
    set_property -dict [ list \
      CONFIG.STRATEGY {1} \
      CONFIG.NUM_MI {3} \
      CONFIG.NUM_SI {1} \
    ] $axi_interconnect_1

    # Create instance: dmem, and set properties
    set dmem [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 dmem ]
    set_property -dict [ list \
      CONFIG.Assume_Synchronous_Clk {true} \
      CONFIG.EN_SAFETY_CKT {false} \
      CONFIG.Enable_B {Use_ENB_Pin} \
      CONFIG.Memory_Type {True_Dual_Port_RAM} \
      CONFIG.Port_B_Clock {100} \
      CONFIG.Port_B_Enable_Rate {100} \
      CONFIG.Port_B_Write_Rate {50} \
      CONFIG.Use_RSTB_Pin {true} \
    ] $dmem
  
    # Create instance: imem, and set properties
    set imem [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 imem ]
    set_property -dict [ list \
      CONFIG.Assume_Synchronous_Clk {true} \
      CONFIG.EN_SAFETY_CKT {false} \
      CONFIG.Enable_B {Use_ENB_Pin} \
      CONFIG.Memory_Type {True_Dual_Port_RAM} \
      CONFIG.Port_B_Clock {100} \
      CONFIG.Port_B_Enable_Rate {100} \
      CONFIG.Port_B_Write_Rate {50} \
      CONFIG.Use_RSTB_Pin {true} \
    ] $imem

    # Create instance: ps_dmem_ctrl, and set properties
    set ps_dmem_ctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 ps_dmem_ctrl ]
    set_property -dict [ list \
      CONFIG.DATA_WIDTH {32} \
      CONFIG.SINGLE_PORT_BRAM {1} \
    ] $ps_dmem_ctrl
   
    # Create instance: ps_imem_ctrl, and set properties
    set ps_imem_ctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 ps_imem_ctrl ]
    set_property -dict [ list \
      CONFIG.DATA_WIDTH {32} \
      CONFIG.SINGLE_PORT_BRAM {1} \
    ] $ps_imem_ctrl
	
	
    connect_bd_intf_net -intf_net axi_interconnect_1_M00_AXI [get_bd_intf_pins axi_interconnect_1/M00_AXI] [get_bd_intf_pins ps_imem_ctrl/S_AXI]
    connect_bd_intf_net -intf_net axi_interconnect_1_M01_AXI [get_bd_intf_pins axi_interconnect_1/M01_AXI] [get_bd_intf_pins ps_dmem_ctrl/S_AXI]
    connect_bd_intf_net -intf_net axi_interconnect_1_M02_AXI [get_bd_intf_pins axi_interconnect_1/M02_AXI] [get_bd_intf_pins ps_bmpmem_ctrl/S_AXI]
    connect_bd_intf_net -intf_net fuzzercore_0_m_axi_cpu_mem [get_bd_intf_pins axi_interconnect_1/S00_AXI] [get_bd_intf_pins fuzzercore_0/m_axi_cpu_mem]
    connect_bd_intf_net -intf_net cva5_0_data_bram [get_bd_intf_pins dmem/BRAM_PORTA] [get_bd_intf_pins cva5_0/data_bram]
    connect_bd_intf_net -intf_net cva5_0_instruction_bram [get_bd_intf_pins imem/BRAM_PORTA] [get_bd_intf_pins cva5_0/instruction_bram]
    connect_bd_intf_net -intf_net ps_dmem_ctrl_BRAM_PORTA [get_bd_intf_pins dmem/BRAM_PORTB] [get_bd_intf_pins ps_dmem_ctrl/BRAM_PORTA]
    connect_bd_intf_net -intf_net ps_imem_ctrl_BRAM_PORTA [get_bd_intf_pins imem/BRAM_PORTB] [get_bd_intf_pins ps_imem_ctrl/BRAM_PORTA]
	
    connect_bd_net -net cva5_0_rst [get_bd_pins fuzzercore_0/rst] [get_bd_pins cva5_0/rst]
    connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_1/ACLK] [get_bd_pins axi_interconnect_1/M00_ACLK] [get_bd_pins axi_interconnect_1/M01_ACLK] [get_bd_pins axi_interconnect_1/M02_ACLK] [get_bd_pins axi_interconnect_1/S00_ACLK] [get_bd_pins ps_dmem_ctrl/s_axi_aclk] [get_bd_pins ps_imem_ctrl/s_axi_aclk]
    connect_bd_net -net rst_CLK_100M_interconnect_aresetn [get_bd_pins axi_interconnect_1/ARESETN]
    connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_1/M00_ARESETN] [get_bd_pins axi_interconnect_1/M01_ARESETN] [get_bd_pins axi_interconnect_1/M02_ARESETN] [get_bd_pins axi_interconnect_1/S00_ARESETN] [get_bd_pins ps_dmem_ctrl/s_axi_aresetn] [get_bd_pins ps_imem_ctrl/s_axi_aresetn]
	
    create_bd_addr_seg -range 0x00010000 -offset 0x00010000 [get_bd_addr_spaces fuzzercore_0/m_axi_cpu_mem] [get_bd_addr_segs ps_dmem_ctrl/S_AXI/Mem0] SEG_ps_dmem_ctrl_Mem0
    create_bd_addr_seg -range 0x00010000 -offset 0x00000000 [get_bd_addr_spaces fuzzercore_0/m_axi_cpu_mem] [get_bd_addr_segs ps_imem_ctrl/S_AXI/Mem0] SEG_ps_imem_ctrl_Mem0
    create_bd_addr_seg -range $fuzzerMemSize -offset 0x00020000 [get_bd_addr_spaces fuzzercore_0/m_axi_cpu_mem] [get_bd_addr_segs ps_bmpmem_ctrl/S_AXI/Mem0] SEG_ps_bmpmem_ctrl_Mem0
  } elseif { $enable_hbm == 1 } {
	# Create instance: fuzzercore_0, and set properties
	set fuzzercore_0 [ create_bd_cell -type ip -vlnv esa.informatik.tu-darmstadt.de:fuzzer:fuzzercore_cva5_hbm:1.0 fuzzercore_0 ]
	
    # Create instance: cva5_0, and set properties
    set cva5_0 [ create_bd_cell -type ip -vlnv openhwgroup:cva5:cva5:0.1 cva5_0 ]
	
    # Create instance: axi_interconnect_1, and set properties
    set axi_interconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_1 ]
    set_property -dict [ list \
      CONFIG.STRATEGY {1} \
      CONFIG.NUM_MI {2} \
      CONFIG.NUM_SI {1} \
    ] $axi_interconnect_1
    
	set M_AXI [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI ]
    set_property -dict [ list \
      CONFIG.ADDR_WIDTH {32} \
      CONFIG.DATA_WIDTH {32} \
      CONFIG.PROTOCOL {AXI4} \
    ] $M_AXI

    # Create instance: coreMemShim, and set properties
    set coreMemShim [ create_bd_cell -type ip -vlnv esa.informatik.tu-darmstadt.de:axi_offset_resetwrap:axi_offset_resetwrap_8_6:1.0 coreMemShim ]
	
    # Create instance: axi_interconnect_2, and set properties
    set axi_interconnect_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_2 ]
    set_property -dict [ list \
      CONFIG.STRATEGY {1} \
      CONFIG.NUM_MI {1} \
      CONFIG.NUM_SI {2} \
    ] $axi_interconnect_2
	
	# Fuzzer -> axi_interconnect_1 -> {bmpmem, axi_interconnect_2}
	# CVA5 -> coreMemShim -> axi_interconnect_2 -> M_AXI
	
    connect_bd_intf_net -intf_net fuzzercore_0_m_axi_cpu_mem [get_bd_intf_pins fuzzercore_0/m_axi_cpu_mem] [get_bd_intf_pins axi_interconnect_1/S00_AXI]
    connect_bd_intf_net -intf_net axi_interconnect_1_M00_AXI [get_bd_intf_pins axi_interconnect_1/M00_AXI] [get_bd_intf_pins axi_interconnect_2/S00_AXI]
    connect_bd_intf_net -intf_net axi_interconnect_1_M01_AXI [get_bd_intf_pins axi_interconnect_1/M01_AXI] [get_bd_intf_pins ps_bmpmem_ctrl/S_AXI]
    connect_bd_intf_net -intf_net cva5_0_m_axi_cache [get_bd_intf_pins cva5_0/m_axi_cache] [get_bd_intf_pins coreMemShim/s_axi]
    connect_bd_intf_net -intf_net coreMemShim_M_AXI [get_bd_intf_pins coreMemShim/m_axi] [get_bd_intf_pins axi_interconnect_2/S01_AXI]
    connect_bd_intf_net -intf_net axi_interconnect_2_M00_AXI [get_bd_intf_pins axi_interconnect_2/M00_AXI] [get_bd_intf_ports M_AXI]
	
    connect_bd_net -net fuzzercore_0_rst [get_bd_pins fuzzercore_0/rst] [get_bd_pins coreMemShim/core_rst_in]
    connect_bd_net -net cva5_0_rst [get_bd_pins coreMemShim/core_rst] [get_bd_pins cva5_0/rst]
    connect_bd_net -net fuzzercore_0_setup_sectionid_val [get_bd_pins fuzzercore_0/setup_sectionid_val] [get_bd_pins coreMemShim/setup_sectionid]
    connect_bd_net -net fuzzercore_0_setup_sectionid_en [get_bd_pins fuzzercore_0/setup_sectionid_en] [get_bd_pins coreMemShim/EN_setup]
	
	#save_bd_design $design_name
    #close_bd_design $design_name 
    #open_bd_design ./${_xil_proj_name_}/${_xil_proj_name_}.srcs/sources_1/bd/${design_name}/${design_name}.bd
	
    connect_bd_net -net CLK_1 [get_bd_pins coreMemShim/clk]
	connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins coreMemShim/RST_N]
	
	# Weird Vivado bug(?):
	# With several  connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_1/ACLK] [get_bd_pins axi_interconnect_1/M00_ACLK] (...) :
	# ERROR: [BD 41-738] Exec TCL: the object '/axi_interconnect_1' is part of the appcore 'axi_interconnect_1' and cannot be modified directly.
	# 
	# Apparently works in all other instances of the exact same thing, and also works if every pin gets its own connect_bd_net command ...
    connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_1/ACLK]
	connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_1/M00_ACLK]
	connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_1/M01_ACLK]
	connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_1/S00_ACLK]
    connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_2/ACLK]
    connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_2/M00_ACLK]
    connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_2/S00_ACLK]
    connect_bd_net -net CLK_1 [get_bd_pins axi_interconnect_2/S01_ACLK]
    connect_bd_net -net rst_CLK_100M_interconnect_aresetn [get_bd_pins axi_interconnect_1/ARESETN]
    connect_bd_net -net rst_CLK_100M_interconnect_aresetn [get_bd_pins axi_interconnect_2/ARESETN]
	connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_1/M00_ARESETN]
	connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_1/M01_ARESETN]
	connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_1/S00_ARESETN]
    connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_2/M00_ARESETN]
	connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_2/S00_ARESETN]
	connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins axi_interconnect_2/S01_ARESETN]  
	
    create_bd_addr_seg -range 0x01000000 -offset 0x00000000 [get_bd_addr_spaces cva5_0/m_axi_cache] [get_bd_addr_segs coreMemShim/s_axi/Mem0] SEG_coreMemShim_reg0
    create_bd_addr_seg -range 0x01000000 -offset 0x00000000 [get_bd_addr_spaces coreMemShim/m_axi] [get_bd_addr_segs M_AXI/Reg] SEG_MAXI_Reg_core
    create_bd_addr_seg -range 0x01000000 -offset 0x00000000 [get_bd_addr_spaces fuzzercore_0/m_axi_cpu_mem] [get_bd_addr_segs M_AXI/Reg] SEG_MAXI_Reg_fuzz
    create_bd_addr_seg -range $fuzzerMemSize -offset 0x01000000 [get_bd_addr_spaces fuzzercore_0/m_axi_cpu_mem] [get_bd_addr_segs ps_bmpmem_ctrl/S_AXI/Mem0] SEG_ps_bmpmem_ctrl_Mem0


  } else { #if { $enable_bram == 0 && $enable_hbm == 0 }
	# Create instance: fuzzercore_0, and set properties
	set fuzzercore_0 [ create_bd_cell -type ip -vlnv esa.informatik.tu-darmstadt.de:fuzzer:fuzzercore_cva5:1.0 fuzzercore_0 ]
	
    # Create instance: cva5_0, and set properties
    set cva5_0 [ create_bd_cell -type ip -vlnv openhwgroup:cva5:cva5:0.1 cva5_0 ]
    
    set M_AXI [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI ]
    set_property -dict [ list \
      CONFIG.ADDR_WIDTH {32} \
      CONFIG.DATA_WIDTH {32} \
      CONFIG.PROTOCOL {AXI4} \
    ] $M_AXI

    # Create instance: coreMemShim, and set properties
    set coreMemShim [ create_bd_cell -type ip -vlnv esa.informatik.tu-darmstadt.de:axi_offset_resetwrap:axi_offset_resetwrap_8_6:1.0 coreMemShim ]
	
    connect_bd_intf_net -intf_net fuzzercore_0_m_axi_cpu_mem [get_bd_intf_pins ps_bmpmem_ctrl/S_AXI] [get_bd_intf_pins fuzzercore_0/m_axi_cpu_mem]
	
    connect_bd_intf_net -intf_net coreMemShim_M_AXI [get_bd_intf_ports M_AXI] [get_bd_intf_pins coreMemShim/m_axi]
    connect_bd_intf_net -intf_net cva5_0_m_axi_cache [get_bd_intf_pins coreMemShim/s_axi] [get_bd_intf_pins cva5_0/m_axi_cache]
	
    connect_bd_net -net fuzzercore_0_rst [get_bd_pins fuzzercore_0/rst] [get_bd_pins coreMemShim/core_rst_in]
    connect_bd_net -net cva5_0_rst [get_bd_pins coreMemShim/core_rst] [get_bd_pins cva5_0/rst]
    connect_bd_net -net fuzzercore_0_setup_sectionid_val [get_bd_pins fuzzercore_0/setup_sectionid_val] [get_bd_pins coreMemShim/setup_sectionid]
    connect_bd_net -net fuzzercore_0_setup_sectionid_en [get_bd_pins fuzzercore_0/setup_sectionid_en] [get_bd_pins coreMemShim/EN_setup]
    
    connect_bd_net -net CLK_1 [get_bd_pins coreMemShim/clk]
    connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins coreMemShim/RST_N] 
	
    create_bd_addr_seg -range 0x000100000000 -offset 0x00000000 [get_bd_addr_spaces coreMemShim/m_axi] [get_bd_addr_segs M_AXI/Reg] SEG_MAXI_Reg
    create_bd_addr_seg -range 0x000100000000 -offset 0x00000000 [get_bd_addr_spaces cva5_0/m_axi_cache] [get_bd_addr_segs coreMemShim/s_axi/Mem0] SEG_coreMemShim_reg0
    create_bd_addr_seg -range $fuzzerMemSize -offset 0x00020000 [get_bd_addr_spaces fuzzercore_0/m_axi_cpu_mem] [get_bd_addr_segs ps_bmpmem_ctrl/S_AXI/Mem0] SEG_ps_bmpmem_ctrl_Mem0
  }

  # Create interface connections
  connect_bd_intf_net -intf_net AXIGate_0_maxi [get_bd_intf_pins AXIGate_0/maxi] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
  connect_bd_intf_net -intf_net S_AXI_BRAM_1 [get_bd_intf_ports S_AXI_BRAM] [get_bd_intf_pins fuzzercore_0/s_axi_bram]
  connect_bd_intf_net -intf_net S_AXI_CTRL_1 [get_bd_intf_ports S_AXI_CTRL] [get_bd_intf_pins AXIGate_0/saxi]
  connect_bd_intf_net -intf_net axi_interconnect_0_M00_AXI [get_bd_intf_pins fuzzercore_0/s_axi_ctrl] [get_bd_intf_pins axi_interconnect_0/M00_AXI]
  connect_bd_intf_net -intf_net cva5_0_m_axi [get_bd_intf_pins axi_interconnect_0/S01_AXI] [get_bd_intf_pins cva5_0/m_axi]
  # connect_bd_intf_net [get_bd_intf_ports M_AXIS_FUZZOUT] [get_bd_intf_pins fuzzercore_0/m_axis_fuzzOut]
  
  connect_bd_intf_net -intf_net ps_bmpmem_ctrl_BRAM_PORTA [get_bd_intf_pins bmpmem/BRAM_PORTA] [get_bd_intf_pins ps_bmpmem_ctrl/BRAM_PORTA]

  # Create port connections
  connect_bd_net -net ARESET_N_1 [get_bd_ports ARESET_N] [get_bd_pins rst_CLK_100M/ext_reset_in]
  connect_bd_net -net CLK_1 [get_bd_ports CLK] [get_bd_pins AXIGate_0/CLK] [get_bd_pins axi_interconnect_0/ACLK] [get_bd_pins axi_interconnect_0/M00_ACLK] [get_bd_pins axi_interconnect_0/S00_ACLK] [get_bd_pins axi_interconnect_0/S01_ACLK] [get_bd_pins fuzzercore_0/CLK] [get_bd_pins ps_bmpmem_ctrl/s_axi_aclk] [get_bd_pins rst_CLK_100M/slowest_sync_clk] [get_bd_pins cva5_0/clk]
  connect_bd_net -net fuzzercore_0_irq [get_bd_ports interrupt] [get_bd_pins fuzzercore_0/irq] [get_bd_pins cva5_0/irq]

  connect_bd_net [get_bd_pins cva5_0/tr_instruction_issued_dec] [get_bd_pins fuzzercore_0/traceSpecInput_trace_rv_i_valid_ip]
  connect_bd_net [get_bd_pins cva5_0/tr_instruction_pc_dec] [get_bd_pins fuzzercore_0/traceSpecInput_trace_rv_i_address_ip]
  connect_bd_net [get_bd_pins cva5_0/tr_instruction_data_dec] [get_bd_pins fuzzercore_0/traceSpecInput_trace_rv_i_insn]
  connect_bd_net [get_bd_pins cva5_0/dexie_stall] [get_bd_pins fuzzercore_0/dexie_stall]
  connect_bd_net [get_bd_pins cva5_0/fuzztr_exception_valid] [get_bd_pins fuzzercore_0/exceptionInput_valid]
  connect_bd_net [get_bd_pins cva5_0/fuzztr_exception_code] [get_bd_pins fuzzercore_0/exceptionInput_cause]
  connect_bd_net [get_bd_pins cva5_0/fuzztr_exception_tval] [get_bd_pins fuzzercore_0/exceptionInput_tval]
  connect_bd_net [get_bd_pins cva5_0/fuzztr_exception_pc] [get_bd_pins fuzzercore_0/exceptionInput_epc]
  connect_bd_net [get_bd_pins cva5_0/icache_set_invalidate_all] [get_bd_pins fuzzercore_0/icacheInvalidate_req]
  connect_bd_net [get_bd_pins cva5_0/icache_invalidating_all] [get_bd_pins fuzzercore_0/icacheInvalidate_pending]
  connect_bd_net [get_bd_pins cva5_0/bp_set_invalidate_all] [get_bd_pins fuzzercore_0/bpInvalidate_req]
  connect_bd_net [get_bd_pins cva5_0/bp_invalidating_all] [get_bd_pins fuzzercore_0/bpInvalidate_pending]
  connect_bd_net [get_bd_pins cva5_0/dcache_set_invalidate_all] [get_bd_pins fuzzercore_0/dcacheInvalidate_req]
  connect_bd_net [get_bd_pins cva5_0/dcache_invalidating_all] [get_bd_pins fuzzercore_0/dcacheInvalidate_pending]

  connect_bd_net -net rst_CLK_100M_interconnect_aresetn [get_bd_pins axi_interconnect_0/ARESETN] [get_bd_pins rst_CLK_100M/interconnect_aresetn]
  connect_bd_net -net rst_CLK_100M_peripheral_aresetn [get_bd_pins AXIGate_0/RST_N] [get_bd_pins axi_interconnect_0/M00_ARESETN] [get_bd_pins axi_interconnect_0/S00_ARESETN] [get_bd_pins axi_interconnect_0/S01_ARESETN] [get_bd_pins ps_bmpmem_ctrl/s_axi_aresetn] [get_bd_pins rst_CLK_100M/peripheral_aresetn] [get_bd_pins fuzzercore_0/RST_N]
  
  # Create address segments
  create_bd_addr_seg -range 0x00004000 -offset 0x11000000 [get_bd_addr_spaces AXIGate_0/maxi] [get_bd_addr_segs fuzzercore_0/s_axi_ctrl/reg0] SEG_fuzzercore_0_reg0
  create_bd_addr_seg -range 0x00004000 -offset 0x11000000 [get_bd_addr_spaces cva5_0/m_axi] [get_bd_addr_segs fuzzercore_0/s_axi_ctrl/reg0] SEG_fuzzercore_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x00000000 [get_bd_addr_spaces S_AXI_CTRL] [get_bd_addr_segs AXIGate_0/saxi/reg0] SEG_AXIGate_0_reg0
  create_bd_addr_seg -range $range -offset 0x00000000 [get_bd_addr_spaces S_AXI_BRAM] [get_bd_addr_segs fuzzercore_0/s_axi_bram/Mem0] SEG_fuzzercore_0_Mem0
  
  save_bd_design
  
  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
  close_bd_design $design_name 
}
# End of cr_bd_cva5_pe()
cr_bd_cva5_pe $_xil_proj_name_ "" $addr_width $range $fuzzerMemSize $enable_bram $enable_hbm

if { $enable_bram == 1 } {
  set bd_file [get_files cva5_bram_pe.bd]
} elseif { $enable_hbm == 1 } {
  set bd_file [get_files cva5_hbm_pe.bd]
} else {
  set bd_file [get_files cva5_pe.bd]
}
#make_wrapper -files $bd_file -top
#add_files -norecurse [file join cva5_pe_wrapper.v]
set_property synth_checkpoint_mode Singular $bd_file
generate_target all $bd_file




source tcl/package_fuzzer_pe.tcl
