class qspi_tlm extends uvm_sequence_item;
    rand bit [7:0]  opcode;         
    rand bit [31:0] address;       
    rand bit [7:0]  data_payload[]; 
    int cmd_lanes;
    int addr_lanes;
    int data_lanes;
    int addr_bytes;
    int dummy_cycles;
    bit is_read; // 1 = Read, 0= Write.

    `uvm_object_utils_begin(qspi_tlm)
        `uvm_field_int(opcode,        UVM_ALL_ON)
        `uvm_field_int(address,       UVM_ALL_ON)
        `uvm_field_array_int(data_payload, UVM_ALL_ON) 
        `uvm_field_int(cmd_lanes,     UVM_ALL_ON)
        `uvm_field_int(addr_lanes,    UVM_ALL_ON)
        `uvm_field_int(data_lanes,    UVM_ALL_ON)
        `uvm_field_int(addr_bytes,    UVM_ALL_ON)
        `uvm_field_int(dummy_cycles,  UVM_ALL_ON)
        `uvm_field_int(is_read,       UVM_ALL_ON)
    `uvm_object_utils_end

    constraint data_size_c {
        soft data_payload.size() inside {[0 : 256]}; 
    }

    function new(string name = "qspi_tlm");
        super.new(name);
    endfunction

endclass