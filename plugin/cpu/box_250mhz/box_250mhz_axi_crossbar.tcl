# cpu user-plugin: no AXI-Lite crossbar inside Box0. The single cpu_stub
# slave takes the box's 1MB BAR2 window directly (axi_lite_register masks
# the upper bits via its 8-bit ADDR_W).
