class cmd_tlm extends uvm_sequence_item;
    bit [7:0] opcode;
    bit [23:0] address;
    bit [7:0] data_payload[];
    bit [31:0] data_len;
    int dummy_cycles;
`uvm_object_utils_begin(cmd_tlm)
        `uvm_field_int(opcode,        UVM_ALL_ON)
        `uvm_field_int(address,       UVM_ALL_ON)
        `uvm_field_array_int(data_payload, UVM_ALL_ON) 
        `uvm_field_array_int(data_len, UVM_ALL_ON) 
        `uvm_field_int(dummy_cycles,  UVM_ALL_ON)
`uvm_object_utils_end
function new(string name = "cmd_tlm");
        super.new(name);
endfunction

function void do_copy(uvm_object rhs);

  cmd_tlm  der_type;

  super.do_copy(rhs);

  $cast(der_type,rhs);

  opcode = der_type.opcode;

  address = der_type.address;

  data_len = der_type.data_len;
  dummy_cycles= der_type.dummy_cycles;

  data_payload = der_type.data_payload;

endfunction

virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);

  cmd_tlm  der_type;

  do_compare = super.do_compare(rhs,comparer);

  $cast(der_type,rhs);

  do_compare &= comparer.compare_field_int("opcode", opcode, der_type.opcode, $bits(opcode));

  do_compare &= comparer.compare_field_int("address", address, der_type.address, $bits(address));

  do_compare &= comparer.compare_field_int("data_len", data_len, der_type.data_len, $bits(data_len));

  do_compare &= comparer.compare_field_int("dummy_cycles", dummy_cycles, der_type.dummy_cycles, $bits(dummy_cycles));

  if (data_payload.size() != der_type.data_payload.size()) begin
    do_compare = 0;
    `uvm_info(get_type_name(), $sformatf("Size mismatch on data_payload! ACT: %0d bytes vs EXP: %0d bytes", data_payload.size(), der_type.data_payload.size()), UVM_LOW)
  end
  else begin
    foreach (data_payload[i]) begin
      do_compare &= comparer.compare_field_int($sformatf("data_payload[%0d]", i), data_payload[i], der_type.data_payload[i], 8);
    end
  end
endfunction
endclass