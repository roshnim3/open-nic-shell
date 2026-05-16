`timescale 1ns/1ps

// *************************************************************************
// Simplified ITCH parser for OpenNIC bitstream closure.
//
// Drop-in replacement for packetparser_322mhz with the same port list,
// designed to map to a handful of registers + a single case statement
// instead of the 4 KB byte-addressable buffer the full parser uses.
//
// Tradeoffs:
//   - Only one ITCH message type is decoded: Add Order (0x41). Other types
//     update msg_type only and leave the field registers unchanged.
//   - Only one message per packet. msg_num/msg_count semantics are not
//     honored — only the first message body in beat 1 is parsed.
//   - Packet layout is hardcoded: 42-byte L2/L3/L4 + 20-byte MoldUDP64 +
//     2-byte msg_len + ITCH body. Body always starts at byte 64 of the
//     packet (= byte 0 of beat 1 on a 512-bit AXI-Stream).
//
// In return, the synthesized cost is trivial: ~25 registers and a case
// statement. No circular buffer, no byte-addressable RAM, no multi-cycle
// state machine. Vivado place-and-route closes in minutes instead of days.
// *************************************************************************

module packetparser_322mhz_simple #(
    parameter int NUM_CMAC_PORT = 1
) (
    input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tvalid,
    input  [512*NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tdata,
    input   [64*NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tkeep,
    input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tlast,
    input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_tuser_err,

    input                          mod_rstn,
    output                         mod_rst_done,

    input                          axil_aclk,
    input      [NUM_CMAC_PORT-1:0] cmac_clk,

    output logic [47:0]  dst_mac,
    output logic [47:0]  src_mac,
    output logic [15:0]  header_checksum,
    output logic [31:0]  src_ip,
    output logic [31:0]  dst_ip,
    output logic [15:0]  src_port,
    output logic [15:0]  dst_port,
    output logic [15:0]  length,
    output logic [15:0]  checksum,
    output logic [79:0]  section,
    output logic [63:0]  seq,
    output logic [15:0]  msg_num,
    output logic [15:0]  msg_count,
    output logic [15:0]  msg_len,
    output logic [8:0]   spillover_len,
    output logic [511:0] buffer,
    output logic         p_header_flag,
    output logic         parsing_active,

    output logic [7:0]   msg_type,
    output logic [15:0]  stock_locate,
    output logic [47:0]  timestamp,
    output logic [63:0]  ref_num,
    output logic [7:0]   buy_sell,
    output logic [31:0]  share_amt,
    output logic [63:0]  stock_sym,
    output logic [31:0]  price,

    output logic         snapshot_toggle,
    output logic         packet_toggle
);

    assign mod_rst_done = 1'b1;

    // Unused interface outputs. Tied to constants so the downstream plugin
    // sees a consistent port signature without inferring storage we don't use.
    assign buffer         = 512'h0;
    assign spillover_len  = 9'h0;
    assign msg_count      = 16'h0;

    always_ff @(posedge cmac_clk[0]) begin
        if (!mod_rstn) begin
            p_header_flag    <= 1'b0;
            parsing_active   <= 1'b0;
            snapshot_toggle  <= 1'b0;
            packet_toggle    <= 1'b0;

            dst_mac          <= 48'h0;
            src_mac          <= 48'h0;
            header_checksum  <= 16'h0;
            src_ip           <= 32'h0;
            dst_ip           <= 32'h0;
            src_port         <= 16'h0;
            dst_port         <= 16'h0;
            length           <= 16'h0;
            checksum         <= 16'h0;
            section          <= 80'h0;
            seq              <= 64'h0;
            msg_num          <= 16'h0;
            msg_len          <= 16'h0;

            msg_type         <= 8'h0;
            stock_locate     <= 16'h0;
            timestamp        <= 48'h0;
            ref_num          <= 64'h0;
            buy_sell         <= 8'h0;
            share_amt        <= 32'h0;
            stock_sym        <= 64'h0;
            price            <= 32'h0;
        end
        else begin
            // parsing_active is a one-cycle pulse aligned with body parse.
            parsing_active <= 1'b0;

            if (s_axis_cmac_rx_tvalid[0]) begin
                if (!p_header_flag) begin
                    // ------------------------------------------------------
                    // Beat 0 — Ethernet (14) + IPv4 (20) + UDP (8) +
                    // MoldUDP64 (20) + 2-byte ITCH msg_len = 64 bytes.
                    // Byte 0 of the packet is at tdata[511:504].
                    // ------------------------------------------------------
                    dst_mac         <= s_axis_cmac_rx_tdata[511:464];
                    src_mac         <= s_axis_cmac_rx_tdata[463:416];
                    header_checksum <= s_axis_cmac_rx_tdata[319:304];
                    src_ip          <= s_axis_cmac_rx_tdata[303:272];
                    dst_ip          <= s_axis_cmac_rx_tdata[271:240];
                    src_port        <= s_axis_cmac_rx_tdata[239:224];
                    dst_port        <= s_axis_cmac_rx_tdata[223:208];
                    length          <= s_axis_cmac_rx_tdata[207:192];
                    checksum        <= s_axis_cmac_rx_tdata[191:176];
                    section         <= s_axis_cmac_rx_tdata[175:96];
                    seq             <= s_axis_cmac_rx_tdata[95:32];
                    msg_num         <= s_axis_cmac_rx_tdata[31:16];
                    msg_len         <= s_axis_cmac_rx_tdata[15:0];

                    p_header_flag   <= 1'b1;
                end
                else begin
                    // ------------------------------------------------------
                    // Beat 1 — ITCH message body. Byte N of the body lives
                    // at tdata[511 - N*8 -: 8]. Only Add Order (0x41) is
                    // decoded; other types update msg_type only.
                    // ------------------------------------------------------
                    msg_type <= s_axis_cmac_rx_tdata[511:504];

                    if (s_axis_cmac_rx_tdata[511:504] == 8'h41) begin
                        stock_locate <= s_axis_cmac_rx_tdata[503:488];
                        // bytes 3-4 are tracking number, ignored
                        timestamp    <= s_axis_cmac_rx_tdata[471:424];
                        ref_num      <= s_axis_cmac_rx_tdata[423:360];
                        buy_sell     <= s_axis_cmac_rx_tdata[359:352];
                        share_amt    <= s_axis_cmac_rx_tdata[351:320];
                        stock_sym    <= s_axis_cmac_rx_tdata[319:256];
                        price        <= s_axis_cmac_rx_tdata[255:224];

                        parsing_active  <= 1'b1;
                        snapshot_toggle <= ~snapshot_toggle;
                    end
                end

                if (s_axis_cmac_rx_tlast[0]) begin
                    p_header_flag <= 1'b0;
                    packet_toggle <= ~packet_toggle;
                end
            end
        end
    end

endmodule : packetparser_322mhz_simple
