////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : QSPI Controller
//  File Name        : qspi_controller.v
//  Description      : Implements QSPI clocking, command/address/mode/dummy/data phases, FIFO transfer, and error status.
//  Authors          : Truong Quoc Bao, Thai Hai Dang, Nguyen Bao Tinh
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module qspi_controller (
    // ---------- Clock and Reset ----------
    input  wire        i_clk,
    input  wire        i_rst_n,

    // ---------- Trigger & Status ----------
    input  wire        i_qspi_start,
    output wire        o_qspi_done,

    // ---------- CTRL Configuration ----------
    input  wire        i_enable,
    input  wire        i_quad_en,
    input  wire        i_cpol,
    input  wire        i_cpha,

    // ---------- CLK_DIV Configuration ----------
    input  wire [2:0]  i_clk_div,

    // ---------- CS_CTRL Configuration ----------
    input  wire        i_cs_auto,
    input  wire        i_cs_level,
    input  wire [1:0]  i_cs_delay,

    // ---------- CMD_CFG Configuration ----------
    input  wire [1:0]  i_cmd_lanes,
    input  wire [1:0]  i_addr_lanes,
    input  wire [1:0]  i_data_lanes,
    input  wire [1:0]  i_addr_bytes,
    input  wire        i_mode_en,
    input  wire [3:0]  i_dummy_cycles,
    input  wire        i_dir,           // 0: TX (master -> flash), 1: RX (flash -> master)

    // ---------- CMD_OP Configuration ----------
    input  wire [7:0]  i_opcode,
    input  wire [7:0]  i_mode_bits,

    // ---------- CMD_ADDR Configuration ----------
    input  wire [31:0] i_cmd_addr,

    // ---------- CMD_DUMMY Configuration ----------
    input  wire [7:0]  i_extra_dummy,

    // ---------- CMD_LEN Configuration ----------
    input  wire [31:0] i_cmd_len,

    // ---------- TX FIFO Signals ----------
    output reg         o_tx_ren,         // read enable to TX FIFO (pulse)
    input  wire [31:0] i_tx_data_fifo,   // data bus from TX FIFO
    input  wire        i_tx_empty,

    // ---------- RX FIFO Signals ----------
    input  wire        i_rx_full,
    output reg  [31:0] o_rx_data_fifo,
    output reg         o_rx_wen,

    // ---------- Error Status Outputs ----------
    output wire        o_timeout,
    output wire        o_overrun,
    output wire        o_underrun,

    // ---------- Physical QSPI Interface ----------
    output wire        o_sclk,
    output reg         o_cs_n,
    inout  wire        io_qspi_io0,
    inout  wire        io_qspi_io1,
    inout  wire        io_qspi_io2,
    inout  wire        io_qspi_io3
);

    // ---------- Error flags ----------
    reg underrun_reg;
    reg overrun_reg;
    reg timeout_reg;

    assign o_timeout  = timeout_reg;
    assign o_overrun  = overrun_reg;
    assign o_underrun = underrun_reg;

    // Timeout counter (sclk domain)
    reg [23:0] timeout_cnt;
    localparam TIMEOUT_LIMIT = 24'd2000;

    // -----------------------
    // SCLK generation
    // -----------------------
    reg  [7:0] sclk_r;
    reg  [7:0] sclk_n;
    reg        sclk_div;
    reg        shift_div;
    reg        sclk_flag;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            sclk_flag <= 1'b0;
        else
            sclk_flag <= 1'b1;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sclk_r    <= 8'd0;
            sclk_n    <= 8'd0;
            sclk_div  <= 1'b0;
            shift_div <= 1'b0;
        end else if ((i_clk_div != 0) && sclk_flag) begin
            sclk_r <= sclk_n;
            if (sclk_r < ((1 << i_clk_div) >> 1))
                sclk_div <= i_cpol;
            else
                sclk_div <= ~i_cpol;

            if (!i_cpha) begin
                if (sclk_r < ((1 << i_clk_div) >> 1))
                    shift_div <= 1'b1;
                else
                    shift_div <= 1'b0;
            end else begin
                if (sclk_r < ((1 << i_clk_div) >> 1))
                    shift_div <= 1'b0;
                else
                    shift_div <= 1'b1;
            end
        end
    end

    always @* begin
        if (sclk_flag) begin
            sclk_n = sclk_r;
            if (sclk_r == ((1 << i_clk_div) - 1))
                sclk_n = 8'd0;
            else
                sclk_n = sclk_r + 8'd1;
        end else begin
            sclk_n = sclk_r;
        end
    end

    wire sclk_cpol = (!i_rst_n) ? 1'b0 :
                     (!i_clk_div && i_cpol)                 ? i_clk  :
                     (!i_clk_div && !i_cpol && !sclk_flag)  ? 1'b0   :
                     (!i_clk_div && !i_cpol && sclk_flag)   ? ~i_clk :
                                                              sclk_div;

    assign o_sclk = (!i_rst_n) ? 1'b0 :
                    (!i_clk_div && !i_cpha && i_cpol)                 ? sclk_cpol  :
                    (!i_clk_div && !i_cpha && !i_cpol && !sclk_flag)  ? 1'b0       :
                    (!i_clk_div && !i_cpha && !i_cpol && sclk_flag)   ? ~sclk_cpol :
                    (!i_clk_div &&  i_cpha && !i_cpol)                ? sclk_cpol  :
                    (!i_clk_div &&  i_cpha &&  i_cpol && !sclk_flag)  ? 1'b0       :
                    (!i_clk_div &&  i_cpha &&  i_cpol && sclk_flag)   ? ~sclk_cpol :
                                                                        shift_div;

    // =========================
    // FSM states
    // =========================
    localparam
        IDLE    = 3'b000,
        CS      = 3'b001,
        CMD     = 3'b010,
        ADDR    = 3'b011,
        MODE    = 3'b100,
        DUMMY   = 3'b101,
        DATA    = 3'b110,
        STOP_CS = 3'b111;

    reg [2:0] cur_state, next_state;
    reg       idle_done, cs_done, cmd_done, addr_done, mode_done, dummy_done, data_done, stop_done;

    // Next-state combinational
    always @(*) begin
        next_state = cur_state;
        case (cur_state)
            IDLE:    if (idle_done) next_state = CS;
            CS:      if (cs_done)   next_state = CMD;
            CMD:     if (cmd_done) begin
                         if (i_addr_bytes != 2'b00) next_state = ADDR;
                         else if (i_cmd_len != 0)   next_state = DATA;
                         else                       next_state = STOP_CS;
                     end
            ADDR:    if (addr_done) begin
                         if (i_mode_en)                 next_state = MODE;
                         else if ((i_dummy_cycles + i_extra_dummy) != 0) next_state = DUMMY;
                         else if (i_cmd_len != 0)       next_state = DATA;
                         else                           next_state = STOP_CS;
                     end
            MODE:    if (mode_done)  next_state = DUMMY;
            DUMMY:   if (dummy_done) next_state = DATA;
            DATA:    if (data_done)  next_state = STOP_CS;
            STOP_CS: if (stop_done)  next_state = IDLE;
        endcase
    end

    // =========================
    // Registers used in shifts & FIFOs
    // =========================
    reg [7:0]  opcode_shift;
    reg [31:0] addr_shift;
    reg [7:0]  mode_shift;
    reg        tx_ren_start;
    wire [31:0] shift_o_tmp = i_tx_data_fifo;
    reg [31:0] shift_o;
    reg [31:0] shift_i;
    reg        data_ready;
    reg [1:0]  check_data_word_w;
    reg [3:0]  check_data_byte_w;
    reg [1:0]  check_data_word_r;
    reg [3:0]  check_data_byte_r;
    reg        allow_tx_ren;
    reg        allow_tx_ren_flag;
    reg [2:0]  opcode_cnt;
    reg [5:0]  addr_cnt;
    reg [2:0]  mode_cnt;
    reg [7:0]  dummy_cnt;
    reg [1:0]  cs_delay_cnt;

    // IO outputs - unified
    reg [3:0] io_out;   // bits [3]=io3 ... [0]=io0
    reg [3:0] io_oe;    // 1 = drive, 0 = tri-state (input)
    wire [3:0] io_in = {io_qspi_io3, io_qspi_io2, io_qspi_io1, io_qspi_io0};

    // =========================
    // FSM register + setup from i_qspi_start
    // =========================
    reg wait_idle;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cur_state         <= IDLE;
            cs_delay_cnt      <= 2'd0;
            o_cs_n            <= 1'b1;
            opcode_shift      <= 8'd0;
            addr_shift        <= 32'd0;
            mode_shift        <= 8'd0;
            idle_done         <= 1'b0;
            tx_ren_start      <= 1'b0;
            wait_idle         <= 1'b0;
        end else begin
            cur_state <= next_state;
            if (next_state == STOP_CS)
                underrun_reg <= 1'b0;
            if (next_state == IDLE && i_qspi_start && i_enable)
                wait_idle <= 1'b1;

            if (next_state != IDLE)
                wait_idle <= 1'b0;
        end
    end

    // =========================
    // TX FIFO read request (o_tx_ren) logic - on i_clk domain
    // =========================
    reg tx_ren_flag;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_tx_ren     <= 1'b0;
            tx_ren_flag  <= 1'b0;
            data_ready   <= 1'b0;
            underrun_reg <= 1'b0;
        end else begin
            if (!data_done) begin
                if (tx_ren_start && !i_tx_empty && !o_tx_ren && !tx_ren_flag) begin
                    // pulse o_tx_ren for one clk cycle to request FIFO word
                    o_tx_ren     <= 1'b1;
                    tx_ren_flag  <= 1'b1;
                    underrun_reg <= 1'b0;
                end else if (o_tx_ren) begin
                    // deassert and capture next cycle
                    o_tx_ren   <= 1'b0;
                    data_ready <= 1'b1;
                end else if (tx_ren_start && !o_tx_ren && !tx_ren_flag && i_tx_empty && (next_state == DATA)) begin
                    underrun_reg <= 1'b1; // no data to pull when requested -> underrun
                end
            end

            // when allowed to consume next word
            if (allow_tx_ren) begin
                tx_ren_flag <= 1'b0;
                data_ready  <= 1'b0; // consumed
            end
        end
    end

    reg [31:0] data_cnt;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            allow_tx_ren      <= 1'b0;
            allow_tx_ren_flag <= 1'b0;
        end else begin
            if ((next_state == DATA) && (check_data_word_w == 2'b01) && !allow_tx_ren_flag && data_ready) begin
                allow_tx_ren      <= 1'b1;
                allow_tx_ren_flag <= 1'b1;
            end else begin
                allow_tx_ren <= 1'b0;
            end

            if ((next_state == DATA) && (check_data_word_w == 2'b10) && allow_tx_ren_flag)
                allow_tx_ren_flag <= 1'b0;
        end
    end

    reg [1:0] read_latency_sel;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            read_latency_sel <= 2'b01;
        end else begin
            if (cur_state == IDLE && wait_idle) begin
                case (i_opcode)
                    8'h03, 8'hEB, 8'h9F, 8'h05: read_latency_sel <= 2'b10; // Read Data (normal)
                    default: read_latency_sel <= 2'b01; // Fast Read, Dual, Quad, v.v.
                endcase
            end
        end
    end

    // Address bits length and packed address
    wire [5:0] total_bits = (i_addr_bytes == 2'b01) ? 6'd24 :
                            (i_addr_bytes == 2'b10) ? 6'd32 : 6'd0;

    wire [31:0] addr_packed = (i_addr_bytes == 2'b01) ? {i_cmd_addr[23:0], 8'd0} :
                              (i_addr_bytes == 2'b10) ?  i_cmd_addr : 32'd0;

    wire [1:0] effective_cmd_lanes  = (i_quad_en) ? i_cmd_lanes  :
                                      (i_cmd_lanes  == 2'b10) ? 2'b00 : i_cmd_lanes;

    wire [1:0] effective_addr_lanes = (i_quad_en) ? i_addr_lanes :
                                      (i_addr_lanes == 2'b10) ? 2'b00 : i_addr_lanes;

    wire [1:0] effective_data_lanes = (i_quad_en) ? i_data_lanes :
                                      (i_data_lanes == 2'b10) ? 2'b00 : i_data_lanes;

    // =========================
    // SHIFT logic: operate on o_sclk domain
    // CMD -> ADDR -> MODE -> DUMMY -> DATA -> STOP_CS
    // =========================
    reg [1:0] start_read;
    reg       start_write;
    always @(posedge o_sclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            shift_o           <= 32'd0;
            shift_i           <= 32'd0;
            cs_done           <= 1'b0;
            cmd_done          <= 1'b0;
            opcode_cnt        <= 3'd0;
            addr_done         <= 1'b1;
            addr_cnt          <= 6'd0;
            mode_done         <= 1'b1;
            mode_cnt          <= 3'd0;
            dummy_done        <= 1'b0;
            dummy_cnt         <= 8'd0;
            data_done         <= 1'b1;
            data_cnt          <= 32'd0;
            check_data_byte_w <= 4'd0;
            check_data_word_w <= 2'b00;
            check_data_byte_r <= 4'd0;
            check_data_word_r <= 2'b00;
            stop_done         <= 1'b1;
            cs_delay_cnt      <= 2'b00;
            io_out            <= 4'b0000;
            io_oe             <= 4'b0000;
            o_rx_wen          <= 1'b0;
            o_rx_data_fifo    <= 32'd0;
            start_read        <= 2'b0;
            start_write       <= 1'b0;
            // clear error flags
            overrun_reg       <= 1'b0;
            timeout_reg       <= 1'b0;
            timeout_cnt       <= 1'b0;
        end else begin
            // Default assume inputs (tri-state) unless explicitly driving
            io_oe <= 4'b0000;

            case (next_state)
                IDLE: begin
                    stop_done <= 1'b0;
                    if (wait_idle) begin
                        addr_shift   <= addr_packed;
                        mode_shift   <= i_mode_bits;
                        opcode_shift <= i_opcode;
                        timeout_reg  <= 1'b0;
                        tx_ren_start <= 1'b0;

                        if ((i_opcode == 8'h02) || (i_opcode == 8'h32)) begin
                            tx_ren_start <= 1'b1;
                            idle_done    <= 1'b1;
                        end else begin
                            idle_done    <= 1'b1;
                        end
                    end
                end
                CS: begin
                    idle_done <= 1'b0;
                    stop_done <= 1'b0;
                    cs_done   <= 1'b1;
                    if (i_cs_auto)
                        o_cs_n <= 1'b0;
                    else
                        o_cs_n <= i_cs_level;

                    // minimal drive for first opcode bit if needed
                    io_oe        <= 4'b0001;
                    io_out[0]    <= opcode_shift[7];
                    opcode_shift <= {opcode_shift[6:0], 1'b0};
                    opcode_cnt   <= opcode_cnt + 1;
                end
                CMD: begin
                    cs_done <= 1'b0;
                    if (check_data_word_w == 2'b00 && data_ready) begin
                        shift_o     <= shift_o_tmp;
                        start_write <= 1'b1;
                    end

                    case (effective_cmd_lanes)
                        2'b00: begin
                            io_oe        <= 4'b0001;
                            io_out[0]    <= opcode_shift[7];
                            opcode_shift <= {opcode_shift[6:0], 1'b0};
                            if (opcode_cnt >= 3'd7) begin
                                cmd_done   <= 1'b1;
                                opcode_cnt <= 3'd0;
                            end else begin
                                opcode_cnt <= opcode_cnt + 1;
                            end
                        end
                        2'b01: begin
                            io_oe        <= 4'b0011;
                            io_out[1]    <= opcode_shift[7];
                            io_out[0]    <= opcode_shift[6];
                            opcode_shift <= {opcode_shift[5:0], 2'b00};
                            if (opcode_cnt >= 3'd6) begin
                                cmd_done   <= 1'b1;
                                opcode_cnt <= 3'd0;
                            end else begin
                                opcode_cnt <= opcode_cnt + 2;
                            end
                        end
                        2'b10: begin
                            io_oe        <= 4'b1111;
                            io_out[3]    <= opcode_shift[7];
                            io_out[2]    <= opcode_shift[6];
                            io_out[1]    <= opcode_shift[5];
                            io_out[0]    <= opcode_shift[4];
                            opcode_shift <= {opcode_shift[3:0], 4'b0000};
                            if (opcode_cnt >= 3'd4) begin
                                cmd_done   <= 1'b1;
                                opcode_cnt <= 3'd0;
                            end else begin
                                opcode_cnt <= opcode_cnt + 4;
                            end
                        end
                        default: begin
                            cmd_done <= 1'b1;
                        end
                    endcase
                end

                ADDR: begin
                    cmd_done <= 1'b0;
                    case (effective_addr_lanes)
                        2'b00: begin
                            io_oe      <= 4'b0001;
                            io_out[0]  <= addr_shift[31];
                            addr_shift <= {addr_shift[30:0], 1'b0};
                            if (addr_cnt >= (total_bits - 1)) begin
                                addr_done <= 1'b1;
                                addr_cnt  <= 6'd0;
                            end else begin
                                addr_cnt  <= addr_cnt + 1;
                            end
                        end
                        2'b01: begin
                            io_oe      <= 4'b0011;
                            io_out[1]  <= addr_shift[31];
                            io_out[0]  <= addr_shift[30];
                            addr_shift <= {addr_shift[29:0], 2'b00};
                            if (addr_cnt >= (total_bits - 2)) begin
                                addr_done <= 1'b1;
                                addr_cnt  <= 6'd0;
                            end else begin
                                addr_cnt  <= addr_cnt + 2;
                            end
                        end
                        2'b10: begin
                            io_oe      <= 4'b1111;
                            io_out[3]  <= addr_shift[31];
                            io_out[2]  <= addr_shift[30];
                            io_out[1]  <= addr_shift[29];
                            io_out[0]  <= addr_shift[28];
                            addr_shift <= {addr_shift[27:0], 4'b0000};
                            if (addr_cnt >= (total_bits - 4)) begin
                                addr_done <= 1'b1;
                                addr_cnt  <= 6'd0;
                            end else begin
                                addr_cnt  <= addr_cnt + 4;
                            end
                        end
                        default: addr_done <= 1'b1;
                    endcase
                end

                MODE: begin
                    addr_done <= 1'b0;
                    case (effective_addr_lanes)
                        2'b00: begin
                            io_oe      <= 4'b0001;
                            io_out[0]  <= mode_shift[7];
                            mode_shift <= {mode_shift[6:0], 1'b0};
                            if (mode_cnt >= 3'd7) begin
                                mode_done <= 1'b1;
                                mode_cnt  <= 3'd0;
                            end else begin
                                mode_cnt  <= mode_cnt + 1;
                            end
                        end
                        2'b01: begin
                            io_oe      <= 4'b0011;
                            io_out[1]  <= mode_shift[7];
                            io_out[0]  <= mode_shift[6];
                            mode_shift <= {mode_shift[5:0], 2'b00};
                            if (mode_cnt >= 3'd6) begin
                                mode_done <= 1'b1;
                                mode_cnt  <= 3'd0;
                            end else begin
                                mode_cnt  <= mode_cnt + 2;
                            end
                        end
                        2'b10: begin
                            io_oe      <= 4'b1111;
                            io_out[3]  <= mode_shift[7];
                            io_out[2]  <= mode_shift[6];
                            io_out[1]  <= mode_shift[5];
                            io_out[0]  <= mode_shift[4];
                            mode_shift <= {mode_shift[3:0], 4'b0000};
                            if (mode_cnt >= 3'd4) begin
                                mode_done <= 1'b1;
                                mode_cnt  <= 3'd0;
                            end else begin
                                mode_cnt  <= mode_cnt + 4;
                            end
                        end
                        default: mode_done <= 1'b1;
                    endcase
                end

                DUMMY: begin
                    mode_done <= 1'b0;
                    addr_done <= 1'b0;
                    if ((i_dummy_cycles + i_extra_dummy) == 0) begin
                        dummy_done <= 1'b1;
                    end else begin
                        if (dummy_cnt < (i_dummy_cycles + i_extra_dummy)) begin
                            dummy_cnt <= dummy_cnt + 1;
                        end else begin
                            dummy_done <= 1'b1;
                            dummy_cnt  <= 8'd0;
                        end
                    end
                end

                DATA: begin
                    dummy_done <= 1'b0;
                    cmd_done   <= 1'b0;
                    addr_done  <= 1'b0;
                    if (i_cmd_len != 0) begin
                        if (i_dir == 1'b0) begin
                            // TX (master -> flash)
                            if (start_write) begin
                                case (effective_data_lanes)
                                    2'b00: begin
                                        io_oe     <= 4'b0001;
                                        io_out[0] <= shift_o[31];
                                        shift_o   <= {shift_o[30:0], 1'b0};
                                        if (check_data_byte_w >= 3'd7) begin
                                            check_data_byte_w <= 3'd0;
                                            if (data_cnt == (i_cmd_len - 1)) begin
                                                data_done <= 1'b1;
                                                o_tx_ren  <= 1'b1;
                                            end else begin
                                                data_cnt  <= data_cnt + 1;
                                            end
                                            if (check_data_word_w == 2'b11) begin
                                                check_data_word_w <= 2'b00;
                                                if (!data_ready)
                                                    start_write <= 0;
                                                else
                                                    shift_o <= shift_o_tmp;
                                            end else begin
                                                check_data_word_w <= check_data_word_w + 1;
                                            end
                                        end else begin
                                            check_data_byte_w <= check_data_byte_w + 1;
                                        end
                                    end
                                    2'b01: begin
                                        io_oe       <= 4'b0011;
                                        io_out[1:0] <= shift_o[31:30];
                                        shift_o     <= {shift_o[29:0], 2'b00};
                                        if (check_data_byte_w >= 3'd6) begin
                                            check_data_byte_w <= 3'd0;
                                            if (data_cnt == (i_cmd_len - 1)) begin
                                                data_done <= 1'b1;
                                                o_tx_ren  <= 1'b1;
                                            end else begin
                                                data_cnt  <= data_cnt + 1;
                                            end
                                            if (check_data_word_w == 2'b11) begin
                                                check_data_word_w <= 2'b00;
                                                shift_o <= shift_o_tmp;
                                            end else begin
                                                check_data_word_w <= check_data_word_w + 1;
                                            end
                                        end else begin
                                            check_data_byte_w <= check_data_byte_w + 2;
                                        end
                                    end
                                    2'b10: begin
                                        io_oe       <= 4'b1111;
                                        io_out[3:0] <= shift_o[31:28];
                                        shift_o     <= {shift_o[27:0], 4'b0000};
                                        if (check_data_byte_w >= 3'd4) begin
                                            check_data_byte_w <= 3'd0;
                                            if (data_cnt == (i_cmd_len - 1)) begin
                                                data_done <= 1'b1;
                                                o_tx_ren  <= 1'b1;
                                            end else begin
                                                data_cnt  <= data_cnt + 1;
                                            end
                                            if (check_data_word_w == 2'b11) begin
                                                check_data_word_w <= 2'b00;
                                                shift_o <= shift_o_tmp;
                                            end else begin
                                                check_data_word_w <= check_data_word_w + 1;
                                            end
                                        end else begin
                                            check_data_byte_w <= check_data_byte_w + 4;
                                        end
                                    end
                                    default: data_done <= 1'b1;
                                endcase
                            end else if (!check_data_word_w && data_ready) begin
                                start_write <= 1'b1;
                            end
                        end else begin
                            if (start_read == read_latency_sel) begin
                                if (!i_rx_full) begin
                                    overrun_reg <= 1'b0;
                                    case (i_data_lanes)
                                        2'b00: begin // single-lane: device drives io_in[1]
                                            io_oe   <= (data_cnt == 0) ? 4'b0001 : 4'b0000;
                                            shift_i <= {shift_i[30:0], io_in[1]};
                                            if (check_data_byte_r >= 3'd7) begin
                                                check_data_byte_r <= 3'd0;
                                                if (data_cnt == (i_cmd_len - 1))
                                                    data_done <= 1'b1;
                                                else
                                                    data_cnt <= data_cnt + 1;
                                                if (check_data_word_r == 2'b11) begin
                                                    check_data_word_r <= 2'b00;
                                                    if (!i_rx_full) begin
                                                        o_rx_data_fifo <= {shift_i[30:0], io_in[1]};
                                                        o_rx_wen       <= 1'b1;
                                                    end
                                                end else begin
                                                    check_data_word_r <= check_data_word_r + 1;
                                                end
                                            end else begin
                                                check_data_byte_r <= check_data_byte_r + 1;
                                                o_rx_wen          <= 1'b0;
                                            end
                                        end

                                        2'b01: begin // dual-lane: sample io1, io0
                                            io_oe   <= 4'b0000;
                                            shift_i <= {shift_i[29:0], io_in[1], io_in[0]};
                                            if (check_data_byte_r >= 3'd6) begin
                                                check_data_byte_r <= 3'd0;
                                                if (data_cnt == (i_cmd_len - 1))
                                                    data_done <= 1'b1;
                                                else
                                                    data_cnt <= data_cnt + 1;
                                                if (check_data_word_r == 2'b11) begin
                                                    check_data_word_r <= 2'b00;
                                                    if (!i_rx_full) begin
                                                        o_rx_data_fifo <= {shift_i[29:0], io_in[1], io_in[0]};
                                                        o_rx_wen       <= 1'b1;
                                                    end
                                                end else begin
                                                    check_data_word_r <= check_data_word_r + 1;
                                                end
                                            end else begin
                                                check_data_byte_r <= check_data_byte_r + 2;
                                                o_rx_wen          <= 1'b0;
                                            end
                                        end

                                        2'b10: begin // quad-lane
                                            io_oe   <= 4'b0000;
                                            shift_i <= {shift_i[27:0], io_in[3], io_in[2], io_in[1], io_in[0]};
                                            if (check_data_byte_r >= 3'd4) begin
                                                check_data_byte_r <= 3'd0;
                                                if (data_cnt == (i_cmd_len - 1))
                                                    data_done <= 1'b1;
                                                else
                                                    data_cnt <= data_cnt + 1;
                                                if (check_data_word_r == 2'b11) begin
                                                    check_data_word_r <= 2'b00;
                                                    if (!i_rx_full) begin
                                                        o_rx_data_fifo <= {shift_i[27:0], io_in[3], io_in[2], io_in[1], io_in[0]};
                                                        o_rx_wen       <= 1'b1;
                                                    end
                                                end else begin
                                                    check_data_word_r <= check_data_word_r + 1;
                                                end
                                            end else begin
                                                check_data_byte_r <= check_data_byte_r + 4;
                                                o_rx_wen          <= 1'b0;
                                            end
                                        end

                                        default: data_done <= 1'b1;
                                    endcase

                                    if ((data_cnt == (i_cmd_len - 1)) && (check_data_byte_r >= 3'd7) && (i_data_lanes == 2'b00)) begin
                                        case (i_cmd_len % 4)
                                            1: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {24'h0, {shift_i[6:0], io_in[1]}};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            2: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {16'h0, shift_i[14:0], io_in[1]};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            3: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {8'h0, shift_i[22:0], io_in[1]};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            default: ;
                                        endcase
                                    end

                                    if ((data_cnt == (i_cmd_len - 1)) && (check_data_byte_r >= 3'd6) && (i_data_lanes == 2'b01)) begin
                                        case (i_cmd_len % 4)
                                            1: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {24'h0, {shift_i[5:0], io_in[1], io_in[0]}};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            2: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {16'h0, shift_i[13:0], io_in[1], io_in[0]};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            3: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {8'h0, shift_i[21:0], io_in[1], io_in[0]};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            default: ;
                                        endcase
                                    end

                                    if ((data_cnt == (i_cmd_len - 1)) && (check_data_byte_r >= 3'd4) && (i_data_lanes == 2'b10)) begin
                                        case (i_cmd_len % 4)
                                            1: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {24'h0, {shift_i[3:0], io_in[3], io_in[2], io_in[1], io_in[0]}};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            2: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {16'h0, shift_i[11:0], io_in[3], io_in[2], io_in[1], io_in[0]};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            3: begin
                                                if (!i_rx_full) begin
                                                    o_rx_data_fifo    <= {8'h0, shift_i[19:0], io_in[3], io_in[2], io_in[1], io_in[0]};
                                                    o_rx_wen          <= 1'b1;
                                                    check_data_word_r <= 2'b00;
                                                end
                                            end
                                            default: ;
                                        endcase
                                    end
                                end else
                                    overrun_reg <= 1'b1;
                            end else
                                start_read <= start_read + 1;
                        end
                    end else begin
                        data_done <= 1'b1;
                    end
                end

                STOP_CS: begin
                    o_tx_ren          <= 1'b0;
                    o_rx_wen          <= 1'b0;
                    start_read        <= 2'b00;
                    data_done         <= 1'b0;
                    cmd_done          <= 1'b0;
                    addr_done         <= 1'b0;
                    mode_done         <= 1'b0;
                    dummy_done        <= 1'b0;
                    check_data_byte_r <= 4'd0;
                    check_data_byte_w <= 4'd0;
                    data_cnt          <= 32'd0;
                    io_oe             <= 4'b0000;
                    if (cs_delay_cnt < i_cs_delay) begin
                        cs_delay_cnt <= cs_delay_cnt + 1;
                    end else begin
                        cs_delay_cnt <= 2'd0;
                        stop_done    <= 1'b1;
                        o_cs_n       <= 1'b1;
                    end
                end

                default: begin end
            endcase

            if (underrun_reg || overrun_reg) begin
                timeout_cnt <= timeout_cnt + 1;
            end else begin
                timeout_cnt <= 0;
            end

            if ((timeout_cnt == TIMEOUT_LIMIT) && (next_state == DATA)) begin
                underrun_reg <= 1'b0;
                overrun_reg  <= 1'b0;
                timeout_cnt  <= 1'b0;
                timeout_reg  <= 1'b1;
                data_done    <= 1'b1;
            end
        end
    end

    // qspi_done: high when stop_done asserted (sclk domain)
    assign o_qspi_done = stop_done;
    wire   qspi_done   = o_qspi_done; // Backward compatibility for testbench hierarchical probe

    // IO tri-state outputs: use io_oe/io_out
    assign io_qspi_io0 = io_oe[0] ? io_out[0] : 1'bz;
    assign io_qspi_io1 = io_oe[1] ? io_out[1] : 1'bz;
    assign io_qspi_io2 = io_oe[2] ? io_out[2] : 1'bz;
    assign io_qspi_io3 = io_oe[3] ? io_out[3] : 1'bz;

endmodule

`default_nettype wire
