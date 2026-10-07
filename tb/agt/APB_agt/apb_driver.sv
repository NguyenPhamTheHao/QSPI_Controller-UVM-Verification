class apb_driver #(type REQ=uvm_sequence_item) extends uvm_driver #(REQ);
  `uvm_component_param_utils(apb_driver #(REQ))

  string my_name;

  //Declare interface
  virtual apb_if vif;
  virtual clk_rst_if clk_rst_vif;

  //Declare configuration
  qspi_cfg driver_cfg;
  int unsigned max_wait_cycles = 1000;

  //
  //NEW
  //
  function new(string name = "apb_driver", uvm_component parent=null);
    super.new(name,parent);
    my_name=name;
  endfunction

  //
  //BUILD
  //
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    //Check for interface
    if( !uvm_config_db #(virtual apb_if)::get(this,"","apb_vif",vif))
      `uvm_error(get_type_name(),"No APB virtual interface connected")
    if( !uvm_config_db #(virtual clk_rst_if)::get(this,"","clk_rst_vif",clk_rst_vif))
      `uvm_error(get_type_name(),"No Clock Reset system virtual interface connected")

    // Keep the default timeout when the test does not set this option.
    void'(uvm_config_db #(int unsigned)::get(this, "", "apb_max_wait_cycles", max_wait_cycles));
  endfunction

  function void connect_phase(uvm_phase phase);

    //
    // Getting a handle to the global config object in driver_cfg
    //

    if( !uvm_config_db #(qspi_cfg)::get(this,"","TB_CONFIG",driver_cfg) ) begin

      `uvm_error(my_name, "Could not retrieve qspi_cfg");

    end

  endfunction
    //
    //START OF SIMULATION
    //
    function void start_of_simulation_phase(uvm_phase phase);
      super.start_of_simulation_phase(phase);

      // Control verbosity
      if (driver_cfg.verbosity_control_arr["driver"] == IS_ENABLE)
        set_report_verbosity_level(UVM_MEDIUM + 1);
      else
        set_report_verbosity_level(UVM_MEDIUM - 1);
    endfunction

    //
    //RUN
    //
    task run_phase(uvm_phase phase);

      REQ req;

      //For clean initialization
      drive_idle();

      forever begin
      //Always receiving packet from sequencer
      seq_item_port.get_next_item(req);
      if(req.to_reset == 1'b1) begin //Check for reset system from sequence
        clk_rst_vif.do_reset(RESET_LENGTH);
        drive_idle();
      end
      else begin
        wait(vif.rst_n == 1'b1);
        drive_transfer(req);
      end
      seq_item_port.item_done();
      end
    endtask

    // Drive known idle values before the first request and between transfers.
    // These are master outputs only; PRDATA, PREADY, and PSLVERR belong to DUT.
    protected function void drive_idle();
      vif.psel    = 1'b0;
      vif.penable = 1'b0;
      vif.pwrite  = 1'b0;
      vif.paddr   = '0;
      vif.pwdata  = '0;
      vif.pstrb   = '0;
      vif.pprot   = '0;
    endfunction

    protected task drive_transfer(apb_tlm req);
      int unsigned wait_cycles = 0;

      // Clear response fields in case a sequence reuses an item. rst_n is
      // active low; do not start a transfer while reset is asserted.
      req.prdata  = '0;
      req.pready  = 1'b0;
      req.pslverr = 1'b0;
      do begin
        @(negedge vif.clk);
      end while (vif.rst_n !== 1'b1);

      // SETUP: drive address and control with PSEL high and PENABLE low.
      // Driving on the falling edge makes them stable before the next
      // rising edge, when the APB slave samples the setup phase.
      vif.psel    = 1'b1;
      vif.penable = 1'b0;
      vif.pwrite  = req.pwrite;
      vif.paddr   = req.paddr;
      vif.pwdata  = req.pwrite ? req.pwdata : '0;
      vif.pstrb   = req.pwrite ? req.pstrb  : '0;
      vif.pprot   = req.pprot;
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) begin
        `uvm_error(get_type_name(), "Reset interrupted the APB setup phase")
        @(negedge vif.clk);
        drive_idle();
        return;
      end

      // ACCESS: assert PENABLE on the following falling edge. Address,
      // direction, write data, strobes, and protection remain unchanged.
      @(negedge vif.clk);
      if (vif.rst_n !== 1'b1) begin
        `uvm_error(get_type_name(), "Reset interrupted the APB setup phase")
        drive_idle();
        return;
      end
      vif.penable = 1'b1;

      // The slave may insert wait cycles by keeping PREADY low. Sample
      // PRDATA and PSLVERR only on a rising edge with PSEL, PENABLE, and
      // PREADY asserted together.
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n !== 1'b1) begin
          `uvm_error(get_type_name(), "Reset interrupted the APB access phase")
          break;
        end
        if (vif.pready === 1'b1) begin
          req.pready = 1'b1;
          req.pslverr = vif.pslverr;
          if (!req.pwrite)
            req.prdata = vif.prdata;
          `uvm_info(get_type_name(),
            $sformatf("APB %s addr=0x%03h wdata=0x%08h rdata=0x%08h slverr=%0b",
              req.pwrite ? "WRITE" : "READ", req.paddr,
              req.pwdata, req.prdata, req.pslverr), UVM_MEDIUM)
          break;
        end
        wait_cycles++;
        if (max_wait_cycles != 0 && wait_cycles >= max_wait_cycles) begin
          `uvm_error(get_type_name(),
            $sformatf("APB timeout at address 0x%03h after %0d access cycles",
              req.paddr, wait_cycles))
          break;
        end
      end

      // Keep the access signals stable through the completion edge, then
      // return to idle on the next falling edge.
      @(negedge vif.clk);
      drive_idle();
    endtask
endclass