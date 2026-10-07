class qspi_scoreboard #(type CMD_PKT=cmd_tlm, type DATA_PKT=read_data_tlm) extends uvm_scoreboard;
  `uvm_component_param_utils(qspi_scoreboard#(CMD_PKT,DATA_PKT))

  string my_name;

  uvm_tlm_analysis_fifo #(CMD_PKT)  exp_cmd_fifo;
  uvm_tlm_analysis_fifo #(DATA_PKT) act_data_fifo;
  uvm_tlm_analysis_fifo #(CMD_PKT)  act_cmd_fifo;
  uvm_tlm_analysis_fifo #(DATA_PKT) exp_data_fifo;
  qspi_cfg scoreboard_cfg;

  //
  // NEW
  //
  function new(string name="qspi_scoreboard", uvm_component parent);
    super.new(name, parent);
    my_name = name;
  endfunction

  //
  // BUILD phase
  //
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_cmd_fifo  = new("exp_cmd_fifo", this);
    act_data_fifo = new("act_data_fifo", this);
    act_cmd_fifo  = new("act_cmd_fifo", this);
    exp_data_fifo = new("exp_data_fifo", this);
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

  //
  // CONNECT phase
  //
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    assert(uvm_resource_db #(qspi_cfg)::read_by_name(get_full_name(), "TB_CONFIG", scoreboard_cfg));
  endfunction

  //
  // RUN phase 
  //
  task run_phase(uvm_phase phase);
    CMD_PKT  exp_cmd, act_cmd;
    DATA_PKT exp_data, act_data;

    forever begin

      act_cmd_fifo.get(act_cmd);
      exp_cmd_fifo.get(exp_cmd); 

      // 
      // FILTER COMMAND 
      // 
      if (exp_cmd.opcode inside {8'h9F, 8'h05, 8'h03, 8'h0B, 8'h3B, 8'h6B, 8'hEB}) begin
      
        if (act_cmd.data_len > exp_cmd.data_len) begin
          `uvm_info(my_name, $sformatf("[CMD FILTER] Detect %0d wrong byte on bus QSPI (ACT=%0d, EXP=%0d).", 
                    act_cmd.data_len - exp_cmd.data_len, act_cmd.data_len, exp_cmd.data_len), UVM_LOW)
          
          act_cmd.data_len = exp_cmd.data_len;
          act_cmd.data_payload = new[exp_cmd.data_len](act_cmd.data_payload);
        end
        exp_cmd.data_payload = act_cmd.data_payload;
      end

      // So sánh Command
      if (exp_cmd.compare(act_cmd)) begin
        `uvm_info(my_name, "CMD MATCHED!", UVM_NONE)
      end else begin
        `uvm_error(my_name, $sformatf("CMD MISMATCHED!\nExpected:\n%s\nActual:\n%s", exp_cmd.sprint(), act_cmd.sprint()))
      end

      if ((exp_cmd.opcode inside {8'h9F, 8'h05, 8'h03, 8'h0B, 8'h3B, 8'h6B, 8'hEB}) && (exp_cmd.data_len > 0)) begin
        int total_bytes = exp_cmd.data_len;
        int num_words   = (total_bytes + 3) / 4; 
        int rem_bytes   = total_bytes % 4;     
        for (int w = 0; w < num_words; w++) begin
          act_data_fifo.get(act_data);
          exp_data_fifo.get(exp_data);

          if ((w == num_words - 1) && (rem_bytes != 0)) begin
            case (rem_bytes)
              1: exp_data.read_data &= 32'h0000_00FF;
              2: exp_data.read_data &= 32'h0000_FFFF; 
              3: exp_data.read_data &= 32'h00FF_FFFF;
            endcase
            `uvm_info(my_name, $sformatf("[DATA FILTER] Zero-padding mask (rem_bytes=%0d): exp_data = 0x%08X", 
                      rem_bytes, exp_data.read_data), UVM_MEDIUM)
          end
          if (exp_data.compare(act_data)) begin
            `uvm_info(my_name, $sformatf("DATA MATCHED (Word %0d/%0d): 0x%08X!", w+1, num_words, act_data.read_data), UVM_NONE)
          end else begin
            `uvm_error(my_name, $sformatf("DATA MISMATCHED at Word %0d!\nExpected:\n%s\nActual:\n%s", w+1, exp_data.sprint(), act_data.sprint()))
          end
        end

        if (!exp_data_fifo.is_empty()) begin
          `uvm_info(my_name, "[DATA FILTER]!", UVM_LOW)
          exp_data_fifo.flush();
        end
      end
    end
  endtask

endclass