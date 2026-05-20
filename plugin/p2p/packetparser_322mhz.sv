`timescale 1ns/1ps

// *************************************************************************
// *  Packet Parser 322MHz
module packetparser_322mhz #(
    parameter int NUM_CMAC_PORT = 1,
    parameter int BUFFER_SIZE    = 4096,
    parameter int MAX_MSG_SIZE   = 256
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

    output logic [47:0] dst_mac,
    output logic [47:0] src_mac,
    output logic [15:0] header_checksum,
    output logic [31:0] src_ip,
    output logic [31:0] dst_ip,
    output logic [15:0] src_port,
    output logic [15:0] dst_port,
    output logic [15:0] length,
    output logic [15:0] checksum,
    output logic [79:0] section,
    output logic [63:0] seq,
    output logic [15:0] msg_num,
    output logic [15:0] msg_count,
    output logic [15:0] msg_len,
    output logic [8:0]  spillover_len,
    output logic [511:0] buffer,
    output logic p_header_flag,
    output logic parsing_active,

    output logic [7:0]  msg_type,
    output logic [15:0] stock_locate,
    output logic [47:0] timestamp,
    output logic [63:0] ref_num,
    output logic [7:0]  buy_sell,
    output logic [31:0] share_amt,
    output logic [63:0] stock_sym,
    output logic [31:0] price,

    output logic snapshot_toggle,
    output logic packet_toggle
);

    logic [7:0] circular_buffer [0:BUFFER_SIZE-1];
    logic [$clog2(BUFFER_SIZE)-1:0] write_ptr;
    logic [$clog2(BUFFER_SIZE)-1:0] read_ptr;
    logic [$clog2(BUFFER_SIZE):0] buffer_data_count;
    logic [15:0] current_msg_size;
    logic snapshot_pending;

    function automatic [6:0] count_valid_bytes(input logic [63:0] keep);
        int i;
        begin
            count_valid_bytes = '0;
            for (i = 0; i < 64; i++) begin
                if (keep[i]) begin
                    count_valid_bytes++;
                end
            end
        end
    endfunction

    assign mod_rst_done = 1'b1;

    always_ff @(posedge cmac_clk[0]) begin
        logic [15:0] msg_size;
        logic [6:0]  valid_bytes;
        logic [$clog2(BUFFER_SIZE):0] next_buffer_data_count;

        if (!mod_rstn) begin
            write_ptr        <= '0;
            read_ptr         <= '0;
            buffer_data_count <= '0;
            p_header_flag    <= 1'b0;
            parsing_active   <= 1'b0;
            snapshot_toggle  <= 1'b0;
            snapshot_pending <= 1'b0;
            packet_toggle    <= 1'b0;
            current_msg_size <= '0;

            dst_mac          <= '0;
            src_mac          <= '0;
            header_checksum  <= '0;
            src_ip           <= '0;
            dst_ip           <= '0;
            src_port         <= '0;
            dst_port         <= '0;
            length           <= '0;
            checksum         <= '0;
            section          <= '0;
            seq              <= '0;
            msg_num          <= '0;
            msg_count        <= '0;
            msg_len          <= '0;
            spillover_len    <= '0;
            buffer           <= '0;

            msg_type         <= '0;
            stock_locate     <= '0;
            timestamp        <= '0;
            ref_num          <= '0;
            buy_sell         <= '0;
            share_amt        <= '0;
            stock_sym        <= '0;
            price            <= '0;
        end
        else begin
            next_buffer_data_count = buffer_data_count;
            parsing_active <= 1'b0;

            if (s_axis_cmac_rx_tvalid[0]) begin
                if (!p_header_flag) begin
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
                    msg_count        <= '0;

                    circular_buffer[write_ptr] <= s_axis_cmac_rx_tdata[15:8];
                    circular_buffer[(write_ptr + 1) % BUFFER_SIZE] <= s_axis_cmac_rx_tdata[7:0];
                    write_ptr <= (write_ptr + 2) % BUFFER_SIZE;
                    next_buffer_data_count = next_buffer_data_count + 2;
                    p_header_flag <= 1'b1;
                end
                else begin
                    valid_bytes = count_valid_bytes(s_axis_cmac_rx_tkeep[63:0]);
                    for (int i = 0; i < 64; i++) begin
                        if (s_axis_cmac_rx_tkeep[i]) begin
                            circular_buffer[(write_ptr + i) % BUFFER_SIZE] <= s_axis_cmac_rx_tdata[511 - (i * 8) -: 8];
                        end
                    end

                    write_ptr <= (write_ptr + valid_bytes) % BUFFER_SIZE;
                    next_buffer_data_count = next_buffer_data_count + valid_bytes;
                end

                if (s_axis_cmac_rx_tlast[0]) begin
                    p_header_flag <= 1'b0;
                    packet_toggle <= ~packet_toggle;
                end
            end

            if (snapshot_pending) begin
                snapshot_toggle  <= ~snapshot_toggle;
                snapshot_pending <= 1'b0;
            end

            // Use buffer_data_count (NBA-stable from prior cycle) — not
            // next_buffer_data_count — so the parser only operates on bytes
            // whose buffer writes have already settled. Otherwise the parse
            // reads X from circular_buffer entries being written this cycle.
            if ((buffer_data_count >= 2) && (msg_count < msg_num)) begin
                msg_size = {circular_buffer[read_ptr], circular_buffer[(read_ptr + 1) % BUFFER_SIZE]} + 16'd2;
                current_msg_size <= msg_size;

                if ((buffer_data_count >= msg_size) && (msg_size > 16'd2) && (msg_size <= MAX_MSG_SIZE + 16'd2)) begin
                    parsing_active <= 1'b1;
                    snapshot_pending <= 1'b1;

                    msg_type <= circular_buffer[(read_ptr + 2) % BUFFER_SIZE];

                    case (circular_buffer[(read_ptr + 2) % BUFFER_SIZE])
                        8'h41: begin
                            stock_locate <= {circular_buffer[(read_ptr + 3) % BUFFER_SIZE], circular_buffer[(read_ptr + 4) % BUFFER_SIZE]};
                            timestamp <= {
                                circular_buffer[(read_ptr + 7) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 8) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 9) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 10) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 11) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 12) % BUFFER_SIZE]
                            };

                            for (int i = 0; i < 8; i++) begin
                                ref_num[63 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 13 + i) % BUFFER_SIZE];
                            end

                            buy_sell <= circular_buffer[(read_ptr + 21) % BUFFER_SIZE];

                            for (int i = 0; i < 4; i++) begin
                                share_amt[31 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 22 + i) % BUFFER_SIZE];
                            end

                            for (int i = 0; i < 8; i++) begin
                                stock_sym[63 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 26 + i) % BUFFER_SIZE];
                            end

                            for (int i = 0; i < 4; i++) begin
                                price[31 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 34 + i) % BUFFER_SIZE];
                            end
                        end

                        8'h69: begin
                            stock_locate <= {circular_buffer[(read_ptr + 3) % BUFFER_SIZE], circular_buffer[(read_ptr + 4) % BUFFER_SIZE]};
                            timestamp <= {
                                circular_buffer[(read_ptr + 7) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 8) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 9) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 10) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 11) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 12) % BUFFER_SIZE]
                            };

                            for (int i = 0; i < 8; i++) begin
                                ref_num[63 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 13 + i) % BUFFER_SIZE];
                            end

                            for (int i = 0; i < 4; i++) begin
                                share_amt[31 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 21 + i) % BUFFER_SIZE];
                            end
                        end

                        8'h68: begin
                            stock_locate <= {circular_buffer[(read_ptr + 3) % BUFFER_SIZE], circular_buffer[(read_ptr + 4) % BUFFER_SIZE]};
                            timestamp <= {
                                circular_buffer[(read_ptr + 7) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 8) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 9) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 10) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 11) % BUFFER_SIZE],
                                circular_buffer[(read_ptr + 12) % BUFFER_SIZE]
                            };

                            for (int i = 0; i < 8; i++) begin
                                ref_num[63 - (i * 8) -: 8] <= circular_buffer[(read_ptr + 13 + i) % BUFFER_SIZE];
                            end
                        end

                        default: begin
                        end
                    endcase

                    for (int i = 0; i < 64; i++) begin
                        buffer[511 - (i * 8) -: 8] <= circular_buffer[(read_ptr + i) % BUFFER_SIZE];
                    end

                    read_ptr <= (read_ptr + msg_size) % BUFFER_SIZE;
                    next_buffer_data_count = next_buffer_data_count - msg_size;

                    if (msg_count + 16'd1 == msg_num) begin
                        msg_count <= '0;
                    end
                    else begin
                        msg_count <= msg_count + 16'd1;
                    end
                end
            end

            buffer_data_count <= next_buffer_data_count;
        end
    end

endmodule: packetparser_322mhz