class apb_tlm extends uvm_sequence_item;

    `uvm_object_utils(apb_tlm)

    string   my_name;
    
    //Master to Slave
    bit        psel;
    bit        penable;
    rand bit        pwrite;
    rand bit [11:0] paddr;   
    rand bit [31:0] pwdata;
    rand bit [3:0]  pstrb;
    rand bit [2:0]  pprot;
    
    // Slave to Master 
    bit [31:0] prdata;
    bit        pready;
    bit        pslverr; 

    //Reset
    bit to_reset;

    `uvm_object_utils_begin(apb_tlm)
        `uvm_field_int(pwrite,  UVM_ALL_ON)
        `uvm_field_int(paddr,   UVM_ALL_ON)
        `uvm_field_int(pwdata,  UVM_ALL_ON)
        `uvm_field_int(pstrb,   UVM_ALL_ON)
        `uvm_field_int(pprot,   UVM_ALL_ON)
        `uvm_field_int(prdata,  UVM_ALL_ON)
        `uvm_field_int(pready,  UVM_ALL_ON)
        `uvm_field_int(pslverr, UVM_ALL_ON)
        `uvm_field_int(to_reset, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint default_pstrb {
        soft pstrb == 4'b1111;
    }

    //
    // NEW
    //
    function new(string name = "apb_tlm");
        super.new(name);
        my_name = name;
    endfunction
endclass