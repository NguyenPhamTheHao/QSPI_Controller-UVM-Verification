class read_data_tlm extends uvm_sequence_item;
  bit [31:0] read_data;

  `uvm_object_utils_begin(read_data_tlm)
    `uvm_field_int(read_data, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "read_data_tlm");
    super.new(name);
  endfunction
  function void do_copy(uvm_object rhs);

  read_data_tlm der_type;

  super.do_copy(rhs);

  $cast(der_type,rhs);

  read_data = der_type.read_data;

endfunction

virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);

  read_data_tlm der_type;

  do_compare = super.do_compare(rhs,comparer);

  $cast(der_type,rhs);

  do_compare &= comparer.compare_field_int("read_data",read_data,der_type.read_data,$bits(read_data));

endfunction
endclass