//*********************************************************
package apb_seq_pkg;

	import uvm_pkg::*;
	import uvm_tb_udf_pkg::*;
	
		`include "uvm_macros.svh"
		`include "apb_base_seq.sv"
        
        //Sequence for testing Read/Write command
        `include "pio_normal_read_03_4bytes_seq.sv"
        `include "pio_normal_read_03_5bytes_seq.sv"

        `include "pio_fast_read_0b_4bytes_seq.sv"

        `include "pio_quad_read_6b_4bytes_seq.sv"
        `include "pio_quad_read_6b_5bytes_seq.sv"

        //Sequence for testing read/write access through Programming Register
		
endpackage