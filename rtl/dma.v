////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : DMA Engine
//  File Name        : dma.v
//  Description      : AXI4 master DMA path for RAM-to-QSPI and QSPI-to-RAM transfers using simple INCR bursts.
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module dma (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // ---------- DMA Configuration ----------
    input  wire        i_dma_dir,      // 0=RAM-to-QSPI, 1=QSPI-to-RAM
    input  wire        i_incr_addr,
    input  wire [31:0] i_dma_addr,
    input  wire [31:0] i_dma_len,
    input  wire        i_dma_start,

    // ---------- AXI4 Master Write Address Channel ----------
    output reg  [31:0] o_awaddr,
    output reg  [7:0]  o_awlen,
    output wire [2:0]  o_awsize,
    output wire [1:0]  o_awburst,
    output reg         o_awvalid,
    input  wire        i_awready,

    // ---------- AXI4 Master Write Data Channel ----------
    output reg  [31:0] o_wdata,
    output reg  [3:0]  o_wstrb,
    output reg         o_wlast,
    output reg         o_wvalid,
    input  wire        i_wready,

    // ---------- AXI4 Master Write Response Channel ----------
    input  wire [1:0]  i_bresp,
    input  wire        i_bvalid,
    output reg         o_bready,

    // ---------- AXI4 Master Read Address Channel ----------
    output reg  [31:0] o_araddr,
    output reg  [7:0]  o_arlen,
    output wire [2:0]  o_arsize,
    output wire [1:0]  o_arburst,
    output reg         o_arvalid,
    input  wire        i_arready,

    // ---------- AXI4 Master Read Data Channel ----------
    input  wire [31:0] i_rdata,
    input  wire [1:0]  i_rresp,
    input  wire        i_rlast,
    input  wire        i_rvalid,
    output reg         o_rready,

    // ---------- RX FIFO Interface: QSPI-to-RAM ----------
    input  wire [31:0] i_rx_data,
    input  wire        i_rx_empty,
    output reg         o_rx_ren,

    // ---------- TX FIFO Interface: RAM-to-QSPI ----------
    output reg  [31:0] o_tx_data,
    output reg         o_tx_valid,
    input  wire        i_tx_ready,

    // ---------- Status ----------
    output reg         o_dma_done,
    output reg         o_dma_error
);

    // Revision 1.0 fixed AXI attributes.
    assign o_awsize  = 3'b010; // 4 bytes/beat
    assign o_arsize  = 3'b010;
    assign o_awburst = 2'b01;  // INCR
    assign o_arburst = 2'b01;

    function [8:0] f_beats_for_bytes;
        input [31:0] bytes;
        input        incr;
        reg [31:0] words;
        begin
            words = (bytes + 32'd3) >> 2;
            if (words == 0)
                f_beats_for_bytes = 9'd0;
            else if (!incr)
                f_beats_for_bytes = 9'd1;
            else if (words > 256)
                f_beats_for_bytes = 9'd256;
            else
                f_beats_for_bytes = words[8:0];
        end
    endfunction

    localparam [3:0] S_IDLE      = 4'd0,
                     S_W_AW      = 4'd1,
                     S_W_FETCH   = 4'd2,
                     S_W_CAPTURE = 4'd3,
                     S_W_SEND    = 4'd4,
                     S_W_RESP    = 4'd5,
                     S_R_AR      = 4'd6,
                     S_R_DATA    = 4'd7,
                     S_R_PUSH    = 4'd8,
                     S_W_DELAY   = 4'd9;

    reg [3:0]  r_state;
    reg [31:0] r_addr;
    reg [31:0] r_bytes_remaining;
    reg [8:0]  r_burst_beats;
    reg [8:0]  r_beats_left;
    reg [31:0] r_read_hold;
    reg        r_read_last;

    wire [8:0] w_next_burst_beats = f_beats_for_bytes(r_bytes_remaining, i_incr_addr);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state           <= S_IDLE;
            r_addr            <= 32'd0;
            r_bytes_remaining <= 32'd0;
            r_burst_beats     <= 9'd0;
            r_beats_left      <= 9'd0;
            r_read_hold       <= 32'd0;
            r_read_last       <= 1'b1;
            o_awaddr          <= 32'd0;
            o_awlen           <= 8'd0;
            o_awvalid         <= 1'b0;
            o_wdata           <= 32'd0;
            o_wstrb           <= 4'd0;
            o_wlast           <= 1'b0;
            o_wvalid          <= 1'b0;
            o_bready          <= 1'b0;
            o_araddr          <= 32'd0;
            o_arlen           <= 8'd0;
            o_arvalid         <= 1'b0;
            o_rready          <= 1'b0;
            o_rx_ren          <= 1'b0;
            o_tx_data         <= 32'd0;
            o_tx_valid        <= 1'b0;
            o_dma_done        <= 1'b0;
            o_dma_error       <= 1'b0;
        end else begin
            o_dma_done  <= 1'b0;
            o_dma_error <= 1'b0;
            o_rx_ren    <= 1'b0;
            o_rready    <= 1'b0;
            o_bready    <= 1'b0;

            if (i_dma_start && (r_state == S_IDLE)) begin
                r_addr            <= i_dma_addr;
                r_bytes_remaining <= i_dma_len;
                o_dma_error       <= 1'b0;
                if (i_dma_len == 0) begin
                    o_dma_done <= 1'b1;
                end else if (i_dma_dir) begin
                    r_burst_beats <= f_beats_for_bytes(i_dma_len, i_incr_addr);
                    r_beats_left  <= f_beats_for_bytes(i_dma_len, i_incr_addr);
                    o_awaddr      <= i_dma_addr;
                    o_awlen       <= f_beats_for_bytes(i_dma_len, i_incr_addr) - 1'b1;
                    o_awvalid     <= 1'b1;
                    r_state       <= S_W_AW;
                end else begin
                    r_burst_beats <= f_beats_for_bytes(i_dma_len, i_incr_addr);
                    r_beats_left  <= f_beats_for_bytes(i_dma_len, i_incr_addr);
                    o_araddr      <= i_dma_addr;
                    o_arlen       <= f_beats_for_bytes(i_dma_len, i_incr_addr) - 1'b1;
                    o_arvalid     <= 1'b1;
                    r_state       <= S_R_AR;
                end
            end

            case (r_state)
                S_IDLE: begin
                    // Preserve the launch-cycle address VALID asserted by the
                    // start path.  Clearing it here would erase the request
                    // before an AXI handshake can occur.
                    if (!i_dma_start) begin
                        o_awvalid  <= 1'b0;
                        o_wvalid   <= 1'b0;
                        o_arvalid  <= 1'b0;
                        o_tx_valid <= 1'b0;
                    end
                end

                // ---------------- QSPI-to-RAM / AXI write ----------------
                S_W_AW: begin
                    if (o_awvalid && i_awready) begin
                        o_awvalid <= 1'b0;
                        r_state   <= S_W_FETCH;
                    end else if (o_awvalid && !i_awready) begin
                        o_awvalid <= 1'b1;
                    end
                end

                S_W_FETCH: begin
                    if (!i_rx_empty) begin
                        o_rx_ren <= 1'b1;
                        // RX FIFO data is registered on the pop edge.  Wait
                        // one clock before sampling its output.
                        r_state  <= S_W_DELAY;
                    end
                end

                S_W_DELAY: begin
                    r_state <= S_W_CAPTURE;
                end

                S_W_CAPTURE: begin
                    o_wdata <= i_rx_data;
                    if (r_bytes_remaining >= 4)
                        o_wstrb <= 4'b1111;
                    else begin
                        case (r_bytes_remaining[1:0])
                            2'd1: o_wstrb <= 4'b0001;
                            2'd2: o_wstrb <= 4'b0011;
                            2'd3: o_wstrb <= 4'b0111;
                            default: o_wstrb <= 4'b1111;
                        endcase
                    end
                    o_wlast  <= (r_beats_left == 1);
                    o_wvalid <= 1'b1;
                    r_state  <= S_W_SEND;
                end

                S_W_SEND: begin
                    if (o_wvalid && i_wready) begin
                        o_wvalid <= 1'b0;
                        if (r_bytes_remaining > 4)
                            r_bytes_remaining <= r_bytes_remaining - 4;
                        else
                            r_bytes_remaining <= 0;

                        if (r_beats_left > 1) begin
                            r_beats_left <= r_beats_left - 1'b1;
                            r_state      <= S_W_FETCH;
                        end else begin
                            r_beats_left <= 0;
                            r_state      <= S_W_RESP;
                        end
                    end
                end

                S_W_RESP: begin
                    o_bready <= 1'b1;
                    if (i_bvalid) begin
                        if (i_bresp == 2'b11) begin
                            o_dma_error <= 1'b1;
                            o_dma_done  <= 1'b1;
                            r_state     <= S_IDLE;
                        end else if (r_bytes_remaining == 0) begin
                            o_dma_done <= 1'b1;
                            r_state    <= S_IDLE;
                        end else begin
                            if (i_incr_addr)
                                r_addr <= r_addr + (r_burst_beats << 2);
                            r_burst_beats <= f_beats_for_bytes(r_bytes_remaining, i_incr_addr);
                            r_beats_left  <= f_beats_for_bytes(r_bytes_remaining, i_incr_addr);
                            o_awaddr      <= i_incr_addr ? (r_addr + (r_burst_beats << 2)) : r_addr;
                            o_awlen       <= f_beats_for_bytes(r_bytes_remaining, i_incr_addr) - 1'b1;
                            o_awvalid     <= 1'b1;
                            r_state       <= S_W_AW;
                        end
                    end
                end

                // ---------------- RAM-to-QSPI / AXI read ----------------
                S_R_AR: begin
                    if (o_arvalid && i_arready) begin
                        o_arvalid <= 1'b0;
                        r_state   <= S_R_DATA;
                    end
                end

                S_R_DATA: begin
                    if ((r_bytes_remaining <= 32'd16) && !o_tx_valid)
                        o_rready <= 1'b1;
                    if (i_rvalid && o_rready) begin
                        r_read_hold <= i_rdata;
                        r_read_last <= i_rlast;
                        if (i_rresp == 2'b11) begin
                            o_dma_error <= 1'b1;
                            o_dma_done  <= 1'b1;
                            r_state     <= S_IDLE;
                        end else begin
                            o_tx_data  <= i_rdata;
                            o_tx_valid <= 1'b1;
                            r_state    <= S_R_PUSH;
                        end
                    end
                end

                S_R_PUSH: begin
                    if (o_tx_valid && i_tx_ready) begin
                        o_tx_valid <= 1'b0;
                        if (r_bytes_remaining > 4)
                            r_bytes_remaining <= r_bytes_remaining - 4;
                        else
                            r_bytes_remaining <= 0;

                        if (r_beats_left > 1) begin
                            // RLAST must only be asserted on the final beat of the burst.
                            if (r_read_last) begin
                                o_dma_error <= 1'b1;
                                o_dma_done  <= 1'b1;
                                r_state     <= S_IDLE;
                            end else begin
                                r_beats_left <= r_beats_left - 1'b1;
                                r_state      <= S_R_DATA;
                            end
                        end else begin
                            if (!r_read_last) begin
                                o_dma_error <= 1'b1;
                                o_dma_done  <= 1'b1;
                                r_state     <= S_IDLE;
                            end else if (r_bytes_remaining <= 4) begin
                                o_dma_done <= 1'b1;
                                r_state    <= S_IDLE;
                            end else begin
                                if (i_incr_addr)
                                    r_addr <= r_addr + (r_burst_beats << 2);
                                r_burst_beats <= f_beats_for_bytes(r_bytes_remaining - 4, i_incr_addr);
                                r_beats_left  <= f_beats_for_bytes(r_bytes_remaining - 4, i_incr_addr);
                                o_araddr      <= i_incr_addr ? (r_addr + (r_burst_beats << 2)) : r_addr;
                                o_arlen       <= f_beats_for_bytes(r_bytes_remaining - 4, i_incr_addr) - 1'b1;
                                o_arvalid     <= 1'b1;
                                r_state       <= S_R_AR;
                            end
                        end
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
