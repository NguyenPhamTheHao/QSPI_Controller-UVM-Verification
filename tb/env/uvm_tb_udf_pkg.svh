package uvm_tb_udf_pkg;
//============================ REGISTER=========================================================
  // 
  //
  // System, Control & Status
  parameter bit [11:0] ADDR_ID        = 12'h000; // Identification/version
  parameter bit [11:0] ADDR_CTRL      = 12'h004; // Controller and command control
  parameter bit [11:0] ADDR_STATUS    = 12'h008; // Controller status
  parameter bit [11:0] ADDR_INT_EN    = 12'h00C; // Interrupt enable
  parameter bit [11:0] ADDR_INT_STAT  = 12'h010; // Latched interrupt/status flags
  parameter bit [11:0] ADDR_CLK_DIV   = 12'h014; // QSPI clock divider
  parameter bit [11:0] ADDR_CS_CTRL   = 12'h018; // Chip-select control

  // 
  //
  // Execute-in-Place
  parameter bit [11:0] ADDR_XIP_CFG   = 12'h01C; // XIP transaction configuration
  parameter bit [11:0] ADDR_XIP_CMD   = 12'h020; // XIP opcode and mode value

  // 
  //
  // PIO Command 
  parameter bit [11:0] ADDR_CMD_CFG   = 12'h024; // Indirect command format
  parameter bit [11:0] ADDR_CMD_OP    = 12'h028; // Indirect opcode and mode value
  parameter bit [11:0] ADDR_CMD_ADDR  = 12'h02C; // Flash address
  parameter bit [11:0] ADDR_CMD_LEN   = 12'h030; // Command data length in bytes
  parameter bit [11:0] ADDR_CMD_DUMMY = 12'h034; // Additional dummy-cycle configuration

  // 
  //
  // DMA
  parameter bit [11:0] ADDR_DMA_CFG   = 12'h038; // DMA direction and address control
  parameter bit [11:0] ADDR_DMA_ADDR  = 12'h03C; // DMA system-memory start address
  parameter bit [11:0] ADDR_DMA_LEN   = 12'h040; // DMA transfer length in bytes

  //
  //
  // FIFO & Error Status
  parameter bit [11:0] ADDR_WRITE_TX  = 12'h044; // TX FIFO data port
  parameter bit [11:0] ADDR_READ_RX   = 12'h048; // RX FIFO data port
  parameter bit [11:0] ADDR_FIFO_STAT = 12'h04C; // FIFO status
  parameter bit [11:0] ADDR_ERR_STAT  = 12'h050; // Error status

  //
  //
  // LUT (Look-Up Table)
  //
  parameter bit [11:0] ADDR_LUT_CTRL  = 12'h054; // LUT enable and entry index
  parameter bit [11:0] ADDR_LUT_CFG   = 12'h058; // Selected LUT command configuration
  parameter bit [11:0] ADDR_LUT_OP    = 12'h05C; // Selected LUT opcode/mode value
  parameter bit [11:0] ADDR_LUT_DUMMY = 12'h060; // Selected LUT dummy configuration

  //============================ TYPES & ENUMS ====================================================
  
  //
  //
  // QSPI Monitor FSM States
  typedef enum {
    ST_IDLE, 
    ST_CMD, 
    ST_ADDR, 
    ST_DUMMY, 
    ST_DATA
  } qspi_state_e;
  
typedef enum {IS_TRUE, IS_FALSE, IS_ENABLE, IS_DISABLE} bool_t;
parameter int RESET_LENGTH =5;
prameter int HALF_CLK =50;
parameter GLB_TIMEOUT   =  500000;
parameter DRAIN_TIME    =    1000;
endpackage