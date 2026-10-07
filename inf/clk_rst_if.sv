import uvm_tb_udf_pkg::*;
interface clk_rst_if (output logic clk, output logic rst_n);
// pragma attribute clk_rst_if partition_interface_xif

    //
    // Generate reset
    //
    task do_reset (integer reset_length); // pragma tbx xtf
        rst_n = 0;
        #(reset_length*HALF_CLK*2);
        rst_n = 1;
    endtask


    //
    // Generate clock
    //
    initial begin
        #1;
        clk = 1;
        forever begin
            #HALF_CLK clk = ~clk;
        end
    end

endinterface