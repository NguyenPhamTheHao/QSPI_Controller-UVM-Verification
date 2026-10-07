class apb_monitor #(type APB_PKT=uvm_sequence_item, type CMD_PKT=uvm_sequence_item, type DATA_PKT=uvm_sequence_item) extends uvm_monitor;
  `uvm_component_param_utils(apb_monitor #(APB_PKT,CMD_PKT,DATA_PKT))

  //Declaration
  string my_name;
  virtual apb_if vif;
  qspi_cfg monitor_cfg;

  //Analysis Port
  uvm_analysis_port #(CMD_PKT) exp_cmd_port;
  uvm_analysis_port #(APB_PKT) act_apb_port;
  uvm_analysis_port #(DATA_PKT) act_data_port;
// ==========================================

  // REFERENCE MODEL for expected command packet

  // ==========================================

  bit [7:0]  ref_opcode;

  bit [23:0] ref_address;

  bit [31:0] ref_data_len;

  int        ref_dummy_cycles;

  bit [7:0]  ref_tx_fifo[$]; // Store write data from TX_FIFO

  //==========================================

  int unsigned transfer_count = 0;
  //
  //NEW
  //
  function new(string name="apb_monitor", uvm_component parent = null);
    super.new(name,parent);
  endfunction

  //
  //BUILD
  //
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    //Check for interface connection
    if( !uvm_config_db #(virtual apb_if)::get(this,"","apb_vif",vif))
      `uvm_fatal(get_type_name(),"No APB Virtual interface connected")

    //Create analysis port
    exp_cmd_port =new("exp_cmd_port",this);
    act_apb_port= new("act_apb_port",this);
    act_data_port= new("act_data_port",this);
  endfunction

  //
  //CONNECT
  //
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    assert(uvm_resource_db #(qspi_cfg)::read_by_name(get_full_name(),"TB_CONFIG",monitor_cfg));
      if (monitor_cfg.inject_error == IS_TRUE)
        `uvm_info(my_name,"Error injection is true",UVM_NONE)
      else
        `uvm_info(my_name,"Error injection is false",UVM_NONE)
  endfunction

  //
  //START OF SIMULATION
  //
  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (monitor_cfg.verbosity_control_arr["monitor"] == IS_ENABLE)
      set_report_verbosity_level(UVM_MEDIUM + 1);
    else
      set_report_verbosity_level(UVM_MEDIUM - 1);
  endfunction

  task run_phase(uvm_phase phase);
    APB_PKT tr;
    CMD_PKT cmd_tr;
    forever begin
      @(posedge vif.clk);

      // rst_n is active low. Ignore bus values during reset because
      // they do not represent completed register accesses.
      if (vif.rst_n !== 1'b1) begin
        ref_tx_fifo.delete();
        continue;
      end
      //=================DIRECT APB TRANSACTION CAPTURING=================
      // APB completes a transfer only in the access phase when the
      // slave asserts PREADY. This also handles any number of wait
      // cycles without publishing duplicate transactions.
      if (vif.psel === 1'b1 && vif.penable === 1'b1 &&vif.pready === 1'b1) begin
        transfer_count++;
        tr = APB_PKT::type_id::create(
          $sformatf("apb_transfer_%0d", transfer_count));

        // Capture the request as it appeared on the bus. PSEL and
        // PENABLE are high here because this is a completed access.
        tr.psel    = vif.psel;
        tr.penable = vif.penable;
        tr.pwrite  = vif.pwrite;
        tr.paddr   = vif.paddr;
        tr.pwdata  = vif.pwdata;
        tr.pstrb   = vif.pstrb;
        tr.pprot   = vif.pprot;

        // PRDATA is meaningful for reads; PSLVERR applies to either
        // read or write transfers. PREADY records completion.
        tr.prdata = (vif.pwrite === 1'b0) ? vif.prdata : '0;
        tr.pready = vif.pready;
        tr.pslverr = vif.pslverr;
        `uvm_info(get_type_name(),
          $sformatf("Observed APB %s addr=0x%03h wdata=0x%08h rdata=0x%08h slverr=%0b",
            tr.pwrite ? "WRITE" : "READ", tr.paddr,
            tr.pwdata, tr.prdata, tr.pslverr), UVM_MEDIUM)

        // Subscribers receive the transaction observed on the bus,
        // independently of the request object used by the driver.
        act_apb_port.write(tr);

        //WRITE TRANSACTION
        //=================CAPTURING FOR CMD REFERENCE======================================
        if(tr.pwrite==1) begin
          case(tr.paddr)
            ADDR_CMD_ADDR: ref_address      =tr.pwdata[23:0];
            ADDR_CMD_CFG:  ref_dummy_cycles =tr.pwdata[12:9];
            ADDR_CMD_OP:   ref_opcode       =tr.pwdata[7:0];
            ADDR_CMD_LEN:  ref_data_len     =tr.pwdata[31:0];
            ADDR_WRITE_TX: begin
              ref_tx_fifo.push_back(tr.pwdata[7:0]);
              ref_tx_fifo.push_back(tr.pwdata[15:8]);
              ref_tx_fifo.push_back(tr.pwdata[23:16]);
              ref_tx_fifo.push_back(tr.pwdata[31:24]);
            end
            ADDR_CTRL: begin
              //Monitor and detect when command is triggered
              if(tr.pwdata[8]==1'b1) begin
                //Create CMD_PKT
                cmd_tr=CMD_PKT::type_id::create("cmd_tr");
                cmd_tr.opcode       = ref_opcode;
                cmd_tr.address      = ref_address;
                cmd_tr.dummy_cycles = ref_dummy_cycles;
                cmd_tr.data_len     = ref_data_len;
                //Capturign write data to WRITE_TX
                cmd_tr.data_payload= new[ref_data_len];
                for(int i=0;i<ref_data_len;i=i+1) begin
                  if(ref_tx_fifo.size() > 0 )
                    cmd_tr.data_payload[i]=ref_tx_fifo.pop_front();
                  else
                    cmd_tr.data_payload[i]=8'hFF;
                end
                `uvm_info(my_name, $sformatf("TRIGGER DETECTED! Generated Expected CMD:OP=%0h, LEN=%0d, ADDR=%0h, DUMMY=%0d, WRITE_DATA=%0p",cmd_tr.opcode, cmd_tr.data_len, cmd_tr.address, cmd_tr.dummy_cycles, cmd_tr.data_payload), UVM_LOW)
                exp_cmd_port.write(cmd_tr);
              end
            end
          endcase
        end

        //READ TRANSACTION
        //=================CAPTURING FOR ACT DATA REFERENCE======================
        if (tr.pwrite == 1'b0) begin
          case (tr.paddr)
            ADDR_READ_RX: begin
              DATA_PKT data_tr;
              data_tr = DATA_PKT::type_id::create("data_tr");
              data_tr.read_data = tr.prdata;
              act_data_port.write(data_tr);
              `uvm_info(my_name, $sformatf("ACT DATA CAPTURED: Read from RX_REG = %0h", data_tr.read_data), UVM_HIGH)
            end
          endcase
        end
      end
    end
  endtask
endclass