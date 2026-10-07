class qspi_agent #(type CMD_PKT = cmd_tlm, type DATA_PKT= read_data_tlm) extends uvm_agent;
  `uvm_component_param_utils(qspi_agent#(CMD_PKT,DATA_PKT))
  string my_name;

  typedef qspi_driver  driver_t;
  typedef qspi_monitor #(CMD_PKT,DATA_PKT)  monitor_t;
  driver_t driver;
  monitor_t monitor;

  uvm_analysis_port #(CMD_PKT) act_cmd_port; // Forward ra cho Scoreboard/Coverage
  uvm_analysis_port #(DATA_PKT) exp_data_port;

  //
  // NEW
  //
  function new(string name, uvm_component parent);
    super.new(name, parent);
    my_name = get_name();
  endfunction

  //
  // BUILD phase
  //
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver     = driver_t::type_id::create("qspi_driver", this);
    monitor    = monitor_t::type_id::create("qspi_monitor", this);
    act_cmd_port = new("act_cmd_port",this);
    exp_data_port = new("exp_data_port",this);
  endfunction

  //
  // CONNECT phase
  //
  function void connect_phase(uvm_phase phase);
    monitor.act_cmd_port.connect(this.act_cmd_port);
    monitor.exp_data_port.connect(this.exp_data_port);
  endfunction

endclass