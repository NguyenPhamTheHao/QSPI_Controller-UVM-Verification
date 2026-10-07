class apb_base_seq #(type REQ = uvm_sequence_item, type RSP = uvm_sequence_item) extends uvm_sequence #(REQ,RSP);
  `uvm_object_param_utils(apb_base_seq#(REQ,RSP))
  
    string my_name;

    function new(string name="");
        super.new(name);
    endfunction

  // Task write (For transaction)
  virtual task apb_write(input bit [11:0] addr, input bit [31:0] data);
    REQ req;
    req = REQ::type_id::create("req");
    
    start_item(req);
    req.pwrite = 1'b1;     
    req.paddr  = addr;
    req.pwdata = data;
    req.pstrb  = 4'b1111;
    req.pprot  = 3'b000;
    finish_item(req);     
  endtask

  // Task read (For transaction)
  virtual task apb_read(input bit [11:0] addr, output bit [31:0] rdata);
    REQ req;
    req = REQ::type_id::create("req");
    
    start_item(req);
    req.pwrite = 1'b0;     
    req.paddr  = addr;
    finish_item(req);      
    
    rdata = req.prdata;    
  endtask

  //Task reset system
  virtual task apb_reset_system();
    REQ req;
    req= REQ::type_id::create("req");

    start_item(req);
    req.to_reset= 1'b0;
    finish_item(req);
  endtask
endclass