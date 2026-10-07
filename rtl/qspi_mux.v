////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : QSPI Multiplexer
//  File Name        : qspi_mux.v
//  Description      : Selects QSPI command/control fields from XIP or the command path; XIP has priority while enabled.
//  Authors          : Truong Quoc Bao, Thai Hai Dang, Nguyen Bao Tinh
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module qspi_mux (
    // ---------- Control Select ----------
    input  wire        i_xip_en,        // 1: XIP path, 0: Command Engine path

    // ---------- CE inputs ----------
    input  wire        i_ce_qspi_start,
    input  wire [1:0]  i_ce_cmd_lanes,
    input  wire [1:0]  i_ce_addr_lanes,
    input  wire [1:0]  i_ce_data_lanes,
    input  wire [1:0]  i_ce_addr_bytes,
    input  wire [7:0]  i_ce_opcode,
    input  wire        i_ce_mode_en,
    input  wire [7:0]  i_ce_mode_bits,
    input  wire [3:0]  i_ce_dummy_cycles,
    input  wire [31:0] i_ce_cmd_addr,
    input  wire [31:0] i_ce_cmd_len,
    input  wire        i_ce_dir,

    // ---------- XIP inputs ----------
    input  wire        i_xip_qspi_start,
    input  wire [1:0]  i_xip_cmd_lanes,
    input  wire [1:0]  i_xip_addr_lanes,
    input  wire [1:0]  i_xip_data_lanes,
    input  wire [1:0]  i_xip_addr_bytes,
    input  wire [7:0]  i_xip_opcode,
    input  wire        i_xip_mode_en,
    input  wire [7:0]  i_xip_mode_bits,
    input  wire [3:0]  i_xip_dummy_cycles,
    input  wire [31:0] i_xip_cmd_addr,
    input  wire [31:0] i_xip_cmd_len,
    input  wire        i_xip_dir,

    // ---------- Outputs to QSPI Controller ----------
    output reg         o_qspi_start,
    output reg  [1:0]  o_cmd_lanes,
    output reg  [1:0]  o_addr_lanes,
    output reg  [1:0]  o_data_lanes,
    output reg  [1:0]  o_addr_bytes,
    output reg  [7:0]  o_opcode,
    output reg         o_mode_en,
    output reg  [7:0]  o_mode_bits,
    output reg  [3:0]  o_dummy_cycles,
    output reg  [31:0] o_cmd_addr,
    output reg  [31:0] o_cmd_len,
    output reg         o_dir
);

    // ====================================================
    // COMBINATIONAL MUX LOGIC
    // ====================================================
    always @(*) begin
        if (i_xip_en) begin
            o_qspi_start   = i_xip_qspi_start;
            o_cmd_lanes    = i_xip_cmd_lanes;
            o_addr_lanes   = i_xip_addr_lanes;
            o_data_lanes   = i_xip_data_lanes;
            o_addr_bytes   = i_xip_addr_bytes;
            o_opcode       = i_xip_opcode;
            o_mode_en      = i_xip_mode_en;
            o_mode_bits    = i_xip_mode_bits;
            o_dummy_cycles = i_xip_dummy_cycles;
            o_cmd_addr     = i_xip_cmd_addr;
            o_cmd_len      = i_xip_cmd_len;
            o_dir          = i_xip_dir;
        end else begin
            o_qspi_start   = i_ce_qspi_start;
            o_cmd_lanes    = i_ce_cmd_lanes;
            o_addr_lanes   = i_ce_addr_lanes;
            o_data_lanes   = i_ce_data_lanes;
            o_addr_bytes   = i_ce_addr_bytes;
            o_opcode       = i_ce_opcode;
            o_mode_en      = i_ce_mode_en;
            o_mode_bits    = i_ce_mode_bits;
            o_dummy_cycles = i_ce_dummy_cycles;
            o_cmd_addr     = i_ce_cmd_addr;
            o_cmd_len      = i_ce_cmd_len;
            o_dir          = i_ce_dir;
        end
    end

endmodule
`default_nettype wire
