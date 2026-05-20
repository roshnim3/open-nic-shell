// *************************************************************************
// cpu user-plugin: placeholder. Box0 routes BAR2 directly to cpu_stub
// from user_plugin_250mhz_inst.vh, so this module is never instantiated.
// Kept as an empty stub because build.tcl unconditionally read_verilog's
// box_250mhz_address_map.v from the user-plugin box directory.
// *************************************************************************
`timescale 1ns/1ps
module box_250mhz_address_map_unused ();
endmodule
