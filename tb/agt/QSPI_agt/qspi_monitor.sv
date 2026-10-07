class qspi_monitor #(type CMD_PKT=uvm_sequence_item, type DATA_PKT=uvm_sequence_item) extends uvm_monitor;

  `uvm_component_param_utils(qspi_monitor#(CMD_PKT, DATA_PKT))

  string my_name;

  virtual qspi_if vif;
  qspi_cfg        monitor_cfg;

  // Thay the qspi_act_port bang 2 port phan tach
  uvm_analysis_port #(CMD_PKT) act_cmd_port;
  uvm_analysis_port #(DATA_PKT) exp_data_port;

  //
  // NEW
  //
  function new(string name = "qspi_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //
  // BUILD phase
  //
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    my_name       = get_name();

    // Khoi tao cac port
    act_cmd_port  = new("act_cmd_port", this);
    exp_data_port = new("exp_data_port", this);

  //Check for interface
    if (!uvm_config_db#(virtual qspi_if)::get(this, "", "qspi_vif", vif)) begin

    end
  endfunction

  // ... (connect_phase va run_phase giu nguyen) ...
  //
  // CONNECT phase
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

  //
  // RUN phase
  //
  task run_phase(uvm_phase phase);
    forever begin
      @(negedge vif.qspi_cs_n);
      collect_transaction();
    end
  endtask

  //-----------------------------------------------------------------
  // collect_transaction: giai ma 1 giao dich, ban ra cac port tuong ung
  //-----------------------------------------------------------------
  task automatic collect_transaction();
    CMD_PKT      act_cmd_tr;
    logic [31:0] tmp;
    logic [7:0]  opcode;
    logic [31:0] addr;
    byte         q[$];
    int          dummy_cyc;
    bit          is_read_op;

    act_cmd_tr = CMD_PKT::type_id::create("act_cmd_tr");
    addr = 32'h0;
    dummy_cyc = 0;
    is_read_op = 0;

    sample_master_bits(8, 1, tmp);
    opcode    = tmp[7:0];
    act_cmd_tr.opcode = opcode;

    // Giai ma giao dich giong y het phien ban cu
    case (opcode)
      8'h9F, 8'h05: begin
        is_read_op = 1'b1;
        collect_slave_bytes(1, q);
      end

      8'h06, 8'h04: begin
        is_read_op = 1'b0;
      end

      8'h03: begin is_read_op=1; sample_master_bits(24,1,tmp); addr=tmp; dummy_cyc=0; collect_slave_bytes(1,q); end
      8'h0B: begin is_read_op=1; sample_master_bits(24,1,tmp); addr=tmp; skip_dummy(8); dummy_cyc=8; collect_slave_bytes(1,q); end
      8'h3B: begin is_read_op=1; sample_master_bits(24,1,tmp); addr=tmp; skip_dummy(8); dummy_cyc=8; collect_slave_bytes(2,q); end
      8'h6B: begin is_read_op=1; sample_master_bits(24,1,tmp); addr=tmp; skip_dummy(8); dummy_cyc=8; collect_slave_bytes(4,q); end
      8'hEB: begin
        is_read_op=1;
        sample_master_bits(24,4,tmp); addr=tmp;
        sample_master_bits(8,4,tmp);
        skip_dummy(4);
        dummy_cyc = 4;
        collect_slave_bytes(4,q);
      end

      8'h02: begin is_read_op=0; sample_master_bits(24,1,tmp); addr=tmp; collect_master_bytes(1,q); end
      8'h32: begin is_read_op=0; sample_master_bits(24,1,tmp); addr=tmp; collect_master_bytes(4,q); end

      8'h20, 8'hD8: begin is_read_op=0; sample_master_bits(24,1,tmp); addr=tmp; end
      8'hC7: begin is_read_op=0; end

      default: `uvm_error(my_name, $sformatf("Quan sat duoc opcode khong xac dinh: 0x%02X", opcode))
    endcase

    // 1. DONG GOI VA GUI CMD_PKT (Chup lai lenh thucte gui ra tu DUT)
    act_cmd_tr.address      = addr;
    act_cmd_tr.dummy_cycles = dummy_cyc;
    act_cmd_tr.data_len     = q.size();
    act_cmd_tr.data_payload = new[q.size()];
    foreach (q[i]) act_cmd_tr.data_payload[i] = q[i];

    `uvm_info(my_name, $sformatf("ACT CMD CAPTURED: opcode=0x%02X addr=0x%08X len=%0d", opcode, addr, q.size()), UVM_HIGH)
    act_cmd_port.write(act_cmd_tr);

    // 2. DONG GOI VA GUI DATA_PKT (Neu la lenh Read, lay du lieu Flash phan hoi lam Expected Data)
    if (is_read_op && q.size() > 0) begin
      // Thanh ghi RX_REG trong APB rong 32-bit (4 bytes)
      // Chung ta can gom 4 byte vao 1 goi read_data_tlm de khop voi APB Monitor
      int byte_idx = 0;
      while (byte_idx < q.size()) begin
        DATA_PKT exp_data_tr;
        exp_data_tr = DATA_PKT::type_id::create("exp_data_tr");
        exp_data_tr.read_data = 32'h0;

        // Gom toi da 4 byte vao 1 tu 32-bit
        for (int i=0; i<4; i++) begin
          if (byte_idx < q.size()) begin
            // Luu y: APB read data thuong duoc sap xep theo Little-Endian,
            // ban co the can dieu chinh phep dich bit nay cho khop voi RTL.
            exp_data_tr.read_data = exp_data_tr.read_data | (q[byte_idx] << (i*8));
            byte_idx++;
          end
        end

        `uvm_info(my_name, $sformatf("EXP DATA CAPTURED: read_data=0x%08X", exp_data_tr.read_data), UVM_HIGH)
        exp_data_port.write(exp_data_tr);
      end
    end

  endtask

  //-----------------------------------------------------------------
  task automatic sample_master_bits(input int nbits, input int lanes, output logic [31:0] val);
    val = '0;
    if (lanes == 1) begin
      repeat (nbits) begin
        @(posedge vif.qspi_sclk);
        val = {val[30:0], vif.qspi_io0};
      end
    end else begin
      repeat (nbits/4) begin
        @(posedge vif.qspi_sclk);
        val = {val[27:0], vif.qspi_io3, vif.qspi_io2, vif.qspi_io1, vif.qspi_io0};
      end
    end
  endtask

  task automatic skip_dummy(input int cycles);
    repeat (cycles) @(posedge vif.qspi_sclk);
  endtask

  task automatic collect_slave_bytes(input int lanes, output byte q[$]);
    byte b;
    int  nedges;
    q.delete();
    nedges = 8 / lanes;
    while (!vif.qspi_cs_n) begin
      b = 8'h00;
      for (int e = 0; e < nedges; e++) begin
        @(posedge vif.qspi_sclk or posedge vif.qspi_cs_n);
        if(vif.qspi_cs_n==1) break;
        case (lanes)
          1: b = {b[6:0], vif.qspi_io1};
          2: b = {b[5:0], vif.qspi_io1, vif.qspi_io0};
          4: b = {b[3:0], vif.qspi_io3, vif.qspi_io2, vif.qspi_io1, vif.qspi_io0};
        endcase
      end
      if(vif.qspi_cs_n!=1'b1) q.push_back(b);
    end
  endtask

  task automatic collect_master_bytes(input int lanes, output byte q[$]);
    byte b;
    int  nedges;
    q.delete();
    nedges = 8 / lanes;
    while (!vif.qspi_cs_n) begin
      b = 8'h00;
      for (int e = 0; e < nedges; e++) begin
        @(posedge vif.qspi_sclk);
        case (lanes)
          1: b = {b[6:0], vif.qspi_io0};
          4: b = {b[3:0], vif.qspi_io3, vif.qspi_io2, vif.qspi_io1, vif.qspi_io0};
        endcase
      end
      q.push_back(b);
    end
  endtask
endclass