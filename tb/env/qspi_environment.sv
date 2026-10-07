class qspi_environment extends uvm_environment;
    `uvm_component_utils(qspi_environment)

    string my_name;
    
    typedef apb_agent apb_agent_t;
    typedef qspi_agent qspi_agent_t;
    typedef qspi_scoreboard qspi_scoreboard_t;

    //Instatiate
    apb_agent_t apb_agent_0;
    qspi_agent_t qspi_agent_0;
    qspi_scoreboard_t scoreboard_0;

    //
    //NEW
    //
    function new(string name="qspi_environment", uvm_component parent);
        super.new(name,parent);
    endfunction

    //
    //BUILD
    //
    function build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_agent_0=apb_agent_t::type_id::create("apb_agent_0",this);
        qspi_agent_0=qspi_agent_t::type_id::create("qspi_agent_0",this);
        scoreboard_0=qspi_scoreboard_t::type_id::create("scoreboard_0",this);
    endfunction

    //
    //CONNECT
    //
    function connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        apb_agent_0.act_data_port.connect(scoreboard_0.act_data_fifo.analysis_export);
        apb_agent_0.exp_cmd_port.connect(scoreboard_0.exp_cmd_fifo.analysis_export);
        //Todo: Connect exp_data_fifo, act_cmd_fifo with their source port form QSPI Monitor
        qspi_agent_0.exp_data_port.connect(scoreboard_0.exp_data_fifo.analysis_export);
        qspi_agent_0.act_cmd_port.connect(scoreboard_0.act_cmd_fifo.analysis_export);
    endfunction
endclass

