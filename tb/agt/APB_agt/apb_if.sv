interface apb_if(input logic clk, input logic rst_n);
  // Master to Slave (Driven by APB Driver)
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;   
  logic [31:0] pwdata;
  logic [3:0]  pstrb;
  logic [2:0]  pprot;
  
  // Slave to Master 
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr; 
endinterface