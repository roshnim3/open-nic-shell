# *************************************************************************
# cpu user-plugin: read the Box0 stub sources. The address_map placeholder
# (.v) is picked up by build.tcl's read_verilog of ${box_plugin}/${box}_address_map.v
# before this script runs, so we only need to load cpu_stub.sv here.
# *************************************************************************
read_verilog -quiet -sv [file join [file dirname [info script]] cpu_stub.sv]
