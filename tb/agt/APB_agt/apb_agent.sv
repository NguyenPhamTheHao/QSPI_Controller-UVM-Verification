// APB agent: owns the UVM components used to send and observe APB transfers.
// A test starts an APB sequence on this agent's sequencer. The sequencer passes
// each apb_tlm item to the driver, which performs the bus transfer. The monitor
// observes completed bus transfers and publishes them through apb_act_port.
class apb_agent #(type REQ = apb_tlm, type CMD_PKT = cmd_tlm, type DATA_PKT=read_data_tlm) extends uvm_agent;
    `uvm_component_param_utils(apb_agent #(REQ,CMD_PKT))
    typedef apb_driver  #(REQ)   apb_driver_t;
    typedef apb_monitor #(REQ,CMD_PKT,DATA_PKT)  apb_monitor_t;
    typedef uvm_sequencer #(REQ) apb_sequencer_t;
    string   my_name;
    apb_driver_t driver;
    apb_monitor_t monitor;
    apb_sequencer_t sequencer;

    //Connect this port to exp_cmd_fifo of Scoreboard in Evinronment layer
    uvm_analysis_port #(CMD_PKT) exp_cmd_port;

    //Connect this port to act_data_fifo of Scoreboard in Environment layer
    uvm_analysis_port #(DATA_PKT) act_data_port
    //
    //NEW
    //
    function new(string name = "apb_agent", uvm_component parent = null);
        super.new(name,parent);
        my_name=name;
    endfunction

    //
    //BUILD
    //
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (is_active == UVM_ACTIVE) begin
            driver    =apb_driver_t::type_id::create("apb_driver",this);
            sequencer =apb_sequencer_t::type_id::create("apb_sequencer",this);
        end
        monitor   =apb_monitor_t::type_id::create("apb_monitor",this);
        exp_cmd_port = new("exp_cmd_port",this);
        act_data_port= new("act_data_port",this);
    endfunction

    //
    //CONNECT
    //
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.act_data_port.connect(this.act_data_port);
        monitor.exp_cmd_port.connect(this.exp_cmd_port);
        if (is_active == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass