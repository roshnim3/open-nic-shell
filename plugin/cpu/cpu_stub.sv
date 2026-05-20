// *************************************************************************
// cpu_stub.sv — minimal AXI-Lite slave for the CPU plugin slot in Box0.
// Returns a magic value at offset 0x00 to prove the BAR2 -> Box0 path.
// Future milestones replace this with the actual stripped RV32I core.
// *************************************************************************
`timescale 1ns/1ps
module cpu_stub (
  input                       s_axil_awvalid,
  input                [31:0] s_axil_awaddr,
  output                      s_axil_awready,
  input                       s_axil_wvalid,
  input                [31:0] s_axil_wdata,
  output                      s_axil_wready,
  output                      s_axil_bvalid,
  output                [1:0] s_axil_bresp,
  input                       s_axil_bready,
  input                       s_axil_arvalid,
  input                [31:0] s_axil_araddr,
  output                      s_axil_arready,
  output                      s_axil_rvalid,
  output               [31:0] s_axil_rdata,
  output                [1:0] s_axil_rresp,
  input                       s_axil_rready,

  input                       mod_rstn,
  output                      mod_rst_done,
  input                       axil_aclk
);

  wire                  reg_en;
  wire                  reg_we;
  wire           [7:0]  reg_addr;
  wire          [31:0]  reg_din;
  reg           [31:0]  reg_dout;

  assign mod_rst_done = 1'b1;

  axi_lite_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (8),
    .DATA_W        (32)
  ) reg_inst (
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awaddr  (s_axil_awaddr[7:0]),
    .s_axil_awready (s_axil_awready),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bready  (s_axil_bready),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_araddr  (s_axil_araddr[7:0]),
    .s_axil_arready (s_axil_arready),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .s_axil_rready  (s_axil_rready),
    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),
    .axil_aclk      (axil_aclk),
    .axil_aresetn   (mod_rstn),
    .reg_clk        (axil_aclk),
    .reg_rstn       (mod_rstn)
  );

  always @(posedge axil_aclk) begin
    if (!mod_rstn)
      reg_dout <= 32'h0;
    else if (reg_en && !reg_we) begin
      case (reg_addr)
        8'h00:   reg_dout <= 32'h5249_5343;   // "RISC"
        8'h04:   reg_dout <= 32'h0000_0001;   // version
        default: reg_dout <= 32'hDEAD_BEEF;
      endcase
    end
  end

endmodule
