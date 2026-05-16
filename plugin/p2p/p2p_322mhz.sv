// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps

module p2p_322mhz #(
  parameter int NUM_CMAC_PORT = 1
) (
  input                          s_axil_awvalid,
  input                   [31:0] s_axil_awaddr,
  output                         s_axil_awready,
  input                          s_axil_wvalid,
  input                   [31:0] s_axil_wdata,
  output                         s_axil_wready,
  output                         s_axil_bvalid,
  output                   [1:0] s_axil_bresp,
  input                          s_axil_bready,
  input                          s_axil_arvalid,
  input                   [31:0] s_axil_araddr,
  output                         s_axil_arready,
  output                         s_axil_rvalid,
  output                  [31:0] s_axil_rdata,
  output                   [1:0] s_axil_rresp,
  input                          s_axil_rready,

  input      [NUM_CMAC_PORT-1:0] s_axis_adap_tx_322mhz_tvalid,
  input  [512*NUM_CMAC_PORT-1:0] s_axis_adap_tx_322mhz_tdata,
  input   [64*NUM_CMAC_PORT-1:0] s_axis_adap_tx_322mhz_tkeep,
  input      [NUM_CMAC_PORT-1:0] s_axis_adap_tx_322mhz_tlast,
  input      [NUM_CMAC_PORT-1:0] s_axis_adap_tx_322mhz_tuser_err,
  output     [NUM_CMAC_PORT-1:0] s_axis_adap_tx_322mhz_tready,

  output     [NUM_CMAC_PORT-1:0] m_axis_adap_rx_322mhz_tvalid,
  output [512*NUM_CMAC_PORT-1:0] m_axis_adap_rx_322mhz_tdata,
  output  [64*NUM_CMAC_PORT-1:0] m_axis_adap_rx_322mhz_tkeep,
  output     [NUM_CMAC_PORT-1:0] m_axis_adap_rx_322mhz_tlast,
  output     [NUM_CMAC_PORT-1:0] m_axis_adap_rx_322mhz_tuser_err,

  output     [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_tvalid,
  output [512*NUM_CMAC_PORT-1:0] m_axis_cmac_tx_tdata,
  output  [64*NUM_CMAC_PORT-1:0] m_axis_cmac_tx_tkeep,
  output     [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_tlast,
  output     [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_tuser_err,
  input      [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_tready,

  input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tvalid,
  input  [512*NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tdata,
  input   [64*NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tkeep,
  input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tlast,
  input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tuser_err,

  input                          mod_rstn,
  output                         mod_rst_done,

  input                          axil_aclk,
  input      [NUM_CMAC_PORT-1:0] cmac_clk
);

  wire                         axil_aresetn;
  wire     [NUM_CMAC_PORT-1:0] cmac_rstn;

  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tlast;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tuser_err;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tready;

  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tlast;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tuser_err;

  wire                         parser_snapshot_toggle;
  wire                         parser_packet_toggle;
  wire [7:0]                   parser_msg_type;
  wire [31:0]                  parser_src_ip;
  wire [31:0]                  parser_dst_ip;
  wire [15:0]                  parser_src_port;
  wire [15:0]                  parser_dst_port;
  wire [63:0]                  parser_seq;
  wire [15:0]                  parser_msg_num;
  wire [15:0]                  parser_stock_locate;
  wire [47:0]                  parser_timestamp;
  wire [63:0]                  parser_ref_num;
  wire [7:0]                   parser_buy_sell;
  wire [31:0]                  parser_share_amt;
  wire [63:0]                  parser_stock_sym;
  wire [31:0]                  parser_price;
  wire                         parser_p_header_flag;
  wire                         parser_parsing_active;

  wire                         reg_en;
  wire                         reg_we;
  wire [7:0]                   reg_addr;
  wire [31:0]                  reg_din;
  reg  [31:0]                  reg_dout;

  reg  [31:0]                  packet_count;
  reg  [31:0]                  parsed_msg_count;
  reg  [31:0]                  parser_status;
  reg  [31:0]                  last_msg_type_reg;
  reg  [31:0]                  last_src_ip_reg;
  reg  [31:0]                  last_dst_ip_reg;
  reg  [31:0]                  last_src_port_dst_port_reg;
  reg  [31:0]                  last_seq_low_reg;
  reg  [31:0]                  last_seq_high_reg;
  reg  [31:0]                  last_msg_num_reg;
  reg  [31:0]                  last_stock_locate_reg;
  reg  [31:0]                  last_timestamp_low_reg;
  reg  [31:0]                  last_timestamp_high_reg;
  reg  [31:0]                  last_ref_num_low_reg;
  reg  [31:0]                  last_ref_num_high_reg;
  reg  [31:0]                  last_buy_sell_reg;
  reg  [31:0]                  last_share_amt_reg;
  reg  [31:0]                  last_stock_sym_low_reg;
  reg  [31:0]                  last_stock_sym_high_reg;
  reg  [31:0]                  last_price_reg;

  reg  [1:0]                   snapshot_toggle_sync;
  reg  [1:0]                   packet_toggle_sync;
  reg                          snapshot_toggle_prev;
  reg                          packet_toggle_prev;

  localparam logic [7:0] REG_MAGIC               = 8'h00;
  localparam logic [7:0] REG_VERSION             = 8'h04;
  localparam logic [7:0] REG_PACKET_COUNT        = 8'h08;
  localparam logic [7:0] REG_PARSED_MSG_COUNT    = 8'h0C;
  localparam logic [7:0] REG_LAST_MSG_TYPE       = 8'h10;
  localparam logic [7:0] REG_LAST_SRC_IP         = 8'h14;
  localparam logic [7:0] REG_LAST_DST_IP         = 8'h18;
  localparam logic [7:0] REG_LAST_PORTS          = 8'h1C;
  localparam logic [7:0] REG_LAST_SEQ_LOW        = 8'h20;
  localparam logic [7:0] REG_LAST_SEQ_HIGH       = 8'h24;
  localparam logic [7:0] REG_LAST_MSG_NUM        = 8'h28;
  localparam logic [7:0] REG_LAST_STOCK_LOCATE   = 8'h2C;
  localparam logic [7:0] REG_LAST_TIMESTAMP_LOW  = 8'h30;
  localparam logic [7:0] REG_LAST_TIMESTAMP_HIGH = 8'h34;
  localparam logic [7:0] REG_LAST_REF_NUM_LOW    = 8'h38;
  localparam logic [7:0] REG_LAST_REF_NUM_HIGH   = 8'h3C;
  localparam logic [7:0] REG_LAST_BUY_SELL       = 8'h40;
  localparam logic [7:0] REG_LAST_SHARE_AMT      = 8'h44;
  localparam logic [7:0] REG_LAST_STOCK_SYM_LOW  = 8'h48;
  localparam logic [7:0] REG_LAST_STOCK_SYM_HIGH = 8'h4C;
  localparam logic [7:0] REG_LAST_PRICE          = 8'h50;
  localparam logic [7:0] REG_PARSER_STATUS       = 8'h54;
  localparam logic [7:0] REG_CLEAR_COUNTS        = 8'h58;

  generic_reset #(
    .NUM_INPUT_CLK  (1 + NUM_CMAC_PORT),
    .RESET_DURATION (100)
  ) reset_inst (
    .mod_rstn     (mod_rstn),
    .mod_rst_done (mod_rst_done),
    .clk          ({cmac_clk, axil_aclk}),
    .rstn         ({cmac_rstn, axil_aresetn})
  );

  axi_lite_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (8),
    .DATA_W        (32)
  ) reg_inst (
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

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .axil_aclk      (axil_aclk),
    .axil_aresetn   (axil_aresetn),
    .reg_clk        (axil_aclk),
    .reg_rstn       (axil_aresetn)
  );

  packetparser_322mhz_simple #(
    .NUM_CMAC_PORT (NUM_CMAC_PORT)
  ) parser_inst (
    .s_axis_cmac_rx_tvalid (s_axis_cmac_rx_tvalid),
    .s_axis_cmac_rx_tdata  (s_axis_cmac_rx_tdata),
    .s_axis_cmac_rx_tkeep  (s_axis_cmac_rx_tkeep),
    .s_axis_cmac_rx_tlast  (s_axis_cmac_rx_tlast),
    .s_axis_cmac_rx_tuser_err (s_axis_cmac_rx_tuser_err),
    .mod_rstn              (cmac_rstn[0]),
    .mod_rst_done          (),
    .axil_aclk             (axil_aclk),
    .cmac_clk              (cmac_clk),
    .dst_mac               (),
    .src_mac               (),
    .header_checksum       (),
    .src_ip                (parser_src_ip),
    .dst_ip                (parser_dst_ip),
    .src_port              (parser_src_port),
    .dst_port              (parser_dst_port),
    .length                (),
    .checksum              (),
    .section               (),
    .seq                   (parser_seq),
    .msg_num               (parser_msg_num),
    .msg_count             (),
    .msg_len               (),
    .spillover_len         (),
    .buffer                (),
    .p_header_flag         (parser_p_header_flag),
    .parsing_active        (parser_parsing_active),
    .msg_type              (parser_msg_type),
    .stock_locate          (parser_stock_locate),
    .timestamp             (parser_timestamp),
    .ref_num               (parser_ref_num),
    .buy_sell              (parser_buy_sell),
    .share_amt             (parser_share_amt),
    .stock_sym             (parser_stock_sym),
    .price                 (parser_price),
    .snapshot_toggle       (parser_snapshot_toggle),
    .packet_toggle         (parser_packet_toggle)
  );

  always_ff @(posedge axil_aclk) begin
    if (!axil_aresetn) begin
      snapshot_toggle_sync       <= 2'b00;
      packet_toggle_sync         <= 2'b00;
      snapshot_toggle_prev       <= 1'b0;
      packet_toggle_prev         <= 1'b0;
      packet_count               <= 32'h0;
      parsed_msg_count           <= 32'h0;
      parser_status              <= 32'h0;
      last_msg_type_reg          <= 32'h0;
      last_src_ip_reg            <= 32'h0;
      last_dst_ip_reg            <= 32'h0;
      last_src_port_dst_port_reg <= 32'h0;
      last_seq_low_reg           <= 32'h0;
      last_seq_high_reg          <= 32'h0;
      last_msg_num_reg           <= 32'h0;
      last_stock_locate_reg      <= 32'h0;
      last_timestamp_low_reg     <= 32'h0;
      last_timestamp_high_reg    <= 32'h0;
      last_ref_num_low_reg       <= 32'h0;
      last_ref_num_high_reg      <= 32'h0;
      last_buy_sell_reg          <= 32'h0;
      last_share_amt_reg         <= 32'h0;
      last_stock_sym_low_reg     <= 32'h0;
      last_stock_sym_high_reg    <= 32'h0;
      last_price_reg             <= 32'h0;
    end
    else begin
      snapshot_toggle_sync <= {snapshot_toggle_sync[0], parser_snapshot_toggle};
      packet_toggle_sync   <= {packet_toggle_sync[0], parser_packet_toggle};

      if (reg_en && reg_we && (reg_addr == REG_CLEAR_COUNTS) && reg_din[0]) begin
        packet_count     <= 32'h0;
        parsed_msg_count <= 32'h0;
      end
      else begin
        if (snapshot_toggle_sync[1] ^ snapshot_toggle_prev) begin
          last_msg_type_reg          <= {24'h0, parser_msg_type};
          last_src_ip_reg            <= parser_src_ip;
          last_dst_ip_reg            <= parser_dst_ip;
          last_src_port_dst_port_reg <= {parser_src_port, parser_dst_port};
          last_seq_low_reg           <= parser_seq[31:0];
          last_seq_high_reg          <= parser_seq[63:32];
          last_msg_num_reg           <= {16'h0, parser_msg_num};
          last_stock_locate_reg      <= {16'h0, parser_stock_locate};
          last_timestamp_low_reg     <= parser_timestamp[31:0];
          last_timestamp_high_reg    <= {16'h0, parser_timestamp[47:32]};
          last_ref_num_low_reg       <= parser_ref_num[31:0];
          last_ref_num_high_reg      <= parser_ref_num[63:32];
          last_buy_sell_reg          <= {24'h0, parser_buy_sell};
          last_share_amt_reg         <= parser_share_amt;
          last_stock_sym_low_reg     <= parser_stock_sym[31:0];
          last_stock_sym_high_reg    <= parser_stock_sym[63:32];
          last_price_reg             <= parser_price;
          parsed_msg_count           <= parsed_msg_count + 32'd1;
        end

        if (packet_toggle_sync[1] ^ packet_toggle_prev) begin
          packet_count <= packet_count + 32'd1;
        end
      end

      snapshot_toggle_prev <= snapshot_toggle_sync[1];
      packet_toggle_prev   <= packet_toggle_sync[1];

      parser_status <= {
        28'h0,
        snapshot_toggle_sync[1],
        packet_toggle_sync[1],
        |parsed_msg_count,
        |packet_count
      };
    end
  end

  always_ff @(posedge axil_aclk) begin
    if (!axil_aresetn) begin
      reg_dout <= 32'h0;
    end
    else if (reg_en && !reg_we) begin
      case (reg_addr)
        REG_MAGIC:               reg_dout <= 32'h4954_4348;
        REG_VERSION:             reg_dout <= 32'h0000_0001;
        REG_PACKET_COUNT:        reg_dout <= packet_count;
        REG_PARSED_MSG_COUNT:    reg_dout <= parsed_msg_count;
        REG_LAST_MSG_TYPE:       reg_dout <= last_msg_type_reg;
        REG_LAST_SRC_IP:         reg_dout <= last_src_ip_reg;
        REG_LAST_DST_IP:         reg_dout <= last_dst_ip_reg;
        REG_LAST_PORTS:          reg_dout <= last_src_port_dst_port_reg;
        REG_LAST_SEQ_LOW:        reg_dout <= last_seq_low_reg;
        REG_LAST_SEQ_HIGH:       reg_dout <= last_seq_high_reg;
        REG_LAST_MSG_NUM:        reg_dout <= last_msg_num_reg;
        REG_LAST_STOCK_LOCATE:   reg_dout <= last_stock_locate_reg;
        REG_LAST_TIMESTAMP_LOW:  reg_dout <= last_timestamp_low_reg;
        REG_LAST_TIMESTAMP_HIGH: reg_dout <= last_timestamp_high_reg;
        REG_LAST_REF_NUM_LOW:    reg_dout <= last_ref_num_low_reg;
        REG_LAST_REF_NUM_HIGH:   reg_dout <= last_ref_num_high_reg;
        REG_LAST_BUY_SELL:       reg_dout <= last_buy_sell_reg;
        REG_LAST_SHARE_AMT:      reg_dout <= last_share_amt_reg;
        REG_LAST_STOCK_SYM_LOW:  reg_dout <= last_stock_sym_low_reg;
        REG_LAST_STOCK_SYM_HIGH: reg_dout <= last_stock_sym_high_reg;
        REG_LAST_PRICE:          reg_dout <= last_price_reg;
        REG_PARSER_STATUS:       reg_dout <= parser_status;
        REG_CLEAR_COUNTS:        reg_dout <= 32'h0;
        default:                 reg_dout <= 32'hDEAD_BEEF;
      endcase
    end
  end

  generate for (genvar i = 0; i < NUM_CMAC_PORT; i++) begin
    axi_stream_register_slice #(
      .TDATA_W (512),
      .TUSER_W (1),
      .MODE    ("full")
    ) tx_slice_0_inst (
      .s_axis_tvalid (s_axis_adap_tx_322mhz_tvalid[i]),
      .s_axis_tdata  (s_axis_adap_tx_322mhz_tdata[`getvec(512, i)]),
      .s_axis_tkeep  (s_axis_adap_tx_322mhz_tkeep[`getvec(64, i)]),
      .s_axis_tlast  (s_axis_adap_tx_322mhz_tlast[i]),
      .s_axis_tid    (0),
      .s_axis_tdest  (0),
      .s_axis_tuser  (s_axis_adap_tx_322mhz_tuser_err[i]),
      .s_axis_tready (s_axis_adap_tx_322mhz_tready[i]),

      .m_axis_tvalid (axis_adap_tx_322mhz_tvalid[i]),
      .m_axis_tdata  (axis_adap_tx_322mhz_tdata[`getvec(512, i)]),
      .m_axis_tkeep  (axis_adap_tx_322mhz_tkeep[`getvec(64, i)]),
      .m_axis_tlast  (axis_adap_tx_322mhz_tlast[i]),
      .m_axis_tid    (),
      .m_axis_tdest  (),
      .m_axis_tuser  (axis_adap_tx_322mhz_tuser_err[i]),
      .m_axis_tready (axis_adap_tx_322mhz_tready[i]),

      .aclk          (cmac_clk[i]),
      .aresetn       (cmac_rstn[i])
    );

    axi_stream_register_slice #(
      .TDATA_W (512),
      .TUSER_W (1),
      .MODE    ("full")
    ) tx_slice_1_inst (
      .s_axis_tvalid (axis_adap_tx_322mhz_tvalid[i]),
      .s_axis_tdata  (axis_adap_tx_322mhz_tdata[`getvec(512, i)]),
      .s_axis_tkeep  (axis_adap_tx_322mhz_tkeep[`getvec(64, i)]),
      .s_axis_tlast  (axis_adap_tx_322mhz_tlast[i]),
      .s_axis_tid    (0),
      .s_axis_tdest  (0),
      .s_axis_tuser  (axis_adap_tx_322mhz_tuser_err[i]),
      .s_axis_tready (axis_adap_tx_322mhz_tready[i]),

      .m_axis_tvalid (m_axis_cmac_tx_tvalid[i]),
      .m_axis_tdata  (m_axis_cmac_tx_tdata[`getvec(512, i)]),
      .m_axis_tkeep  (m_axis_cmac_tx_tkeep[`getvec(64, i)]),
      .m_axis_tlast  (m_axis_cmac_tx_tlast[i]),
      .m_axis_tid    (),
      .m_axis_tdest  (),
      .m_axis_tuser  (m_axis_cmac_tx_tuser_err[i]),
      .m_axis_tready (m_axis_cmac_tx_tready[i]),

      .aclk          (cmac_clk[i]),
      .aresetn       (cmac_rstn[i])
    );

    axi_stream_register_slice #(
      .TDATA_W (512),
      .TUSER_W (1),
      .MODE    ("full")
    ) rx_slice_0_inst (
      .s_axis_tvalid (s_axis_cmac_rx_tvalid[i]),
      .s_axis_tdata  (s_axis_cmac_rx_tdata[`getvec(512, i)]),
      .s_axis_tkeep  (s_axis_cmac_rx_tkeep[`getvec(64, i)]),
      .s_axis_tlast  (s_axis_cmac_rx_tlast[i]),
      .s_axis_tid    (0),
      .s_axis_tdest  (0),
      .s_axis_tuser  (s_axis_cmac_rx_tuser_err[i]),
      .s_axis_tready (),

      .m_axis_tvalid (axis_adap_rx_322mhz_tvalid[i]),
      .m_axis_tdata  (axis_adap_rx_322mhz_tdata[`getvec(512, i)]),
      .m_axis_tkeep  (axis_adap_rx_322mhz_tkeep[`getvec(64, i)]),
      .m_axis_tlast  (axis_adap_rx_322mhz_tlast[i]),
      .m_axis_tid    (),
      .m_axis_tdest  (),
      .m_axis_tuser  (axis_adap_rx_322mhz_tuser_err[i]),
      .m_axis_tready (1'b1),

      .aclk          (cmac_clk[i]),
      .aresetn       (cmac_rstn[i])
    );

    axi_stream_register_slice #(
      .TDATA_W (512),
      .TUSER_W (1),
      .MODE    ("full")
    ) rx_slice_1_inst (
      .s_axis_tvalid (axis_adap_rx_322mhz_tvalid[i]),
      .s_axis_tdata  (axis_adap_rx_322mhz_tdata[`getvec(512, i)]),
      .s_axis_tkeep  (axis_adap_rx_322mhz_tkeep[`getvec(64, i)]),
      .s_axis_tlast  (axis_adap_rx_322mhz_tlast[i]),
      .s_axis_tid    (0),
      .s_axis_tdest  (0),
      .s_axis_tuser  (axis_adap_rx_322mhz_tuser_err[i]),
      .s_axis_tready (),

      .m_axis_tvalid (m_axis_adap_rx_322mhz_tvalid[i]),
      .m_axis_tdata  (m_axis_adap_rx_322mhz_tdata[`getvec(512, i)]),
      .m_axis_tkeep  (m_axis_adap_rx_322mhz_tkeep[`getvec(64, i)]),
      .m_axis_tlast  (m_axis_adap_rx_322mhz_tlast[i]),
      .m_axis_tid    (),
      .m_axis_tdest  (),
      .m_axis_tuser  (m_axis_adap_rx_322mhz_tuser_err[i]),
      .m_axis_tready (1'b1),

      .aclk          (cmac_clk[i]),
      .aresetn       (cmac_rstn[i])
    );
  end
  endgenerate

endmodule: p2p_322mhz