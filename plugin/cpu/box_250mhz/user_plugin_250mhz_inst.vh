// *************************************************************************
// cpu user-plugin: Box0 instantiates cpu_stub on the AXI-Lite path and
// terminates the QDMA H2C/C2H and CMAC TX/RX adapter interfaces. The
// pre-CPU datapath (Box1 parser, BAR0/BAR1, CMAC subsystem) is unaffected
// because Box1 falls back to plugin/p2p/box_322mhz/.
// *************************************************************************
localparam C_NUM_USER_BLOCK = 1;

// Unused reset pairs are tied to "done"
assign mod_rst_done[15:C_NUM_USER_BLOCK] = {(16-C_NUM_USER_BLOCK){1'b1}};

cpu_stub cpu_stub_inst (
  .s_axil_awvalid (s_axil_awvalid),
  .s_axil_awaddr  (s_axil_awaddr),
  .s_axil_awready (s_axil_awready),
  .s_axil_wvalid  (s_axil_wvalid),
  .s_axil_wdata   (s_axil_wdata),
  .s_axil_wready  (s_axil_wready),
  .s_axil_bvalid  (s_axil_bvalid),
  .s_axil_bresp   (s_axil_bresp),
  .s_axil_bready  (s_axil_bready),
  .s_axil_arvalid (s_axil_arvalid),
  .s_axil_araddr  (s_axil_araddr),
  .s_axil_arready (s_axil_arready),
  .s_axil_rvalid  (s_axil_rvalid),
  .s_axil_rdata   (s_axil_rdata),
  .s_axil_rresp   (s_axil_rresp),
  .s_axil_rready  (s_axil_rready),

  .mod_rstn       (mod_rstn[0]),
  .mod_rst_done   (mod_rst_done[0]),
  .axil_aclk      (axil_aclk)
);

// QDMA H2C: accept and drop every beat so the host PCIe path never
// back-pressures while no CPU producer exists yet.
assign s_axis_qdma_h2c_tready     = {NUM_PHYS_FUNC*NUM_QDMA{1'b1}};

// QDMA C2H: no producer in M1.
assign m_axis_qdma_c2h_tvalid     = '0;
assign m_axis_qdma_c2h_tdata      = '0;
assign m_axis_qdma_c2h_tkeep      = '0;
assign m_axis_qdma_c2h_tlast      = '0;
assign m_axis_qdma_c2h_tuser_size = '0;
assign m_axis_qdma_c2h_tuser_src  = '0;
assign m_axis_qdma_c2h_tuser_dst  = '0;

// CMAC TX adapter: no producer in M1. CMAC drains an idle stream.
assign m_axis_adap_tx_250mhz_tvalid     = '0;
assign m_axis_adap_tx_250mhz_tdata      = '0;
assign m_axis_adap_tx_250mhz_tkeep      = '0;
assign m_axis_adap_tx_250mhz_tlast      = '0;
assign m_axis_adap_tx_250mhz_tuser_size = '0;
assign m_axis_adap_tx_250mhz_tuser_src  = '0;
assign m_axis_adap_tx_250mhz_tuser_dst  = '0;

// CMAC RX adapter: accept and drop every beat. Box1's parser tap reads
// the same CMAC RX stream upstream of Box0, so this doesn't blind the
// parser regression — Box0 is just the sink end of the adapter mux.
assign s_axis_adap_rx_250mhz_tready = {NUM_CMAC_PORT{1'b1}};

// Silence unused-input lint by reading them into a (synthesizer-eliminated) wire.
wire _unused_box_inputs = &{
  1'b0,
  s_axis_qdma_h2c_tvalid,
  s_axis_qdma_h2c_tdata,
  s_axis_qdma_h2c_tkeep,
  s_axis_qdma_h2c_tlast,
  s_axis_qdma_h2c_tuser_size,
  s_axis_qdma_h2c_tuser_src,
  s_axis_qdma_h2c_tuser_dst,
  m_axis_qdma_c2h_tready,
  m_axis_adap_tx_250mhz_tready,
  s_axis_adap_rx_250mhz_tvalid,
  s_axis_adap_rx_250mhz_tdata,
  s_axis_adap_rx_250mhz_tkeep,
  s_axis_adap_rx_250mhz_tlast,
  s_axis_adap_rx_250mhz_tuser_size,
  s_axis_adap_rx_250mhz_tuser_src,
  s_axis_adap_rx_250mhz_tuser_dst,
  axis_aclk
};
