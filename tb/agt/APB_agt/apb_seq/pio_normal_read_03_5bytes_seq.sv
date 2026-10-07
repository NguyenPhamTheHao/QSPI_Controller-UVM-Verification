class pio_normal_read_03_4bytes_seq #(type REQ=uvm_sequence_item, type RSP=uvm_sequence_item) extends apb_base_seq #(REQ,RSP);
  `uvm_object_param_utils(pio_normal_read_03_4bytes_seq #(REQ,RSP))

  function new(string name = "");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] status_val;
    bit [31:0] read_data;

    `uvm_info(get_type_name(), "Normal Read 03 (Data length= 5bytes)", UVM_LOW)
    //Reset system
    apb_reset_system();
    //Config chip select
    apb_write(ADDR_CS_CTRL,  32'h0000_0001); //CS_AUTO=1
    // Config the Command
    apb_write(ADDR_CMD_CFG,  32'h0000_2040); // lanes = 1-1-1, dir = read
    apb_write(ADDR_CMD_OP,   32'h0000_0003); // opcode = 03
    apb_write(ADDR_CMD_ADDR, 32'h0000_0000); // addr = 24'h00_0000
    apb_write(ADDR_CMD_LEN,  32'h0000_0005); // data_length = 5 bytes

    // (Trigger)
    apb_write(ADDR_CTRL,     32'h0000_0101); 

    `uvm_info(get_type_name(), "Waiting for data received from QSPI Slave ...", UVM_HIGH)
    
    for(int i=0;i<2;i=i+1) begin
    do begin
      apb_read(ADDR_FIFO_STAT, status_val);
    end while (status_val[7:4] == 4'b0000); 

    // READ_RX (0x048)
    apb_read(ADDR_READ_RX, read_data);
    
    `uvm_info(get_type_name(), $sformatf("Completed! Data read from READ_RX: 'h%0h", read_data), UVM_LOW)
    end
  endtask

endclass