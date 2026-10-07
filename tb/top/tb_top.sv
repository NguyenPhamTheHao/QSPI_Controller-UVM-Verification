module tb_top;

import uvm_pkg::*;
`include "uvm_macros.svh"

import uvm_tb_udf_pkg::*;
import qspi_test_pkg::*;

wire clk;
wire rst_n;

// 1. Khai báo các Interface cần thiết cho PIO
clk_rst_if      clk_rst_vif(.clk(clk), .rst_n(rst_n));      // Cấp Clock và Reset[cite: 30]
apb_if          apb_vif(.clk(clk),.rst_n(rst_n)); // Giao tiếp APB[cite: 28]
qspi_if         qspi_vif();             // Giao tiếp QSPI[cite: 29]

// (Các tín hiệu ảo để "buộc" ngõ vào của XIP và DMA tránh lỗi thả nổi)
logic [31:0] s_araddr = '0;
logic [2:0]  s_arprot = '0;
logic        s_arvalid = 1'b0;
logic        s_rready = 1'b0;
logic        m_awready = 1'b0;
logic        m_wready = 1'b0;
logic [1:0]  m_bresp = '0;
logic        m_bvalid = 1'b0;
logic        m_arready = 1'b0;
logic [31:0] m_rdata = '0;
logic [1:0]  m_rresp = '0;
logic        m_rlast = 1'b0;
logic        m_rvalid = 1'b0;

// 2. Khởi tạo DUT (top_module)
top_module dut (

    // Clock & Reset
    .clk        (clk_rst_vif.clk),        
    .rst_n      (clk_rst_vif.rst_n),      

    // APB Interface
    .psel       (apb_vif.psel),           
    .penable    (apb_vif.penable),     
    .pwrite     (apb_vif.pwrite),        
    .paddr      (apb_vif.paddr),        
    .pwdata     (apb_vif.pwdata),       
    .pstrb      (apb_vif.pstrb),        
    .pprot      (apb_vif.pprot),        
    .prdata     (apb_vif.prdata),     
    .pready     (apb_vif.pready),        

    // QSPI Interface
    .qspi_sclk  (qspi_vif.qspi_sclk),    
    .qspi_cs_n  (qspi_vif.qspi_cs_n),    
    .qspi_io0   (qspi_vif.qspi_io0),      
    .qspi_io1   (qspi_vif.qspi_io1),      
    .qspi_io2   (qspi_vif.qspi_io2),      
    .qspi_io3   (qspi_vif.qspi_io3),      

    // XIP & DMA 
    .s_araddr   (s_araddr),
    .s_arprot   (s_arprot),
    .s_arvalid  (s_arvalid),
    .s_arready  (),
    .s_rdata    (),
    .s_rresp    (),
    .s_rvalid   (),
    .s_rready   (s_rready),

    .m_awaddr   (),
    .m_awlen    (),
    .m_awsize   (),
    .m_awburst  (),
    .m_awvalid  (),
    .m_awready  (m_awready),
    .m_wdata    (),
    .m_wstrb    (),
    .m_wlast    (),
    .m_wvalid   (),
    .m_wready   (m_wready),
    .m_bresp    (m_bresp),
    .m_bvalid   (m_bvalid),
    .m_bready   (),
    .m_araddr   (),
    .m_arlen    (),
    .m_arsize   (),
    .m_arburst  (),
    .m_arvalid  (),
    .m_arready  (m_arready),
    .m_rdata    (m_rdata),
    .m_rresp    (m_rresp),
    .m_rlast    (m_rlast),
    .m_rvalid   (m_rvalid),
    .m_rready   (),

    // Status (Để trống nếu không test IRQ/SLVERR)
    .pslverr    (apb_vif.pslverr),        //[cite: 27, 28]
    .irq        ()
);

// 3. Đưa Interface vào uvm_config_db và khởi động mô phỏng
initial begin
  uvm_config_db#(virtual clk_rst_if)::set(null, "*", "clk_rst_vif", clk_rst_vif);
  uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_vif);      
  uvm_config_db#(virtual qspi_if)::set(null, "*", "qspi_vif", qspi_vif); 

  run_test();
end

endmodule