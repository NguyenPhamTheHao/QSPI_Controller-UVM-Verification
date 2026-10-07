class pio_fast_read_0b_4bytes_test extends base_test;

  `uvm_component_utils(pio_fast_read_0b_4bytes_test)
  typedef pio_fast_read_0b_4bytes_seq #(apb_tlm, apb_tlm) pio_fast_read_0b_4bytes_seq_t;
  pio_fast_read_0b_4bytes_seq_t pio_fast_read_0b_4bytes_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    qspi_cfg test_cfg;
    super.build_phase(phase);
    pio_fast_read_0b_4bytes_seq = pio_fast_read_0b_4bytes_seq_t::type_id::create("pio_fast_read_0b_4bytes_seq");

    if (!uvm_config_db#(qspi_cfg)::get(this, "", "TB_CONFIG", test_cfg)) begin
      `uvm_fatal("GET_CFG", "Cannot get TB_CONFIG in testcase")
    end
    test_cfg.verbosity_control_arr["monitor"] = IS_ENABLE;
    test_cfg.verbosity_control_arr["driver"] = IS_ENABLE;
    test_cfg.verbosity_control_arr["uvm_top"] = IS_ENABLE;

  endfunction

  task run_phase(uvm_phase phase);
    phase.phase_done.set_drain_time(this, DRAIN_TIME);
    phase.raise_objection(this, "Objection raised by PIO Fast Read Test");
    `uvm_info(get_type_name(), "Starting PIO Fast Read Sequence", UVM_LOW)
    pio_fast_read_0b_4bytes_seq.start(env_h.apb_agent_0.sequencer);
    phase.drop_objection(this, "Objection dropped by PIO Fast Read Test");
  endtask
endclass