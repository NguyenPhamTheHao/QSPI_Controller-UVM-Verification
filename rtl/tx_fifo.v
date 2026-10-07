////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : TX FIFO
//  File Name        : tx_fifo.v
//  Description      : Buffers transmit data from CSR to the QSPI controller.
//  Authors          : Truong Quoc Bao, Thai Hai Dang, Nguyen Bao Tinh
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module tx_fifo #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 4
)(
    // ---------- Clock and Reset ----------
    input  wire                 i_clk,
    input  wire                 i_rst_n,

    // ---------- Write Interface (CSR/CPU side) ----------
    input  wire                 i_tx_wen,
    input  wire [WIDTH-1:0]     i_tx_data,
    output wire                 o_tx_full,

    // ---------- Read Interface (QSPI Controller side) ----------
    input  wire                 i_tx_ren,
    output reg  [WIDTH-1:0]     o_tx_data,
    output wire                 o_tx_empty,

    // ---------- FIFO Status ----------
    output wire [3:0]           o_tx_level
);

    // =====================================================
    // INTERNAL REGISTERS AND MEMORY
    // =====================================================
    reg [WIDTH-1:0]         r_mem [0:DEPTH-1];
    reg [$clog2(DEPTH)-1:0] r_wptr, r_rptr;
    reg [$clog2(DEPTH):0]   r_cnt;

    // =====================================================
    // CONTINUOUS ASSIGNMENTS
    // =====================================================
    assign o_tx_full  = (r_cnt == DEPTH);
    assign o_tx_empty = (r_cnt == 0);
    assign o_tx_level = r_cnt;

    // =====================================================
    // SEQUENTIAL LOGIC
    // =====================================================
    integer i;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1) r_mem[i] <= {WIDTH{1'b0}};
            r_wptr    <= {$clog2(DEPTH){1'b0}};
            r_rptr    <= {$clog2(DEPTH){1'b0}};
            r_cnt     <= {($clog2(DEPTH)+1){1'b0}};
            o_tx_data <= {WIDTH{1'b0}};
        end else begin
            if (i_tx_ren && i_tx_wen && !o_tx_empty && !o_tx_full) begin
                r_mem[r_wptr] <= i_tx_data;
                r_wptr        <= r_wptr + 1'b1;
                o_tx_data     <= r_mem[r_rptr];
                r_rptr        <= r_rptr + 1'b1;
            end else begin
                // Write logic
                if (i_tx_wen && !o_tx_full) begin
                    r_mem[r_wptr] <= i_tx_data;
                    r_wptr        <= r_wptr + 1'b1;
                    r_cnt         <= r_cnt + 1'b1;
                end

                // Read logic
                if (i_tx_ren && !o_tx_empty) begin
                    o_tx_data <= r_mem[r_rptr];
                    r_rptr    <= r_rptr + 1'b1;
                    r_cnt     <= r_cnt - 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
