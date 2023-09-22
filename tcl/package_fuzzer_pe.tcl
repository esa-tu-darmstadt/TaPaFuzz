ipx::package_project -root_dir fuzzer_ip -vendor esa.informatik.tu-darmstadt.de -library fuzzer -taxonomy /UserIP -module "${_xil_proj_name_}" -import_files -generated_files -force
set_property supported_families {virtex7 Beta qvirtex7 Beta kintex7 Beta kintex7l Beta qkintex7 Beta qkintex7l Beta artix7 Beta artix7l Beta aartix7 Beta qartix7 Beta zynq Beta qzynq Beta azynq Beta spartan7 Beta aspartan7 Beta virtexu Beta virtexuplus Beta kintexuplus Beta zynquplus Beta kintexu Beta virtexuplusHBM Beta} [ipx::current_core]
set core [ipx::current_core]
set_property name "${_xil_proj_name_}_fuzzer" $core
set_property name INTERRUPT [ipx::get_bus_interfaces INTR.INTERRUPT -of_objects $core]
set_property name ARESET_N [ipx::get_bus_interfaces RST.ARESET_N -of_objects $core]
set_property name CLK [ipx::get_bus_interfaces CLK.CLK -of_objects $core]
ipx::remove_bus_parameter PHASE [ipx::get_bus_interfaces CLK -of_objects $core]
ipx::remove_bus_parameter FREQ_HZ [ipx::get_bus_interfaces CLK -of_objects $core]
#set_property name Mem0 [ipx::get_address_blocks Reg0 -of_objects [ipx::get_memory_maps S_AXI_BRAM -of_objects $core]]
set_property core_revision 2 $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core
set_property  ip_repo_paths  "[file normalize "$tapasco_riscv_dir/IP/AXIGate"] [file normalize "$tapasco_riscv_dir/IP/axi_offset"] [file normalize "$origin_dir/ip"] [file normalize "$origin_dir/core/IP"]" [current_project]
update_ip_catalog
ipx::check_integrity -quiet $core
ipx::archive_core "fuzzer_ip/esa.informatik.tu-darmstadt.de_fuzzer_${_xil_proj_name_}_fuzzer_1.0.zip" $core
ipx::unload_core component_1
