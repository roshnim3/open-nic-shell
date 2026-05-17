`timescale 1ns/1ps

// *************************************************************************
// Simplified ITCH parser for OpenNIC bitstream closure.
//
// Drop-in replacement for packetparser_322mhz with the same port list,
// designed to map to a handful of registers + a few muxes instead of the
// 4 KB byte-addressable buffer the full parser uses.
//
// Features:
//   - 3 ITCH message types decoded: 0x41 Add Order, 0x69 Order Executed,
//     0x68 Stock Trading Action. Anything else captures msg_type and
//     bumps an "unknown" counter.
//   - Per-message-type counters (4 x 16-bit).
//   - Single-beat multi-message support for msg_num=2. The second message
//     starts at a variable byte offset within beat 1; for each (msg1_type,
//     msg2_type) combination that fits in 64 bytes, the parser extracts
//     msg2's fields from fixed tdata positions (no runtime barrel shifter).
//     msg1's would-be field values are overwritten by msg2's via NBA
//     last-wins semantics, so the AXI-Lite snapshot always shows the
//     "latest" message in the packet. Per-type counters bump for BOTH
//     messages via blocking accumulators.
//
// Tradeoffs vs full parser:
//   - 3+ messages per packet: only msg1 + msg2 parsed; msg3..N silently
//     skipped (counters don't increment for them).
//   - Messages spanning beat 1 -> beat N: not supported. Some
//     (msg1_type, msg2_type) combinations are too large to fit in 64
//     bytes (e.g., 0x41 + 0x41 = 36+2+36 = 74); for those msg2 is treated
//     as unknown.
//   - No buffer, no LUTRAM, no byte-addressable indexing.
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

    // Per-message-type counters (cmac_clk domain). Latched into the AXI-Lite
    // snapshot block on every snapshot_toggle, so the host sees consistent
    // values across all four counts.
    output logic [15:0]  count_add_order,
    output logic [15:0]  count_order_executed,
    output logic [15:0]  count_stock_action,
    output logic [15:0]  count_unknown,

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
        // Blocking accumulators so a single cycle can bump a counter by up to
        // 2 (when one packet contains two messages of the same type).
        logic [15:0] new_count_add_order;
        logic [15:0] new_count_order_executed;
        logic [15:0] new_count_stock_action;
        logic [15:0] new_count_unknown;
        logic [7:0]  msg1_type_b;
        logic [7:0]  msg2_type_b;

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

            count_add_order      <= 16'h0;
            count_order_executed <= 16'h0;
            count_stock_action   <= 16'h0;
            count_unknown        <= 16'h0;
        end
        else begin
            parsing_active <= 1'b0;

            new_count_add_order      = count_add_order;
            new_count_order_executed = count_order_executed;
            new_count_stock_action   = count_stock_action;
            new_count_unknown        = count_unknown;

            if (s_axis_cmac_rx_tvalid[0]) begin
                if (!p_header_flag) begin
                    // ------------------------------------------------------
                    // Beat 0 — Ethernet (14) + IPv4 (20) + UDP (8) +
                    // MoldUDP64 (20) + 2-byte ITCH msg_len = 64 bytes.
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
                    // Beat 1 — first ITCH message body starts at byte 0.
                    // Always parse msg1; counter for its type bumps.
                    // ------------------------------------------------------
                    msg1_type_b = s_axis_cmac_rx_tdata[511:504];
                    msg_type   <= msg1_type_b;

                    case (msg1_type_b)
                        8'h41: begin
                            stock_locate <= s_axis_cmac_rx_tdata[503:488];
                            timestamp    <= s_axis_cmac_rx_tdata[471:424];
                            ref_num      <= s_axis_cmac_rx_tdata[423:360];
                            buy_sell     <= s_axis_cmac_rx_tdata[359:352];
                            share_amt    <= s_axis_cmac_rx_tdata[351:320];
                            stock_sym    <= s_axis_cmac_rx_tdata[319:256];
                            price        <= s_axis_cmac_rx_tdata[255:224];
                            new_count_add_order = new_count_add_order + 16'd1;
                            parsing_active  <= 1'b1;
                            snapshot_toggle <= ~snapshot_toggle;
                        end
                        8'h69: begin
                            stock_locate <= s_axis_cmac_rx_tdata[503:488];
                            timestamp    <= s_axis_cmac_rx_tdata[471:424];
                            ref_num      <= s_axis_cmac_rx_tdata[423:360];
                            share_amt    <= s_axis_cmac_rx_tdata[351:320];
                            new_count_order_executed = new_count_order_executed + 16'd1;
                            parsing_active  <= 1'b1;
                            snapshot_toggle <= ~snapshot_toggle;
                        end
                        8'h68: begin
                            stock_locate <= s_axis_cmac_rx_tdata[503:488];
                            timestamp    <= s_axis_cmac_rx_tdata[471:424];
                            ref_num      <= s_axis_cmac_rx_tdata[423:360];
                            new_count_stock_action = new_count_stock_action + 16'd1;
                            parsing_active  <= 1'b1;
                            snapshot_toggle <= ~snapshot_toggle;
                        end
                        default: begin
                            new_count_unknown = new_count_unknown + 16'd1;
                        end
                    endcase

                    // --------------------------------------------------------
                    // Beat 1 (cont) — if msg_num >= 2, attempt to parse msg2.
                    // msg2 starts at a byte offset that depends on msg1's
                    // length: 0x41 -> 38, 0x69 -> 33, 0x68 -> 27.
                    // Field NBAs below overwrite msg1's would-be assignments
                    // for the same registers (NBA last-wins). msg2 does NOT
                    // pulse snapshot_toggle a second time (one toggle per
                    // beat 1 cycle; counters carry the per-message accounting).
                    // --------------------------------------------------------
                    if (msg_num >= 16'd2) begin
                        case (msg1_type_b)
                            8'h41: begin
                                // msg2_offset = 38; 26 bytes available; only 0x68 fits.
                                msg2_type_b = s_axis_cmac_rx_tdata[207:200];
                                msg_type   <= msg2_type_b;
                                case (msg2_type_b)
                                    8'h68: begin
                                        stock_locate <= s_axis_cmac_rx_tdata[199:184];
                                        timestamp    <= s_axis_cmac_rx_tdata[167:120];
                                        ref_num      <= s_axis_cmac_rx_tdata[119:56];
                                        new_count_stock_action = new_count_stock_action + 16'd1;
                                    end
                                    default: new_count_unknown = new_count_unknown + 16'd1;
                                endcase
                            end
                            8'h69: begin
                                // msg2_offset = 33; 31 bytes available; 0x69 (31) and 0x68 (25) fit.
                                msg2_type_b = s_axis_cmac_rx_tdata[247:240];
                                msg_type   <= msg2_type_b;
                                case (msg2_type_b)
                                    8'h69: begin
                                        stock_locate <= s_axis_cmac_rx_tdata[239:224];
                                        timestamp    <= s_axis_cmac_rx_tdata[207:160];
                                        ref_num      <= s_axis_cmac_rx_tdata[159:96];
                                        share_amt    <= s_axis_cmac_rx_tdata[87:56];
                                        new_count_order_executed = new_count_order_executed + 16'd1;
                                    end
                                    8'h68: begin
                                        stock_locate <= s_axis_cmac_rx_tdata[239:224];
                                        timestamp    <= s_axis_cmac_rx_tdata[207:160];
                                        ref_num      <= s_axis_cmac_rx_tdata[159:96];
                                        new_count_stock_action = new_count_stock_action + 16'd1;
                                    end
                                    default: new_count_unknown = new_count_unknown + 16'd1;
                                endcase
                            end
                            8'h68: begin
                                // msg2_offset = 27; 37 bytes available; all three fit.
                                msg2_type_b = s_axis_cmac_rx_tdata[295:288];
                                msg_type   <= msg2_type_b;
                                case (msg2_type_b)
                                    8'h41: begin
                                        stock_locate <= s_axis_cmac_rx_tdata[287:272];
                                        timestamp    <= s_axis_cmac_rx_tdata[255:208];
                                        ref_num      <= s_axis_cmac_rx_tdata[207:144];
                                        buy_sell     <= s_axis_cmac_rx_tdata[143:136];
                                        share_amt    <= s_axis_cmac_rx_tdata[135:104];
                                        stock_sym    <= s_axis_cmac_rx_tdata[103:40];
                                        price        <= s_axis_cmac_rx_tdata[39:8];
                                        new_count_add_order = new_count_add_order + 16'd1;
                                    end
                                    8'h69: begin
                                        stock_locate <= s_axis_cmac_rx_tdata[287:272];
                                        timestamp    <= s_axis_cmac_rx_tdata[255:208];
                                        ref_num      <= s_axis_cmac_rx_tdata[207:144];
                                        share_amt    <= s_axis_cmac_rx_tdata[135:104];
                                        new_count_order_executed = new_count_order_executed + 16'd1;
                                    end
                                    8'h68: begin
                                        stock_locate <= s_axis_cmac_rx_tdata[287:272];
                                        timestamp    <= s_axis_cmac_rx_tdata[255:208];
                                        ref_num      <= s_axis_cmac_rx_tdata[207:144];
                                        new_count_stock_action = new_count_stock_action + 16'd1;
                                    end
                                    default: new_count_unknown = new_count_unknown + 16'd1;
                                endcase
                            end
                            default: ;  // msg1 unknown: don't try msg2
                        endcase
                    end
                end

                if (s_axis_cmac_rx_tlast[0]) begin
                    p_header_flag <= 1'b0;
                    packet_toggle <= ~packet_toggle;
                end
            end

            // Commit accumulators
            count_add_order      <= new_count_add_order;
            count_order_executed <= new_count_order_executed;
            count_stock_action   <= new_count_stock_action;
            count_unknown        <= new_count_unknown;
        end
    end

endmodule : packetparser_322mhz_simple
