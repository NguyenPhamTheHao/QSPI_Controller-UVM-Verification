////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : Execute-In-Place (XIP) Engine
//  File Name        : xip.v
//  Description      : Converts an AXI4-Lite read request into a QSPI read command and returns one 32-bit data beat.
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module xip (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // ---------- RX FIFO Interface ----------
    input  wire [31:0] i_rx_data,
    input  wire        i_rx_empty,
    output reg         o_rx_ren,

    // ---------- AXI4-Lite Slave Read Address Channel ----------
    input  wire [31:0] i_araddr,
    input  wire [2:0]  i_arprot,      // present for protocol compliance; functionally ignored
    input  wire        i_arvalid,
    output reg         o_arready,

    // ---------- AXI4-Lite Slave Read Data Channel ----------
    output reg  [31:0] o_rdata,
    output reg  [1:0]  o_rresp,
    output reg         o_rvalid,
    input  wire        i_rready,

    // ---------- Control from CSR ----------
    input  wire        i_xip_en,

    // ---------- XIP Configuration Inputs ----------
    input  wire [1:0]  i_xip_lanes,
    input  wire [1:0]  i_xip_addr_lanes,
    input  wire [1:0]  i_xip_data_lanes,
    input  wire [1:0]  i_xip_addr_bytes,
    input  wire        i_xip_mode_en,
    input  wire [3:0]  i_xip_dummy_cycles,
    input  wire [7:0]  i_xip_read_op,
    input  wire [7:0]  i_xip_mode_bits,

    // ---------- QSPI Controller Interface ----------
    output reg         o_qspi_start,
    input  wire        i_qspi_done,
    input  wire        i_qspi_error,

    output reg  [1:0]  o_cmd_lanes,
    output reg  [1:0]  o_addr_lanes,
    output reg  [1:0]  o_data_lanes,
    output reg  [1:0]  o_addr_bytes,
    output reg         o_mode_en,
    output reg  [3:0]  o_dummy_cycles,
    output reg  [7:0]  o_opcode,
    output reg  [7:0]  o_mode_bits,
    output reg  [31:0] o_cmd_addr,
    output reg  [31:0] o_cmd_len,
    output reg         o_dir,

    // ---------- Status Outputs ----------
    output reg         o_xip_active,
    output reg         o_xip_done
);

    localparam [2:0] S_IDLE       = 3'd0,
                     S_ISSUE_CMD  = 3'd1,
                     S_WAIT_QSPI  = 3'd2,
                     S_RX_REQ     = 3'd3,
                     S_RX_CAPTURE = 3'd4,
                     S_RESP       = 3'd5,
                     S_RX_DELAY   = 3'd6;

    reg [2:0]  r_state;
    reg [31:0] r_araddr;
    reg        r_error_seen;

    // i_arprot is intentionally not interpreted in Revision 1.0.
    wire unused_arprot = ^i_arprot;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state        <= S_IDLE;
            r_araddr       <= 32'd0;
            r_error_seen   <= 1'b0;
            o_arready      <= 1'b0;
            o_rdata        <= 32'd0;
            o_rresp        <= 2'b00;
            o_rvalid       <= 1'b0;
            o_rx_ren       <= 1'b0;
            o_qspi_start   <= 1'b0;
            o_cmd_lanes    <= 2'b00;
            o_addr_lanes   <= 2'b00;
            o_data_lanes   <= 2'b00;
            o_addr_bytes   <= 2'b00;
            o_mode_en      <= 1'b0;
            o_dummy_cycles <= 4'd0;
            o_opcode       <= 8'd0;
            o_mode_bits    <= 8'd0;
            o_cmd_addr     <= 32'd0;
            o_cmd_len      <= 32'd4;
            o_dir          <= 1'b1;
            o_xip_active   <= 1'b0;
            o_xip_done     <= 1'b0;
        end else begin
            o_arready    <= 1'b0;
            o_rx_ren     <= 1'b0;
            o_qspi_start <= 1'b0;
            o_xip_done   <= 1'b0;

            if (i_qspi_error && (r_state != S_IDLE))
                r_error_seen <= 1'b1;

            case (r_state)
                S_IDLE: begin
                    o_xip_active <= 1'b0;
                    o_rvalid     <= 1'b0;
                    o_rresp      <= 2'b00;
                    r_error_seen <= 1'b0;
                    o_arready    <= i_xip_en;
                    if (i_xip_en && i_arvalid) begin
                        r_araddr     <= i_araddr;
                        o_xip_active <= 1'b1;
                        r_state      <= S_ISSUE_CMD;
                    end
                end

                S_ISSUE_CMD: begin
                    o_cmd_lanes    <= i_xip_lanes;
                    o_addr_lanes   <= i_xip_addr_lanes;
                    o_data_lanes   <= i_xip_data_lanes;
                    o_addr_bytes   <= i_xip_addr_bytes;
                    o_mode_en      <= i_xip_mode_en;
                    o_dummy_cycles <= i_xip_dummy_cycles;
                    o_opcode       <= i_xip_read_op;
                    o_mode_bits    <= i_xip_mode_bits;
                    o_cmd_addr     <= r_araddr;
                    o_cmd_len      <= 32'd4;
                    o_dir          <= 1'b1;
                    o_qspi_start   <= 1'b1;
                    r_state        <= S_WAIT_QSPI;
                end

                S_WAIT_QSPI: begin
                    if (i_qspi_done) begin
                        if (r_error_seen || i_qspi_error) begin
                            o_rdata  <= 32'd0;
                            o_rresp  <= 2'b10; // SLVERR
                            o_rvalid <= 1'b1;
                            r_state  <= S_RESP;
                        end else begin
                            r_state <= S_RX_REQ;
                        end
                    end
                end

                S_RX_REQ: begin
                    if (!i_rx_empty) begin
                        o_rx_ren <= 1'b1;
                        // RX FIFO output is registered on the pop edge.
                        r_state  <= S_RX_DELAY;
                    end
                end

                S_RX_DELAY: begin
                    r_state <= S_RX_CAPTURE;
                end

                S_RX_CAPTURE: begin
                    // RX FIFO presents popped data one cycle after read enable.
                    o_rdata  <= i_rx_data;
                    o_rresp  <= r_error_seen ? 2'b10 : 2'b00;
                    o_rvalid <= 1'b1;
                    r_state  <= S_RESP;
                end

                S_RESP: begin
                    if (o_rvalid && i_rready) begin
                        o_rvalid     <= 1'b0;
                        o_xip_active <= 1'b0;
                        o_xip_done   <= 1'b1;
                        r_state      <= S_IDLE;
                    end else if (o_rvalid && !i_rready) begin
                        o_rvalid <= 1'b0;
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
