class qspi_scoreboard #(type CMD_PKT=cmd_tlm, type DATA_PKT=read_data_tlm) extends uvm_scoreboard;
  `uvm_component_param_utils(qspi_scoreboard#(CMD_PKT,DATA_PKT))

  string my_name;

  uvm_tlm_analysis_fifo #(CMD_PKT) exp_cmd_fifo;
  uvm_tlm_analysis_fifo #(DATA_PKT) act_data_fifo;
  //Todo: Declare exp_data_fifo, act_cmd_fifo
  uvm_tlm_analysis_fifo #(CMD_PKT) act_cmd_fifo;
  uvm_tlm_analysis_fifo #(DATA_PKT) exp_data_fifo;
  qspi_cfg scoreboard_cfg;

  //
  //NEW
  //
  function new(string name="qspi_scoreboard",uvm_component parent);
    super.new(name,parent);
    my_name=name;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_cmd_fifo= new("exp_cmd_fifo",this);
    act_data_fifo=new("act_data_fifo",this);
    act_cmd_fifo = new("act_cmd_fifo",this);
    exp_data_fifo=new("exp_data_fifo",this);
    //Todo: create exp_data_fifo, act_cmd_fifo
  endfunction

  //
  // START_OF_SIMULATION phase
  //
  function void start_of_simulation_phase(uvm_phase phase);
    if (scoreboard_cfg.verbosity_control_arr["scoreboard"] == IS_ENABLE)
      set_report_verbosity_level(UVM_MEDIUM + 1);
    else
      set_report_verbosity_level(UVM_MEDIUM - 1);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    assert(uvm_resource_db #(qspi_cfg)::read_by_name(get_full_name(),"TB_CONFIG",scoreboard_cfg));
  endfunction
//
  // RUN phase
  //
  task run_phase(uvm_phase phase);
    CMD_PKT exp_cmd, act_cmd;
    DATA_PKT exp_data, act_data;

    fork
      forever begin
        act_cmd_fifo.get(act_cmd); // Block chờ đến khi có packet thực tế từ QSPI Bus

        if (exp_cmd_fifo.is_empty()) begin
          `uvm_error(my_name, "exp_cmd_fifo is empty but actual CMD received!")
        end else begin
          exp_cmd_fifo.get(exp_cmd);
          if (exp_cmd.compare(act_cmd)) begin
            `uvm_info(my_name, "CMD MATCHED!", UVM_NONE)
          end else begin
            `uvm_error(my_name, $sformatf("CMD MISMATCHED!\nExpected:\n%s\nActual:\n%s", exp_cmd.sprint(), act_cmd.sprint()))
          end
        end
      end
      forever begin
        // Gọi get() cho cả hai FIFO. Luồng nào chưa có data thì mô phỏng sẽ tự động tạm dừng (block) ở dòng đó để chờ luồng kia.
        act_data_fifo.get(act_data);
        exp_data_fifo.get(exp_data);

        if (exp_data.compare(act_data)) begin
          `uvm_info(my_name, "DATA MATCHED!", UVM_NONE)
        end else begin
          `uvm_error(my_name, $sformatf("DATA MISMATCHED!\nExpected:\n%s\nActual:\n%s", exp_data.sprint(), act_data.sprint()))
        end
      end
    join
  endtask
endclass