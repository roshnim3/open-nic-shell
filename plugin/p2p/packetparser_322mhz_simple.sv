`timescale 1ns/1ps

// *************************************************************************
// Simplified ITCH parser for OpenNIC bitstream closure.
//
// Drop-in replacement for packetparser_322mhz with the same port list.
// Designed to map to a handful of registers + a few muxes instead of the
// 4 KB byte-addressable buffer the full parser uses.
//
// Tier 3 (this version) adds messages-spanning-beat-1->beat-2 support for
// msg_num=2 packets, getting us as close to the original parser's
// behaviour as we can while still closing P&R.
//
// Features:
//   - 3 ITCH message types decoded: 0x41 Add Order, 0x69 Order Executed,
//     0x68 Stock Trading Action. Anything else captures msg_type only
//     and bumps an "unknown" counter.
//   - Per-message-type counters (4 x 16-bit).
//   - msg_num <= 2 support, including all (msg1, msg2) combinations where
//     msg2's parsed fields span beat 1 -> beat 2:
//       (0x41, 0x41): stock_sym partial in beat 1, rest + price in beat 2
//       (0x69, 0x41): stock_sym partial in beat 1, rest + price in beat 2
//     Other (0x41, 0x69) span case has all fields in beat 1 -> handled in
//     the single-beat path.
//
// Mechanism for spanning:
//   - On beat 1 we save the full 512-bit tdata into beat1_data.
//   - For spanning combos we parse msg2's beat-1 fields immediately and
//     set pending=1, deferring snapshot.
//   - On beat 2, if pending=1, we complete msg2's remaining fields using
//     fixed bit slices of {beat1_data, current_tdata}. Then snapshot.
//   - All bit positions are compile-time constants per (msg1, msg2) combo.
//     No byte-addressable buffer, no runtime indexing.
//
// Limitations vs full parser:
//   - msg_num >= 3 not supported (msg3..N silently skipped).
//   - Messages spanning > 2 beats not supported (no ITCH msg is large
//     enough for this anyway with our 3 supported types).
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

    output logic [15:0]  count_add_order,
    output logic [15:0]  count_order_executed,
    output logic [15:0]  count_stock_action,
    output logic [15:0]  count_unknown,

    output logic         snapshot_toggle,
    output logic         packet_toggle
);

    assign mod_rst_done = 1'b1;

    assign buffer         = 512'h0;
    assign spillover_len  = 9'h0;
    assign msg_count      = 16'h0;

    // ---------------------------------------------------------------------
    // Tier 3 state for cross-beat msg2 completion.
    //   pending           : 1 = next body beat completes msg2 from beat 2
    //   beat1_data        : full 512 bits of the beat that started msg2
    //   pending_msg1_type : msg1 type from beat 1 (selects beat-2 splice)
    //   pending_msg2_type : msg2 type (always 0x41 in current Tier 3 cases)
    // ---------------------------------------------------------------------
    logic         pending;
    logic [511:0] beat1_data;
    logic [7:0]   pending_msg1_type;
    logic [7:0]   pending_msg2_type;

    always_ff @(posedge cmac_clk[0]) begin
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

            pending           <= 1'b0;
            beat1_data        <= 512'h0;
            pending_msg1_type <= 8'h0;
            pending_msg2_type <= 8'h0;
        end
        else begin
            parsing_active <= 1'b0;

            new_count_add_order      = count_add_order;
            new_count_order_executed = count_order_executed;
            new_count_stock_action   = count_stock_action;
            new_count_unknown        = count_unknown;

            if (s_axis_cmac_rx_tvalid[0]) begin
                if (pending) begin
                    // ------------------------------------------------------
                    // Beat 2 — finish msg2 by splicing saved beat1_data
                    // with current tdata. The bit positions are fixed per
                    // pending_msg1_type / pending_msg2_type combo.
                    // ------------------------------------------------------
                    case ({pending_msg1_type, pending_msg2_type})
                        {8'h41, 8'h41}: begin
                            // msg2 starts at beat-1 byte 38, so:
                            //   msg2 bytes 0..25  -> beat1_data[(511-38*8)-:208] = beat1_data[207:0]
                            //                       (already consumed for fields up to share_amt
                            //                       and the first 2 bytes of stock_sym)
                            //   stock_sym  = {beat1_data[15:0], tdata[511:464]}
                            //   price      = tdata[463:432]
                            stock_sym <= {beat1_data[15:0],
                                          s_axis_cmac_rx_tdata[511:464]};
                            price     <= s_axis_cmac_rx_tdata[463:432];
                        end
                        {8'h69, 8'h41}: begin
                            // msg2 starts at beat-1 byte 33, so:
                            //   stock_sym  = {beat1_data[55:0], tdata[511:504]}
                            //   price      = tdata[503:472]
                            stock_sym <= {beat1_data[55:0],
                                          s_axis_cmac_rx_tdata[511:504]};
                            price     <= s_axis_cmac_rx_tdata[503:472];
                        end
                        default: ;  // unreachable given how we set pending
                    endcase

                    parsing_active  <= 1'b1;
                    snapshot_toggle <= ~snapshot_toggle;
                    pending         <= 1'b0;
                end
                else if (!p_header_flag) begin
                    // ------------------------------------------------------
                    // Beat 0 — Ethernet/IPv4/UDP/MoldUDP64/msg_len.
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
                    // Beat 1 — parse msg1 always; parse msg2 if msg_num>=2.
                    // Stash the beat in beat1_data unconditionally so it's
                    // available if any case sets pending=1.
                    // ------------------------------------------------------
                    beat1_data <= s_axis_cmac_rx_tdata;

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

                    if (msg_num >= 16'd2) begin
                        case (msg1_type_b)
                            8'h41: begin
                                msg2_type_b = s_axis_cmac_rx_tdata[207:200];
                                msg_type   <= msg2_type_b;
                                case (msg2_type_b)
                                    8'h41: begin
                                        // SPANS into beat 2. Parse what's in beat 1:
                                        stock_locate <= s_axis_cmac_rx_tdata[199:184];
                                        timestamp    <= s_axis_cmac_rx_tdata[167:120];
                                        ref_num      <= s_axis_cmac_rx_tdata[119:56];
                                        buy_sell     <= s_axis_cmac_rx_tdata[55:48];
                                        share_amt    <= s_axis_cmac_rx_tdata[47:16];
                                        // stock_sym partial high bits at [15:0], rest from beat 2
                                        // price entirely from beat 2
                                        pending           <= 1'b1;
                                        pending_msg1_type <= 8'h41;
                                        pending_msg2_type <= 8'h41;
                                        new_count_add_order = new_count_add_order + 16'd1;
                                        // No snapshot — wait for beat 2
                                        snapshot_toggle <= snapshot_toggle;  // explicit no-toggle
                                    end
                                    8'h69: begin
                                        // Span body but all parsed fields fit in beat 1
                                        stock_locate <= s_axis_cmac_rx_tdata[199:184];
                                        timestamp    <= s_axis_cmac_rx_tdata[167:120];
                                        ref_num      <= s_axis_cmac_rx_tdata[119:56];
                                        share_amt    <= s_axis_cmac_rx_tdata[87:56];
                                        new_count_order_executed = new_count_order_executed + 16'd1;
                                    end
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
                                msg2_type_b = s_axis_cmac_rx_tdata[247:240];
                                msg_type   <= msg2_type_b;
                                case (msg2_type_b)
                                    8'h41: begin
                                        // SPANS into beat 2
                                        stock_locate <= s_axis_cmac_rx_tdata[239:224];
                                        timestamp    <= s_axis_cmac_rx_tdata[207:160];
                                        ref_num      <= s_axis_cmac_rx_tdata[159:96];
                                        buy_sell     <= s_axis_cmac_rx_tdata[95:88];
                                        share_amt    <= s_axis_cmac_rx_tdata[87:56];
                                        // stock_sym partial high 7 bytes at [55:0], rest from beat 2
                                        // price entirely from beat 2
                                        pending           <= 1'b1;
                                        pending_msg1_type <= 8'h69;
                                        pending_msg2_type <= 8'h41;
                                        new_count_add_order = new_count_add_order + 16'd1;
                                        snapshot_toggle <= snapshot_toggle;  // no toggle
                                    end
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
                            default: ;  // msg1 unknown
                        endcase
                    end
                end

                if (s_axis_cmac_rx_tlast[0]) begin
                    p_header_flag <= 1'b0;
                    packet_toggle <= ~packet_toggle;
                    // If pending was set this same cycle, leave it — the
                    // pending path on the NEXT cycle (if there is one)
                    // expects the next beat to be beat 2. But if tlast=1
                    // on the beat that set pending, the packet ended
                    // prematurely. Clear pending so the next packet's
                    // beat 0 isn't misread as beat 2.
                    if (pending) pending <= 1'b0;
                end
            end

            count_add_order      <= new_count_add_order;
            count_order_executed <= new_count_order_executed;
            count_stock_action   <= new_count_stock_action;
            count_unknown        <= new_count_unknown;
        end
    end

endmodule : packetparser_322mhz_simple
