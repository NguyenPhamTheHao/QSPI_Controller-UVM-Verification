////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Company          : VNCHIP
//  Copyright        : Copyright (c) 2026 VNCHIP. All rights reserved.
//  Project          : QSPI DV Training System
//  IP               : QSPI - Quad Serial Peripheral Interface
//  Module Name      : Top Module
//  File Name        : top_module.v
//  Description      : Integrates APB4 access, CSR, command engine, FIFOs, DMA, XIP, and the QSPI controller.
//  Authors          : Truong Quoc Bao, Thai Hai Dang, Nguyen Bao Tinh
//  Usage            : VNCHIP internal teaching and training only. See LICENSE.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none

module top_module (
    // ---------- Clock and Reset ----------
    input  wire        clk,
    input  wire        rst_n,

    // ---------- APB4 CSR slave interface ----------
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [11:0] paddr,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    input  wire [2:0]  pprot,
    output wire [31:0] prdata,
    output wire        pready,

    // ---------- AXI4-Lite Slave Read Address Channel (XIP) ----------
    input  wire [31:0] s_araddr,
    input  wire [2:0]  s_arprot,
    input  wire        s_arvalid,
    output wire        s_arready,

    // ---------- AXI4-Lite Slave Read Data Channel (XIP) ----------
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,

    // ---------- External QSPI interface ----------
    output wire        qspi_sclk,
    output wire        qspi_cs_n,
    inout  wire        qspi_io0,
    inout  wire        qspi_io1,
    inout  wire        qspi_io2,
    inout  wire        qspi_io3,

    // ---------- AXI4 Master Write Address Channel (DMA) ----------
    output wire [31:0] m_awaddr,
    output wire [7:0]  m_awlen,
    output wire [2:0]  m_awsize,
    output wire [1:0]  m_awburst,
    output wire        m_awvalid,
    input  wire        m_awready,

    // ---------- AXI4 Master Write Data Channel (DMA) ----------
    output wire [31:0] m_wdata,
    output wire [3:0]  m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,

    // ---------- AXI4 Master Write Response Channel (DMA) ----------
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,

    // ---------- AXI4 Master Read Address Channel (DMA) ----------
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire [2:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire        m_arvalid,
    input  wire        m_arready,

    // ---------- AXI4 Master Read Data Channel (DMA) ----------
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready,

    // ---------- Status Outputs ----------
    output wire        pslverr,
    output wire        irq
);

    // ===================================================
    // INTERNAL WIRES AND INTERCONNECTS
    // ===================================================

    // APB <-> CSR
    wire        ce_busy;

    // CE <-> QSPI_CONTROLLER
    wire        qspi_start;
    wire        qspi_done;

    // CE <-> DMA
    wire        dma_done;
    wire        dma_error;
    wire        dma_start;
    wire        rx_ren_dma;

    // TX_FIFO <-> QSPI_CONTROLLER
    wire        tx_ren;
    wire [31:0] tx_data_fifo;
    wire        tx_empty;

    // RX_FIFO <-> QSPI_CONTROLLER
    wire [31:0] rx_data_fifo;
    wire        rx_wen;
    wire        rx_full;

    // DMA <-> AXI4_RAM
    // CSR <-> CE
    wire        cmd_trigger;
    wire        clear;
    wire        cmd_done;
    wire        dma_en;

    // CSR <-> TX_FIFO
    wire        tx_wen;
    wire [31:0] tx_data_csr;
    wire        tx_full;
    wire [31:0] dma_tx_data;
    wire        dma_tx_valid;
    wire        dma_tx_ready;
    wire        tx_push = tx_wen ? tx_wen : dma_tx_valid;
    wire [31:0] tx_push_data = tx_wen ? tx_data_csr : dma_tx_data;

    // CSR <-> RX_FIFO
    wire        rx_ren_csr;
    wire [31:0] rx_data_csr;
    wire        rx_empty;

    // CSR <-> DMA CFG
    wire        dma_dir;
    wire        incr_addr;
    wire [31:0] dma_addr;
    wire [31:0] dma_len;

    // CSR <-> QSPI_MUX (control signals)
    wire        enable;
    wire        quad_en;
    wire        cpol;
    wire        cpha;
    wire [2:0]  clk_div;
    wire        cs_auto;
    wire        cs_level;
    wire [1:0]  cs_delay;
    wire [1:0]  cmd_lanes;
    wire [1:0]  addr_lanes;
    wire [1:0]  data_lanes;
    wire [1:0]  addr_bytes;
    wire        mode_en;
    wire [3:0]  dummy_cycles;
    wire        dir;
    wire [7:0]  opcode;
    wire [7:0]  mode_bits;
    wire [31:0] cmd_addr;
    wire [7:0]  extra_dummy;
    wire [31:0] cmd_len;
    wire        timeout;
    wire        overrun;
    wire        underrun;

    // CSR <-> IRQ enable
    wire        cmd_done_en;
    wire        dma_done_en;
    wire        err_en;
    wire        fifo_tx_empty_en;
    wire        fifo_rx_full_en;

    // FIFO level status
    wire [3:0]  tx_level;
    wire [3:0]  rx_level;

    // CSR <-> XIP
    wire [31:0] xip_rdata_int;
    wire [1:0]  xip_rresp_int;
    wire        xip_en;
    wire        xip_select = xip_en & enable;
    wire [1:0]  xip_lanes;
    wire [1:0]  xip_addr_lanes;
    wire [1:0]  xip_data_lanes;
    wire [1:0]  xip_addr_bytes;
    wire        xip_mode_en;
    wire [3:0]  xip_dummy_cycles;
    wire [7:0]  xip_read_op;
    wire [7:0]  xip_mode_bits;
    wire        xip_active;
    wire        xip_done;

    // XIP <-> QSPI_MUX
    wire        xip_qspi_start_o;
    wire [1:0]  xip_lanes_o;
    wire [1:0]  xip_addr_lanes_o;
    wire [1:0]  xip_data_lanes_o;
    wire [1:0]  xip_addr_bytes_o;
    wire        xip_mode_en_o;
    wire [3:0]  xip_dummy_cycles_o;
    wire [7:0]  xip_read_op_o;
    wire [7:0]  xip_mode_bits_o;
    wire        rx_ren_xip;
    wire        xip_dir_o;
    wire [31:0] xip_addr_o;
    wire [31:0] xip_len_o;

    // QSPI_MUX <-> QSPI_CONTROLLER
    wire        qspi_start_mux;
    wire [1:0]  cmd_lanes_mux;
    wire [1:0]  addr_lanes_mux;
    wire [1:0]  data_lanes_mux;
    wire [1:0]  addr_bytes_mux;
    wire [7:0]  opcode_mux;
    wire        mode_en_mux;
    wire [7:0]  mode_bits_mux;
    wire [3:0]  dummy_cycles_mux;
    wire [31:0] cmd_addr_mux;
    wire [31:0] cmd_len_mux;
    wire        dir_mux;
    wire [7:0]  extra_dummy_mux = xip_select ? 8'd0 : extra_dummy;

    assign s_rdata = xip_rdata_int;
    assign s_rresp = xip_rresp_int;

    // ===================================================
    // SUBMODULE INSTANTIATIONS
    // ===================================================

    // CSR
    csr u_csr (
        // APB slave interface
        .pclk              (clk),
        .presetn           (rst_n),
        .psel              (psel),
        .penable           (penable),
        .pwrite            (pwrite),
        .paddr             (paddr),
        .pwdata            (pwdata),
        .pstrb             (pstrb),
        .pprot             (pprot),
        .pready            (pready),
        .pslverr           (pslverr),
        .prdata            (prdata),

        // Control outputs
        .o_ctrl_enable     (enable),
        .o_ctrl_xip_en     (xip_en),
        .o_ctrl_quad_en    (quad_en),
        .o_ctrl_cpol       (cpol),
        .o_ctrl_cpha       (cpha),
        .o_ctrl_cmd_trigger(cmd_trigger),
        .o_ctrl_dma_en     (dma_en),

        // Clock divider
        .o_clk_div         (clk_div),

        // CS control
        .o_cs_auto         (cs_auto),
        .o_cs_level        (cs_level),
        .o_cs_delay        (cs_delay),

        // XIP config outputs
        .o_xip_lanes       (xip_lanes),
        .o_xip_addr_lanes  (xip_addr_lanes),
        .o_xip_data_lanes  (xip_data_lanes),
        .o_xip_addr_bytes  (xip_addr_bytes),
        .o_xip_mode_en     (xip_mode_en),
        .o_xip_dummy_cycles(xip_dummy_cycles),
        // XIP cmd outputs
        .o_xip_read_op     (xip_read_op),
        .o_xip_mode_bits   (xip_mode_bits),

        // Command config outputs
        .o_cmd_lanes       (cmd_lanes),
        .o_addr_lanes      (addr_lanes),
        .o_data_lanes      (data_lanes),
        .o_addr_bytes      (addr_bytes),
        .o_mode_en         (mode_en),
        .o_dummy_cycles    (dummy_cycles),
        .o_dir             (dir),

        // Command opcode / mode
        .o_opcode          (opcode),
        .o_mode_bits       (mode_bits),

        // Command addr / len / dummy
        .o_cmd_addr        (cmd_addr),
        .o_cmd_len         (cmd_len),
        .o_extra_dummy     (extra_dummy),

        // DMA config outputs
        .o_dma_dir         (dma_dir),
        .o_incr_addr       (incr_addr),
        .o_dma_addr        (dma_addr),
        .o_dma_len         (dma_len),

        // TX FIFO interface
        .o_fifo_tx_data    (tx_data_csr),
        .o_fifo_tx_we      (tx_wen),
        .i_tx_full         (tx_full),

        // Interrupt enable outputs
        .o_cmd_done_en     (cmd_done_en),
        .o_dma_done_en     (dma_done_en),
        .o_err_en          (err_en),
        .o_fifo_tx_empty_en(fifo_tx_empty_en),
        .o_fifo_rx_full_en (fifo_rx_full_en),

        // Status inputs
        .i_busy            (ce_busy),
        .i_xip_active      (xip_active),
        .i_xip_done        (xip_done),
        .i_cmd_done        (cmd_done),
        .i_dma_done        (dma_done),

        // Interrupt status outputs (unused)
        .o_cmd_done        (),
        .o_dma_done        (),
        .o_err             (),
        .o_fifo_tx_empty   (),
        .o_fifo_rx_full    (),

        // RX FIFO interface
        .i_fifo_rx_data    (rx_data_csr),
        .o_fifo_rx_re      (rx_ren_csr),
        .i_rx_empty        (rx_empty),

        // FIFO status inputs
        .i_tx_level        (tx_level),
        .i_rx_level        (rx_level),
        .i_tx_empty        (tx_empty),
        .i_rx_full         (rx_full),

        // Error status inputs
        .i_timeout         (timeout),
        .i_overrun         (overrun),
        .i_underrun        (underrun),
        .i_dma_error       (dma_error),
        // Interrupt line
        .o_irq             (irq),

        // Clear trigger from CE
        .i_clear           (clear)
    );

    // TX FIFO
    tx_fifo #(
        .WIDTH (32),
        .DEPTH (4)
    ) u_tx_fifo (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .i_tx_wen   (tx_push),
        .i_tx_data  (tx_push_data),
        .o_tx_full  (tx_full),
        .i_tx_ren   (tx_ren),
        .o_tx_data  (tx_data_fifo),
        .o_tx_empty (tx_empty),
        .o_tx_level (tx_level)
    );
    assign dma_tx_ready = !tx_full && !tx_wen;

    // RX FIFO
    rx_fifo #(
        .WIDTH (32),
        .DEPTH (4)
    ) u_rx_fifo (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .i_rx_wen   (rx_wen),
        .i_rx_data  (rx_data_fifo),
        .o_rx_full  (rx_full),
        .i_rx_ren   (rx_ren_csr | rx_ren_dma | rx_ren_xip),
        .o_rx_data  (rx_data_csr),
        .o_rx_empty (rx_empty),
        .o_rx_level (rx_level)
    );

    // Command Engine (CE)
    ce u_command_engine (
        .i_clk         (clk),
        .i_rst_n       (rst_n),
        .i_cmd_trigger (cmd_trigger),
        .i_dma_en      (dma_en),
        .i_dma_dir     (dma_dir),
        .i_qspi_done   (qspi_done),
        .i_dma_done    (dma_done),
        .o_qspi_start  (qspi_start),
        .o_dma_start   (dma_start),
        .o_busy        (ce_busy),
        .o_clear       (clear),
        .o_cmd_done    (cmd_done)
    );

    // XIP block
    xip u_xip (
        .i_clk               (clk),
        .i_rst_n             (rst_n),

        // RX FIFO interface
        .i_rx_data           (rx_data_csr),
        .i_rx_empty          (rx_empty),
        .o_rx_ren            (rx_ren_xip),

        // AXI4-Lite Slave side (CPU fetch)
        .i_araddr            (s_araddr),
        .i_arprot            (s_arprot),
        .i_arvalid           (s_arvalid),
        .o_arready           (s_arready),

        .o_rdata             (xip_rdata_int),
        .o_rresp             (xip_rresp_int),
        .o_rvalid            (s_rvalid),
        .i_rready            (s_rready),

        // CSR control & config
        .i_xip_en            (xip_select),
        .i_xip_lanes         (xip_lanes),
        .i_xip_addr_lanes    (xip_addr_lanes),
        .i_xip_data_lanes    (xip_data_lanes),
        .i_xip_addr_bytes    (xip_addr_bytes),
        .i_xip_mode_en       (xip_mode_en),
        .i_xip_dummy_cycles  (xip_dummy_cycles),
        .i_xip_read_op       (xip_read_op),
        .i_xip_mode_bits     (xip_mode_bits),

        .o_xip_done          (xip_done),

        // QSPI outputs
        .o_qspi_start        (xip_qspi_start_o),
        .i_qspi_done         (qspi_done),
        .i_qspi_error        (timeout | overrun | underrun),

        .o_cmd_lanes         (xip_lanes_o),
        .o_addr_lanes        (xip_addr_lanes_o),
        .o_data_lanes        (xip_data_lanes_o),
        .o_addr_bytes        (xip_addr_bytes_o),
        .o_mode_en           (xip_mode_en_o),
        .o_dummy_cycles      (xip_dummy_cycles_o),
        .o_opcode            (xip_read_op_o),
        .o_mode_bits         (xip_mode_bits_o),
        .o_cmd_addr          (xip_addr_o),
        .o_cmd_len           (xip_len_o),
        .o_dir               (xip_dir_o),

        // Status
        .o_xip_active        (xip_active)
    );

    // QSPI MUX
    qspi_mux u_qspi_mux (
        .i_xip_en            (xip_select),

        // CE inputs
        .i_ce_qspi_start     (qspi_start),
        .i_ce_cmd_lanes      (cmd_lanes),
        .i_ce_addr_lanes     (addr_lanes),
        .i_ce_data_lanes     (data_lanes),
        .i_ce_addr_bytes     (addr_bytes),
        .i_ce_opcode         (opcode),
        .i_ce_mode_en        (mode_en),
        .i_ce_mode_bits      (mode_bits),
        .i_ce_dummy_cycles   (dummy_cycles),
        .i_ce_cmd_addr       (cmd_addr),
        .i_ce_cmd_len        (cmd_len),
        .i_ce_dir            (dir),

        // XIP inputs
        .i_xip_qspi_start    (xip_qspi_start_o),
        .i_xip_cmd_lanes     (xip_lanes_o),
        .i_xip_addr_lanes    (xip_addr_lanes_o),
        .i_xip_data_lanes    (xip_data_lanes_o),
        .i_xip_addr_bytes    (xip_addr_bytes_o),
        .i_xip_opcode        (xip_read_op_o),
        .i_xip_mode_en       (xip_mode_en_o),
        .i_xip_mode_bits     (xip_mode_bits_o),
        .i_xip_dummy_cycles  (xip_dummy_cycles_o),
        .i_xip_cmd_addr      (xip_addr_o),
        .i_xip_cmd_len       (xip_len_o),
        .i_xip_dir           (xip_dir_o),

        // Outputs to QSPI controller
        .o_qspi_start        (qspi_start_mux),
        .o_cmd_lanes         (cmd_lanes_mux),
        .o_addr_lanes        (addr_lanes_mux),
        .o_data_lanes        (data_lanes_mux),
        .o_addr_bytes        (addr_bytes_mux),
        .o_opcode            (opcode_mux),
        .o_mode_en           (mode_en_mux),
        .o_mode_bits         (mode_bits_mux),
        .o_dummy_cycles      (dummy_cycles_mux),
        .o_cmd_addr          (cmd_addr_mux),
        .o_cmd_len           (cmd_len_mux),
        .o_dir               (dir_mux)
    );

    // QSPI Controller
    qspi_controller u_qspi_controller (
        .i_clk          (clk),
        .i_rst_n        (rst_n),

        .i_qspi_start   (qspi_start_mux),
        .o_qspi_done    (qspi_done),

        .i_enable       (enable),
        .i_quad_en      (quad_en),
        .i_cpol         (cpol),
        .i_cpha         (cpha),
        .i_clk_div      (clk_div),
        .i_cs_auto      (cs_auto),
        .i_cs_level     (cs_level),
        .i_cs_delay     (cs_delay),

        .i_cmd_lanes    (cmd_lanes_mux),
        .i_addr_lanes   (addr_lanes_mux),
        .i_data_lanes   (data_lanes_mux),
        .i_addr_bytes   (addr_bytes_mux),
        .i_mode_en      (mode_en_mux),
        .i_dummy_cycles (dummy_cycles_mux),
        .i_dir          (dir_mux),
        .i_opcode       (opcode_mux),
        .i_mode_bits    (mode_bits_mux),
        .i_cmd_addr     (cmd_addr_mux),
        .i_extra_dummy  (extra_dummy_mux),
        .i_cmd_len      (cmd_len_mux),

        .o_tx_ren       (tx_ren),
        .i_tx_data_fifo (tx_data_fifo),
        .i_tx_empty     (tx_empty),

        .o_rx_wen       (rx_wen),
        .o_rx_data_fifo (rx_data_fifo),
        .i_rx_full      (rx_full),

        .o_sclk         (qspi_sclk),
        .o_cs_n         (qspi_cs_n),
        .io_qspi_io0    (qspi_io0),
        .io_qspi_io1    (qspi_io1),
        .io_qspi_io2    (qspi_io2),
        .io_qspi_io3    (qspi_io3),

        .o_timeout      (timeout),
        .o_overrun      (overrun),
        .o_underrun     (underrun)
    );

    // DMA Engine
    dma u_dma (
        .i_clk        (clk),
        .i_rst_n      (rst_n),

        // CSR
        .i_dma_dir    (dma_dir),
        .i_incr_addr  (incr_addr),
        .i_dma_addr   (dma_addr),
        .i_dma_len    (dma_len),
        .i_dma_start  (dma_start),
        .o_dma_done   (dma_done),
        .o_dma_error  (dma_error),

        // AXI4 master
        .o_awaddr     (m_awaddr),
        .o_awlen      (m_awlen),
        .o_awsize     (m_awsize),
        .o_awburst    (m_awburst),
        .o_awvalid    (m_awvalid),
        .i_awready    (m_awready),

        .o_wdata      (m_wdata),
        .o_wstrb      (m_wstrb),
        .o_wlast      (m_wlast),
        .o_wvalid     (m_wvalid),
        .i_wready     (m_wready),

        .i_bresp      (m_bresp),
        .i_bvalid     (m_bvalid),
        .o_bready     (m_bready),
        .o_araddr     (m_araddr),
        .o_arlen      (m_arlen),
        .o_arsize     (m_arsize),
        .o_arburst    (m_arburst),
        .o_arvalid    (m_arvalid),
        .i_arready    (m_arready),
        .i_rdata      (m_rdata),
        .i_rresp      (m_rresp),
        .i_rlast      (m_rlast),
        .i_rvalid     (m_rvalid),
        .o_rready     (m_rready),
        .o_tx_data    (dma_tx_data),
        .o_tx_valid   (dma_tx_valid),
        .i_tx_ready   (dma_tx_ready),
        // RX FIFO interface
        .o_rx_ren     (rx_ren_dma),
        .i_rx_data    (rx_data_csr),
        .i_rx_empty   (rx_empty)
    );

endmodule

`default_nettype wire
