////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : Control and Status Register (CSR)
//  File Name        : csr.v
//  Description      : Implements the APB register map, control/status reporting, FIFO access, and interrupt logic.
//  Authors          : Truong Quoc Bao, Thai Hai Dang, Nguyen Bao Tinh
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module csr #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer DATA_WIDTH = 32
) (
    // ---------- APB Interface ----------
    input  wire                  pclk,
    input  wire                  presetn,
    input  wire                  psel,
    input  wire                  penable,
    input  wire                  pwrite,
    input  wire [ADDR_WIDTH-1:0] paddr,
    input  wire [DATA_WIDTH-1:0] pwdata,
    input  wire [3:0]            pstrb,
    input  wire [2:0]            pprot,
    output reg                   pready,
    output reg                   pslverr,
    output reg  [DATA_WIDTH-1:0] prdata,

    // ---------- Control Outputs (CTRL) ----------
    output wire                  o_ctrl_enable,
    output wire                  o_ctrl_xip_en,
    output wire                  o_ctrl_quad_en,
    output wire                  o_ctrl_cpol,
    output wire                  o_ctrl_cpha,
    output wire                  o_ctrl_cmd_trigger, // pulse
    output wire                  o_ctrl_dma_en,

    // ---------- Clock Divider Output (CLK_DIV) ----------
    output wire [2:0]            o_clk_div,

    // ---------- Chip Select Control (CS_CTRL) ----------
    output wire                  o_cs_auto,
    output wire                  o_cs_level,
    output wire [1:0]            o_cs_delay,

    // ---------- XIP Configuration Outputs (XIP_CFG) ----------
    output wire [1:0]            o_xip_lanes,
    output wire [1:0]            o_xip_addr_lanes,
    output wire [1:0]            o_xip_data_lanes,
    output wire [1:0]            o_xip_addr_bytes,
    output wire                  o_xip_mode_en,
    output wire [3:0]            o_xip_dummy_cycles,

    // ---------- XIP Command Outputs (XIP_CMD) ----------
    output wire [7:0]            o_xip_read_op,
    output wire [7:0]            o_xip_mode_bits,

    // ---------- Command Config Outputs (CMD_CFG) ----------
    output wire [1:0]            o_cmd_lanes,
    output wire [1:0]            o_addr_lanes,
    output wire [1:0]            o_data_lanes,
    output wire [1:0]            o_addr_bytes,
    output wire                  o_mode_en,
    output wire [3:0]            o_dummy_cycles,
    output wire                  o_dir,

    // ---------- Command Opcode Outputs (CMD_OP) ----------
    output wire [7:0]            o_opcode,
    output wire [7:0]            o_mode_bits,

    // ---------- Command Address Output (CMD_ADDR) ----------
    output wire [31:0]           o_cmd_addr,

    // ---------- Command Length Output (CMD_LEN) ----------
    output wire [31:0]           o_cmd_len,

    // ---------- Extra Dummy Output (CMD_DUMMY) ----------
    output wire [7:0]            o_extra_dummy,

    // ---------- DMA Config Outputs (DMA_CFG) ----------
    output wire                  o_dma_dir,
    output wire                  o_incr_addr,

    // ---------- DMA Address & Length (DMA_ADDR, DMA_LEN) ----------
    output wire [31:0]           o_dma_addr,
    output wire [31:0]           o_dma_len,

    // ---------- TX FIFO Interface ----------
    output wire [31:0]           o_fifo_tx_data,
    output wire                  o_fifo_tx_we,
    input  wire                  i_tx_full,

    // ---------- Interrupt Enable Outputs (INT_EN) ----------
    output wire                  o_cmd_done_en,
    output wire                  o_dma_done_en,
    output wire                  o_err_en,
    output wire                  o_fifo_tx_empty_en,
    output wire                  o_fifo_rx_full_en,

    // ---------- Status Inputs ----------
    input  wire                  i_busy,
    input  wire                  i_xip_active,
    input  wire                  i_xip_done,
    input  wire                  i_cmd_done,
    input  wire                  i_dma_done,

    // ---------- Interrupt Status Outputs (INT_STAT) ----------
    output wire                  o_cmd_done,
    output wire                  o_dma_done,
    output wire                  o_err,
    output wire                  o_fifo_tx_empty,
    output wire                  o_fifo_rx_full,

    // ---------- RX FIFO Interface ----------
    input  wire [31:0]           i_fifo_rx_data,
    output wire                  o_fifo_rx_re,
    input  wire                  i_rx_empty,

    // ---------- FIFO Status Inputs ----------
    input  wire [3:0]            i_tx_level,
    input  wire [3:0]            i_rx_level,
    input  wire                  i_tx_empty,
    input  wire                  i_rx_full,

    // ---------- Error Status Inputs ----------
    input  wire                  i_timeout,
    input  wire                  i_overrun,
    input  wire                  i_underrun,
    input  wire                  i_dma_error,

    // ---------- Interrupt Line ----------
    output wire                  o_irq,

    // ---------- Clear Trigger Input from CE ----------
    input  wire                  i_clear
);

    // APB4 PPROT is present for interface compliance but is not functionally interpreted.
    wire unused_pprot = ^pprot;

    function [DATA_WIDTH-1:0] f_apply_pstrb;
        input [DATA_WIDTH-1:0] old_value;
        input [DATA_WIDTH-1:0] new_value;
        input [3:0]            strb;
        integer b;
        begin
            f_apply_pstrb = new_value;
            for (b = 0; b < 4; b = b + 1) begin
                if (strb[b])
                    f_apply_pstrb[b*8 +: 8] = new_value[b*8 +: 8];
            end
        end
    endfunction

    // ====================================================
    // REGISTERS MAP
    // ====================================================
    reg [DATA_WIDTH-1:0] r_ctrl;
    reg [DATA_WIDTH-1:0] r_int_en;
    reg [DATA_WIDTH-1:0] r_clk_div;
    reg [DATA_WIDTH-1:0] r_cs_ctrl;
    reg [DATA_WIDTH-1:0] r_xip_cfg;
    reg [DATA_WIDTH-1:0] r_xip_cmd;
    reg [DATA_WIDTH-1:0] r_cmd_cfg;
    reg [DATA_WIDTH-1:0] r_cmd_op;
    reg [DATA_WIDTH-1:0] r_cmd_addr;
    reg [DATA_WIDTH-1:0] r_cmd_len;
    reg [DATA_WIDTH-1:0] r_cmd_dummy;
    reg [DATA_WIDTH-1:0] r_dma_cfg;
    reg [DATA_WIDTH-1:0] r_dma_addr;
    reg [DATA_WIDTH-1:0] r_dma_len;
    reg [DATA_WIDTH-1:0] r_fifo_tx;

    // ---------- Command LUT (4 indirect entries) ----------
    // LUT_CTRL [0]    : LUT_EN
    //          [3:2]  : LUT_INDEX (0..3)
    // Each selected entry mirrors CMD_CFG/CMD_OP/CMD_DUMMY formatting.
    // CMD_ADDR and CMD_LEN remain dynamic per transaction.
    reg [DATA_WIDTH-1:0] r_lut_ctrl;
    reg [DATA_WIDTH-1:0] r_lut_cfg   [0:3];
    reg [DATA_WIDTH-1:0] r_lut_op    [0:3];
    reg [DATA_WIDTH-1:0] r_lut_dummy [0:3];

    wire [1:0] w_lut_index = r_lut_ctrl[3:2];
    wire       w_lut_en    = r_lut_ctrl[0];

    // IP ID: QSPI training architecture 0x0A10, major 1, minor 2 (LUT added).
    localparam [31:0] C_IP_ID = {16'h0A10, 8'h01, 8'h02};

    // Combinational status words
    wire [31:0] w_status    = {28'b0, i_dma_done, i_cmd_done, i_xip_active, i_busy};
    wire [31:0] w_fifo_stat = {22'b0, i_rx_full, i_tx_empty, i_rx_level, i_tx_level};
    wire [31:0] w_err_stat  = {29'b0, i_underrun, i_overrun, i_timeout};

    // FIFO control signals
    reg r_tx_wen;
    reg r_rx_ren;
    assign o_fifo_rx_re   = r_rx_ren;
    assign o_fifo_tx_we   = r_tx_wen;
    assign o_fifo_tx_data = r_fifo_tx;

    // Trigger mechanism
    reg r_cmd_trigger_reg;
    reg r_cmd_trigger_pulse;
    assign o_ctrl_cmd_trigger = r_cmd_trigger_pulse;

    // INT_STAT RW1C latches
    reg r_cmd_done_stat;
    reg r_dma_done_stat;
    reg r_err_stat_latch;
    reg r_fifo_tx_empty_stat;
    reg r_fifo_rx_full_stat;
    reg r_tx_empty_d;
    reg r_rx_full_d;

    // APB FSM states
    localparam [1:0] S_IDLE   = 2'b00,
                     S_SETUP  = 2'b01,
                     S_ACCESS = 2'b10;

    reg [1:0] r_cur_state, r_next_state;

    // APB FSM next state logic
    always @(*) begin
        case (r_cur_state)
            S_IDLE: begin
                if (psel && !penable)
                    r_next_state = S_SETUP;
                else
                    r_next_state = S_IDLE;
            end
            S_SETUP: begin
                if (psel && penable)
                    r_next_state = S_ACCESS;
                else
                    r_next_state = S_SETUP;
            end
            S_ACCESS: begin
                r_next_state = S_IDLE;
            end
            default: begin
                r_next_state = S_IDLE;
            end
        endcase
    end

    // APB FSM state register
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            r_cur_state <= S_IDLE;
        else
            r_cur_state <= r_next_state;
    end

    // Main register file and CMD_TRIGGER logic
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_ctrl      <= {DATA_WIDTH{1'b0}};
            r_int_en    <= {DATA_WIDTH{1'b0}};
            r_clk_div   <= {DATA_WIDTH{1'b0}};
            r_cs_ctrl   <= {DATA_WIDTH{1'b0}};
            r_xip_cfg   <= {DATA_WIDTH{1'b0}};
            r_xip_cmd   <= {DATA_WIDTH{1'b0}};
            r_cmd_cfg   <= {DATA_WIDTH{1'b0}};
            r_cmd_op    <= {DATA_WIDTH{1'b0}};
            r_cmd_addr  <= {DATA_WIDTH{1'b0}};
            r_cmd_len   <= {DATA_WIDTH{1'b0}};
            r_cmd_dummy <= {DATA_WIDTH{1'b0}};
            r_dma_cfg   <= {DATA_WIDTH{1'b0}};
            r_dma_addr  <= {DATA_WIDTH{1'b0}};
            r_dma_len   <= {DATA_WIDTH{1'b0}};
            r_fifo_tx   <= {DATA_WIDTH{1'b0}};
            r_lut_ctrl  <= {DATA_WIDTH{1'b0}};
            r_lut_cfg[0]   <= {DATA_WIDTH{1'b0}};
            r_lut_cfg[1]   <= {DATA_WIDTH{1'b0}};
            r_lut_cfg[2]   <= {DATA_WIDTH{1'b0}};
            r_lut_cfg[3]   <= {DATA_WIDTH{1'b0}};
            r_lut_op[0]    <= {DATA_WIDTH{1'b0}};
            r_lut_op[1]    <= {DATA_WIDTH{1'b0}};
            r_lut_op[2]    <= {DATA_WIDTH{1'b0}};
            r_lut_op[3]    <= {DATA_WIDTH{1'b0}};
            r_lut_dummy[0] <= {DATA_WIDTH{1'b0}};
            r_lut_dummy[1] <= {DATA_WIDTH{1'b0}};
            r_lut_dummy[2] <= {DATA_WIDTH{1'b0}};
            r_lut_dummy[3] <= {DATA_WIDTH{1'b0}};
            prdata      <= {DATA_WIDTH{1'b0}};
            r_tx_wen    <= 1'b0;

            r_cmd_trigger_reg   <= 1'b0;
            r_cmd_trigger_pulse <= 1'b0;

            r_cmd_done_stat      <= 1'b0;
            r_dma_done_stat      <= 1'b0;
            r_err_stat_latch     <= 1'b0;
            r_fifo_tx_empty_stat <= 1'b0;
            r_fifo_rx_full_stat  <= 1'b0;
            r_tx_empty_d         <= 1'b1; // reset-empty is not treated as a FIFO empty event
            r_rx_full_d          <= 1'b0;
        end else begin
            // Default: clear pulses
            r_tx_wen            <= 1'b0;
            r_cmd_trigger_pulse <= 1'b0;

            // Handle APB writes
            if ((r_cur_state == S_ACCESS) && pwrite && penable && psel) begin
                case (paddr)
                    12'h004: begin
                        // Supported CTRL bits: [9] DMA_EN, [8] CMD_TRIGGER, [4:0] core control.
                        // Bit [5] (LSB_FIRST) and all other bits are reserved in the training design.
                        r_ctrl <= f_apply_pstrb(r_ctrl, pwdata, pstrb) & 32'h0000_031F;
                        // Ignore CMD_TRIGGER when ENABLE is written low; this avoids starting CE
                        // for a command that the QSPI controller is intentionally not allowed to accept.
                        if (pstrb[1] && pwdata[8] && (pstrb[0] ? pwdata[0] : r_ctrl[0])) begin
                            // LUT mode snapshots the selected static command profile
                            // before the one-cycle trigger pulse reaches the command engine.
                            // This keeps the active transaction stable even if LUT_INDEX
                            // is reprogrammed while the command is executing.
                            if (w_lut_en) begin
                                r_cmd_cfg   <= r_lut_cfg[w_lut_index];
                                r_cmd_op    <= r_lut_op[w_lut_index];
                                r_cmd_dummy <= r_lut_dummy[w_lut_index];
                            end
                            r_cmd_trigger_reg <= 1'b1;
                        end
                    end
                    12'h00C: r_int_en     <= f_apply_pstrb(r_int_en, pwdata, pstrb);
                    12'h014: r_clk_div    <= f_apply_pstrb(r_clk_div, pwdata, pstrb);
                    12'h018: r_cs_ctrl    <= f_apply_pstrb(r_cs_ctrl, pwdata, pstrb);
                    12'h01C: r_xip_cfg    <= f_apply_pstrb(r_xip_cfg, pwdata, pstrb) & 32'h0000_1FFF; // [14:13] reserved
                    12'h020: r_xip_cmd    <= f_apply_pstrb(r_xip_cmd, pwdata, pstrb) & 32'h00FF_00FF; // [15:8] XIP write opcode reserved
                    12'h024: r_cmd_cfg    <= f_apply_pstrb(r_cmd_cfg, pwdata, pstrb) & 32'h0000_3FFF;
                    12'h028: r_cmd_op     <= f_apply_pstrb(r_cmd_op, pwdata, pstrb) & 32'h0000_FFFF;
                    12'h02C: r_cmd_addr   <= f_apply_pstrb(r_cmd_addr, pwdata, pstrb);
                    12'h030: r_cmd_len    <= f_apply_pstrb(r_cmd_len, pwdata, pstrb);
                    12'h034: r_cmd_dummy  <= f_apply_pstrb(r_cmd_dummy, pwdata, pstrb) & 32'h0000_00FF;
                    12'h038: r_dma_cfg    <= f_apply_pstrb(r_dma_cfg, pwdata, pstrb) & 32'h0000_0030; // [3:0] burst size reserved
                    12'h03C: r_dma_addr   <= f_apply_pstrb(r_dma_addr, pwdata, pstrb);
                    12'h040: r_dma_len    <= f_apply_pstrb(r_dma_len, pwdata, pstrb);

                    // Command LUT indirect programming interface
                    12'h054: r_lut_ctrl <= f_apply_pstrb(r_lut_ctrl, pwdata, pstrb) & 32'h0000_000D; // [0]=enable, [3:2]=index
                    12'h058: r_lut_cfg[w_lut_index]   <= f_apply_pstrb(r_lut_cfg[w_lut_index], pwdata, pstrb) & 32'h0000_3FFF;
                    12'h05C: r_lut_op[w_lut_index]    <= f_apply_pstrb(r_lut_op[w_lut_index], pwdata, pstrb) & 32'h0000_FFFF;
                    12'h060: r_lut_dummy[w_lut_index] <= f_apply_pstrb(r_lut_dummy[w_lut_index], pwdata, pstrb) & 32'h0000_00FF;

                    12'h010: begin // INT_STAT RW1C
                        if (pstrb[0] && (|pwdata[4:0])) begin
                            r_cmd_done_stat      <= 1'b0;
                            r_dma_done_stat      <= 1'b0;
                            r_err_stat_latch     <= 1'b0;
                            r_fifo_tx_empty_stat <= 1'b0;
                            r_fifo_rx_full_stat  <= 1'b0;
                        end
                    end

                    // Write-only TX FIFO
                    12'h044: begin
                        if (!i_tx_full) begin
                            r_fifo_tx <= f_apply_pstrb({DATA_WIDTH{1'b0}}, pwdata, pstrb);
                            r_tx_wen  <= 1'b1;
                        end
                    end
                endcase
            end
            // Handle APB reads
            else if ((r_cur_state == S_ACCESS) && !pwrite && penable && psel) begin
                case (paddr)
                    12'h004: prdata <= r_ctrl;
                    12'h00C: prdata <= r_int_en;
                    12'h014: prdata <= r_clk_div;
                    12'h018: prdata <= r_cs_ctrl;
                    12'h01C: prdata <= r_xip_cfg;
                    12'h020: prdata <= r_xip_cmd;
                    12'h024: prdata <= r_cmd_cfg;
                    12'h028: prdata <= r_cmd_op;
                    12'h02C: prdata <= r_cmd_addr;
                    12'h030: prdata <= r_cmd_len;
                    12'h034: prdata <= r_cmd_dummy;
                    12'h038: prdata <= r_dma_cfg;
                    12'h03C: prdata <= r_dma_addr;
                    12'h040: prdata <= r_dma_len;

                    // Command LUT indirect programming interface
                    12'h054: prdata <= r_lut_ctrl;
                    12'h058: prdata <= r_lut_cfg[w_lut_index];
                    12'h05C: prdata <= r_lut_op[w_lut_index];
                    12'h060: prdata <= r_lut_dummy[w_lut_index];

                    // INT_STAT RW1C
                    12'h010: prdata <= {27'b0, r_fifo_rx_full_stat, r_fifo_tx_empty_stat, r_err_stat_latch, r_dma_done_stat, r_cmd_done_stat};

                    // Read-Only
                    12'h000: prdata <= C_IP_ID;
                    12'h008: prdata <= w_status;
                    12'h048: prdata <= i_fifo_rx_data;

                    12'h04C: prdata <= w_fifo_stat;
                    12'h050: prdata <= w_err_stat;

                    default: prdata <= {DATA_WIDTH{1'b0}};
                endcase
            end

            // CMD_TRIGGER pulse generation
            if (r_cmd_trigger_reg && !r_cmd_trigger_pulse) begin
                r_cmd_trigger_pulse <= 1'b1;
            end

            // Clear trigger
            if (i_clear) begin
                r_cmd_trigger_reg <= 1'b0;
                r_ctrl[8]         <= 1'b0;
            end
            if (i_cmd_done)
                r_ctrl[9] <= 1'b0;

            // Latch interrupt status bits
            if (i_cmd_done) r_cmd_done_stat <= 1'b1;
            if (i_dma_done) r_dma_done_stat <= 1'b1;
            if (i_timeout | i_overrun | i_underrun | i_dma_error) r_err_stat_latch <= 1'b1;
            if (i_tx_empty && !r_tx_empty_d) r_fifo_tx_empty_stat <= 1'b1;
            if (i_rx_full  && !r_rx_full_d)  r_fifo_rx_full_stat  <= 1'b1;
            r_tx_empty_d <= i_tx_empty;
            r_rx_full_d  <= i_rx_full;

        end
    end

    // FIFO RX read control
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_rx_ren <= 1'b0;
        end else begin
            if ((paddr == 12'h048) && !penable && psel && !i_rx_empty)
                r_rx_ren <= 1'b1;
            else
                r_rx_ren <= 1'b0;
        end
    end

    // APB protocol signals
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            pready  <= 1'b0;
            pslverr <= 1'b0;
        end else begin
            pready  <= (r_cur_state == S_ACCESS);
            pslverr <= (r_cur_state == S_ACCESS) && ((paddr % 4 != 0) || (paddr > 12'h060));
        end
    end

    // Assign INT_STAT outputs
    assign o_cmd_done      = r_cmd_done_stat;
    assign o_dma_done      = r_dma_done_stat;
    assign o_err           = r_err_stat_latch;
    assign o_fifo_tx_empty = r_fifo_tx_empty_stat;
    assign o_fifo_rx_full  = r_fifo_rx_full_stat;

    // Assign CTRL outputs
    assign o_ctrl_enable  = r_ctrl[0];
    assign o_ctrl_xip_en  = r_ctrl[1];
    assign o_ctrl_quad_en = r_ctrl[2];
    assign o_ctrl_cpol    = r_ctrl[3];
    assign o_ctrl_cpha    = r_ctrl[4];
    assign o_ctrl_dma_en  = r_ctrl[9];

    // CLK_DIV
    assign o_clk_div = r_clk_div[2:0];

    // CS_CTRL
    assign o_cs_auto  = r_cs_ctrl[0];
    assign o_cs_level = r_cs_ctrl[1];
    assign o_cs_delay = r_cs_ctrl[3:2];

    // XIP_CFG
    assign o_xip_lanes        = r_xip_cfg[1:0];
    assign o_xip_addr_lanes   = r_xip_cfg[3:2];
    assign o_xip_data_lanes   = r_xip_cfg[5:4];
    assign o_xip_addr_bytes   = r_xip_cfg[7:6];
    assign o_xip_mode_en      = r_xip_cfg[8];
    assign o_xip_dummy_cycles = r_xip_cfg[12:9];

    // XIP_CMD
    assign o_xip_read_op   = r_xip_cmd[7:0];
    assign o_xip_mode_bits = r_xip_cmd[23:16];

    // CMD_CFG
    // In LUT mode, the selected LUT entry is snapshotted into these command
    // registers when CMD_TRIGGER is accepted. In direct mode, software writes
    // the same registers normally. This provides one common command-engine path.
    assign o_cmd_lanes    = r_cmd_cfg[1:0];
    assign o_addr_lanes   = r_cmd_cfg[3:2];
    assign o_data_lanes   = r_cmd_cfg[5:4];
    assign o_addr_bytes   = r_cmd_cfg[7:6];
    assign o_mode_en      = r_cmd_cfg[8];
    assign o_dummy_cycles = r_cmd_cfg[12:9];
    assign o_dir          = r_cmd_cfg[13];

    // CMD_OP
    assign o_opcode    = r_cmd_op[7:0];
    assign o_mode_bits = r_cmd_op[15:8];

    // CMD_ADDR, CMD_LEN, CMD_DUMMY
    assign o_cmd_addr    = r_cmd_addr;
    assign o_cmd_len     = r_cmd_len;
    assign o_extra_dummy = r_cmd_dummy[7:0];

    // DMA_CFG, DMA_ADDR, DMA_LEN
    assign o_dma_dir   = r_dma_cfg[4];
    assign o_incr_addr = r_dma_cfg[5];
    assign o_dma_addr  = r_dma_addr;
    assign o_dma_len   = r_dma_len;

    // INT_EN
    assign o_cmd_done_en      = r_int_en[0];
    assign o_dma_done_en      = r_int_en[1];
    assign o_err_en           = r_int_en[2];
    assign o_fifo_tx_empty_en = r_int_en[3];
    assign o_fifo_rx_full_en  = r_int_en[4];

    // IRQ generation: OR of (INT_EN & INT_STAT)
    assign o_irq = (o_cmd_done_en      & r_cmd_done_stat)      |
                   (o_dma_done_en      & r_dma_done_stat)      |
                   (o_err_en           & r_err_stat_latch)     |
                   (o_fifo_tx_empty_en & r_fifo_tx_empty_stat) |
                   (o_fifo_rx_full_en  & r_fifo_rx_full_stat);

endmodule

`default_nettype wire
