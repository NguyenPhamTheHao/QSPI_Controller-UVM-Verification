// The test package provides a test layer between the top module and the environment. More than one test can be included here
//*********************************************************
package qspi_test_pkg;

	import uvm_pkg::*;
	import uvm_tb_udf_pkg::*;
	import qspi_env_pkg::*;
	import apb_seq_pkg::*;
	import tlm_pkg::*;
	import qspi_cfg_pkg::*;
	
	
		`include "uvm_macros.svh"
		`include "base_test.sv"
//
// All news tests must derive from base_test and must be listed here
// Each test is saved as one file
//
		`include "pio_normal_read_03_4bytes_test.sv"
		`include "pio_normal_read_03_5bytes_test.sv"
		`include "pio_fast_read_0b_4bytes_test.sv"
		`include "pio_quad_read_6b_4bytes_test.sv"
		`include "pio_quad_read_6b_5bytes_test.sv"
endpackage