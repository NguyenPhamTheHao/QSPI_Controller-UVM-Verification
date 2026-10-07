////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : Command Engine
//  File Name        : ce.v
//  Description      : Sequences indirect QSPI command execution and optional DMA operation.
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module ce (
    input  wire i_clk,
    input  wire i_rst_n,

    input  wire i_cmd_trigger,
    input  wire i_dma_en,
    input  wire i_dma_dir,

    input  wire i_qspi_done,
    input  wire i_dma_done,

    output reg  o_qspi_start,
    output reg  o_dma_start,
    output reg  o_busy,
    output reg  o_clear,
    output reg  o_cmd_done
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_WAIT  = 2'd2,
                     S_DONE  = 2'd3;

    reg [1:0] r_state;
    reg       r_need_dma;
    reg       r_qspi_seen;
    reg       r_dma_seen;

    // i_dma_dir is retained as part of the command-engine interface. Both DMA directions
    // are started together with QSPI so that FIFO traffic can stream concurrently.
    wire unused_dma_dir = i_dma_dir;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state      <= S_IDLE;
            r_need_dma   <= 1'b0;
            r_qspi_seen  <= 1'b0;
            r_dma_seen   <= 1'b0;
            o_qspi_start <= 1'b0;
            o_dma_start  <= 1'b0;
            o_busy       <= 1'b0;
            o_clear      <= 1'b0;
            o_cmd_done   <= 1'b0;
        end else begin
            o_qspi_start <= 1'b0;
            o_dma_start  <= 1'b0;
            o_clear      <= 1'b0;
            o_cmd_done   <= 1'b0;

            case (r_state)
                S_IDLE: begin
                    o_busy      <= 1'b0;
                    r_qspi_seen <= 1'b0;
                    r_dma_seen  <= 1'b0;
                    if (i_cmd_trigger) begin
                        r_need_dma <= i_dma_en;
                        o_busy     <= 1'b1;
                        r_state    <= S_START;
                    end
                end

                S_START: begin
                    o_busy       <= 1'b1;
                    o_qspi_start <= 1'b1;
                    if (r_need_dma)
                        o_dma_start <= 1'b1;
                    o_clear <= 1'b1;
                    r_state <= S_WAIT;
                end

                S_WAIT: begin
                    o_busy <= 1'b1;
                    if (i_qspi_done)
                        r_qspi_seen <= 1'b1;
                    if (i_dma_done)
                        r_dma_seen <= 1'b1;

                    if ((r_qspi_seen || i_qspi_done) &&
                        (!r_need_dma || r_dma_seen || i_dma_done)) begin
                        r_state <= S_DONE;
                    end
                end

                S_DONE: begin
                    o_busy     <= 1'b0;
                    o_cmd_done <= 1'b1;
                    r_state    <= S_IDLE;
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
