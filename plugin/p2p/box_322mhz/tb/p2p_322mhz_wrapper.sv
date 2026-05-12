`timescale 1ns/1ps

// Sim wrapper for p2p_322mhz (NUM_CMAC_PORT=1).
//
// - Renames tuser_err -> tuser on the CMAC RX bus so cocotbext.axi recognizes it.
// - Adds a dummy s_axil_wstrb (cocotbext.axi expects it; the underlying
//   axi_lite_register doesn't use it).
// - Stubs out streams that aren't exercised by Sim A (adapter TX/RX, CMAC TX).
//   Only s_axis_cmac_rx is driven externally.
module p2p_322mhz_wrapper (
  input  wire         s_axil_awvalid,
  input  wire [31:0]  s_axil_awaddr,
  output wire         s_axil_awready,
  input  wire         s_axil_wvalid,
  input  wire [31:0]  s_axil_wdata,
  input  wire  [3:0]  s_axil_wstrb,
  output wire         s_axil_wready,
  output wire         s_axil_bvalid,
  output wire  [1:0]  s_axil_bresp,
  input  wire         s_axil_bready,
  input  wire         s_axil_arvalid,
  input  wire [31:0]  s_axil_araddr,
  output wire         s_axil_arready,
  output wire         s_axil_rvalid,
  output wire [31:0]  s_axil_rdata,
  output wire  [1:0]  s_axil_rresp,
  input  wire         s_axil_rready,

  // CMAC RX (from wire) — driven by cocotb
  input  wire         s_axis_cmac_rx_tvalid,
  input  wire [511:0] s_axis_cmac_rx_tdata,
  input  wire  [63:0] s_axis_cmac_rx_tkeep,
  input  wire         s_axis_cmac_rx_tlast,
  input  wire         s_axis_cmac_rx_tuser,
  output wire         s_axis_cmac_rx_tready,

  input  wire         mod_rstn,
  output wire         mod_rst_done,

  input  wire         axil_aclk,
  input  wire         cmac_clk
);

  // The parser taps CMAC RX without backpressure; we're always-ready.
  assign s_axis_cmac_rx_tready = 1'b1;

  p2p_322mhz #(
    .NUM_CMAC_PORT (1)
  ) p2p_322mhz_inst (
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

    .s_axis_adap_tx_322mhz_tvalid    (1'b0),
    .s_axis_adap_tx_322mhz_tdata     (512'h0),
    .s_axis_adap_tx_322mhz_tkeep     (64'h0),
    .s_axis_adap_tx_322mhz_tlast     (1'b0),
    .s_axis_adap_tx_322mhz_tuser_err (1'b0),
    .s_axis_adap_tx_322mhz_tready    (),

    .m_axis_adap_rx_322mhz_tvalid    (),
    .m_axis_adap_rx_322mhz_tdata     (),
    .m_axis_adap_rx_322mhz_tkeep     (),
    .m_axis_adap_rx_322mhz_tlast     (),
    .m_axis_adap_rx_322mhz_tuser_err (),

    .m_axis_cmac_tx_tvalid    (),
    .m_axis_cmac_tx_tdata     (),
    .m_axis_cmac_tx_tkeep     (),
    .m_axis_cmac_tx_tlast     (),
    .m_axis_cmac_tx_tuser_err (),
    .m_axis_cmac_tx_tready    (1'b1),

    .s_axis_cmac_rx_tvalid    (s_axis_cmac_rx_tvalid),
    .s_axis_cmac_rx_tdata     (s_axis_cmac_rx_tdata),
    .s_axis_cmac_rx_tkeep     (s_axis_cmac_rx_tkeep),
    .s_axis_cmac_rx_tlast     (s_axis_cmac_rx_tlast),
    .s_axis_cmac_rx_tuser_err (s_axis_cmac_rx_tuser),

    .mod_rstn     (mod_rstn),
    .mod_rst_done (mod_rst_done),

    .axil_aclk    (axil_aclk),
    .cmac_clk     (cmac_clk)
  );

endmodule
