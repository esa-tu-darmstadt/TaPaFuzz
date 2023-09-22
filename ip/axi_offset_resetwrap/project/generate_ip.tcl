create_project -force dummy dummy -part xc7z020clg400-1
set ipname axi_offset_resetwrap_8_6

ipx::infer_core -vendor esa.informatik.tu-darmstadt.de -library axi_offset_resetwrap -taxonomy /UserIP IP
ipx::edit_ip_in_project -upgrade true -name edit_ip_project -directory dummy.tmp IP/component.xml
ipx::current_core IP/component.xml
set_property name "${ipname}" [ipx::current_core]
update_compile_order -fileset sources_1
ipx::remove_bus_interface rst [ipx::current_core]
ipx::remove_bus_interface rstn [ipx::current_core]
set_property name Mem0 [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi -of_objects [ipx::current_core]]]
set_property usage memory [ipx::get_address_blocks Mem0 -of_objects [ipx::get_memory_maps s_axi -of_objects [ipx::current_core]]]
set_property previous_version_for_upgrade "esa.informatik.tu-darmstadt.de:axi_offset_resetwrap:${ipname}:1.0" [ipx::current_core]
set_property core_revision 1 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
ipx::check_integrity -quiet [ipx::current_core]
ipx::archive_core "../esa.informatik.tu-darmstadt.de_axi_offset_resetwrap_8_6_1.0.zip" [ipx::current_core]
ipx::move_temp_component_back -component [ipx::current_core]
close_project -delete
set_property ip_repo_paths IP [current_project]
update_ip_catalog
exit
