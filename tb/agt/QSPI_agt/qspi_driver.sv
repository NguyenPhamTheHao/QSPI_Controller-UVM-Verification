class qspi_driver extends uvm_component;

  `uvm_component_utils(qspi_driver)

  string my_name;
  virtual qspi_if vif;
  qspi_cfg        cfg;

  logic [7:0] flash_mem[0:8388607]; // Flash ao 64Mb, dia chi 24-bit
  bit wel_bit; // Write Enable Latch
  bit wip_bit; // Write In Progress

  //
  // NEW
  //
  function new(string name = "qspi_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //
  // BUILD phase
  //
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    my_name = get_name();
    if (!uvm_resource_db#(qspi_cfg)::read_by_name(get_full_name(), "TB_CONFIG", cfg)) begin
      `uvm_warning(my_name, "Khong tim thay qspi_cfg (TB_CONFIG), dung cau hinh mac dinh.")
      cfg = qspi_cfg::type_id::create("qspi_cfg_default");
    end
  endfunction

  //
  // CONNECT phase
  //

  function void connect_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual qspi_if)::get(this, "", "qspi_vif", vif)) begin
      `uvm_fatal(my_name, "Khong lay duoc virtual qspi_if tu uvm_config_db!")
    end
  endfunction

  //
  // RUN phase
  //

  task run_phase(uvm_phase phase);
    foreach (flash_mem[i]) flash_mem[i] = 8'hFF;
    wel_bit = 1'b0;
    wip_bit = 1'b0;
    release_all_lines();

    `uvm_info(my_name, "Flash Slave Model bat dau chay ...", UVM_LOW)
    forever begin
      @(negedge vif.qspi_cs_n);

      // --- inject_error = CO TONG: ~10% giao dich bi bo qua hoan toan (Timeout) ---
      if (cfg.inject_error == IS_TRUE && ($urandom_range(0, 9) == 0)) begin
        `uvm_info(my_name, "inject_error: mo phong Timeout - khong phan hoi giao dich nay", UVM_LOW)
        @(posedge vif.qspi_cs_n);
        continue;
      end

      //Ensure that release the bus for MASTER control FLASH
      release_all_lines();

      //Transaction finish right after qspi_cs_n go HIGH
      fork
        begin
          process_transaction();
        end
        begin
          @(posedge vif.qspi_cs_n);
        end
      join_any
      disable fork;
      release_all_lines();
    end
  endtask

  //-----------------------------------------------------------------
  // process_transaction: giai ma Opcode roi dieu phoi den tung handler
  //-----------------------------------------------------------------
  task automatic process_transaction();
    logic [31:0] tmp;
    logic [7:0]  opcode;
    logic [31:0] addr;

    sample_single(8, tmp);
    opcode = tmp[7:0];
    `uvm_info(my_name, $sformatf("Phat hien Opcode: 0x%02X", opcode), UVM_HIGH)

    case (opcode)
      8'h9F: respond_rdid();
      8'h05: respond_rdsr();
      8'h06: begin wel_bit = 1'b1; `uvm_info(my_name, "WREN: WEL=1", UVM_HIGH) end
      8'h04: begin wel_bit = 1'b0; `uvm_info(my_name, "WRDI: WEL=0", UVM_HIGH) end
      8'h03: begin sample_single(24, tmp); respond_read(tmp, 0, 1); end
      8'h0B: begin sample_single(24, tmp); respond_read(tmp, 8, 1); end
      8'h3B: begin sample_single(24, tmp); respond_read(tmp, 8, 2); end
      8'h6B: begin sample_single(24, tmp); respond_read(tmp, 8, 4); end
      8'hEB: begin
        sample_quad(24, tmp);
        addr = tmp;
        sample_quad(8, tmp);
        repeat (4) @(posedge vif.qspi_sclk);
        respond_read(addr, 0, 4);
      end
      8'h02: begin
        if (wel_bit) begin sample_single(24, tmp); receive_program(tmp, 1); end
        else `uvm_warning(my_name, "Page Program (0x02) bi tu choi: WEL=0")
      end
      8'h32: begin
        if (wel_bit) begin sample_single(24, tmp); receive_program(tmp, 4); end
        else `uvm_warning(my_name, "Quad Page Program (0x32) bi tu choi: WEL=0")
      end
      8'h20: if (wel_bit) begin sample_single(24, tmp); erase_region(tmp, 32'd4096); end
             else `uvm_warning(my_name, "Sector Erase (0x20) bi tu choi: WEL=0")
      8'hD8: if (wel_bit) begin sample_single(24, tmp); erase_region(tmp, 32'd65536); end
             else `uvm_warning(my_name, "Block Erase (0xD8) bi tu choi: WEL=0")
      8'hC7: if (wel_bit) erase_chip();
             else `uvm_warning(my_name, "Chip Erase (0xC7) bi tu choi: WEL=0")
      default: `uvm_error(my_name, $sformatf("Opcode khong duoc VNCHIP QSPI Controller ho tro: 0x%02X", opcode))
    endcase

    if (opcode inside {8'h02, 8'h32, 8'h20, 8'hD8, 8'hC7}) wel_bit = 1'b0;
  endtask

  //-----------------------------------------------------------------
  // Lay mau du lieu tren bus (MOSI = io0, single/quad lane)
  //-----------------------------------------------------------------
  task automatic sample_single(input int nbits, output logic [31:0] val);
    val = '0;
    repeat (nbits) begin
      @(posedge vif.qspi_sclk);
      val = {val[30:0], vif.qspi_io0};
    end
  endtask

  task automatic sample_quad(input int nbits, output logic [31:0] val);
    val = '0;
    repeat (nbits / 4) begin
      @(posedge vif.qspi_sclk);
      val = {val[27:0], vif.qspi_io3, vif.qspi_io2, vif.qspi_io1, vif.qspi_io0};
    end
  endtask

  //-----------------------------------------------------------------
  // respond_read: doi dummy cycle, lai du lieu ra theo so lane.
  // inject_error = CO TONG: ~5%/byte bi "khong kip day du lieu" (RX stall
  // tu goc nhin Controller) khi co nay bat.
  //-----------------------------------------------------------------
  task automatic respond_read(input logic [31:0] start_addr, input int dummy_cycles, input int lanes);
    logic [23:0] cur_addr;
    byte data_byte;
    int nedges;
    cur_addr = start_addr[23:0];
    repeat (dummy_cycles) @(posedge vif.qspi_sclk);
    drive_enable(lanes, 1'b1);
    while (!vif.qspi_cs_n) begin
      if (cfg.inject_error == IS_TRUE && ($urandom_range(0, 19) == 0)) begin
        @(negedge vif.qspi_sclk);
        continue;
      end
      data_byte = flash_mem[cur_addr];
      nedges = 8 / lanes;
      for (int e = 0; e < nedges; e++) begin
        @(negedge vif.qspi_sclk);
        // Be rong cua toan tu -: BAT BUOC la hang so -> tach case theo lanes
        case (lanes)
          1: drive_bits(1, data_byte[7 - e]);
          2: drive_bits(2, data_byte[7 - 2*e -: 2]);
          4: drive_bits(4, data_byte[7 - 4*e -: 4]);
        endcase
      end
      cur_addr++;
    end
    drive_enable(lanes, 1'b0);
  endtask

  task automatic drive_enable(input int lanes, input bit en);
    case (lanes)
      1: vif.io1_oe <= en;
      2: begin vif.io1_oe <= en; vif.io0_oe <= en; end
      4: begin vif.io3_oe <= en; vif.io2_oe <= en; vif.io1_oe <= en; vif.io0_oe <= en; end
    endcase
  endtask

  task automatic drive_bits(input int lanes, input logic [3:0] bits);
    case (lanes)
      1: vif.io1_out <= bits[0];
      2: begin vif.io1_out <= bits[1]; vif.io0_out <= bits[0]; end
      4: begin vif.io3_out <= bits[3]; vif.io2_out <= bits[2]; vif.io1_out <= bits[1]; vif.io0_out <= bits[0]; end
    endcase
  endtask

  //-----------------------------------------------------------------
  // respond_rdid / respond_rdsr
  //-----------------------------------------------------------------
  task automatic respond_rdid();
    byte id_bytes[3] = '{8'hC2, 8'h20, 8'h17};
    drive_enable(1, 1'b1);
    foreach (id_bytes[b]) begin
      for (int i = 7; i >= 0; i--) begin
        @(negedge vif.qspi_sclk);
        drive_bits(1, id_bytes[b][i]);
      end
    end
    drive_enable(1, 1'b0);
  endtask

  task automatic respond_rdsr();
    byte status_byte;
    status_byte = {6'b0, wel_bit, wip_bit};
    drive_enable(1, 1'b1);
    while (!vif.qspi_cs_n) begin
      for (int i = 7; i >= 0; i--) begin
        @(negedge vif.qspi_sclk);
        drive_bits(1, status_byte[i]);
      end
    end
    drive_enable(1, 1'b0);
  endtask

  //-----------------------------------------------------------------
  // receive_program: nhan du lieu tu Controller, ghi vao flash_mem.
  // inject_error = CO TONG: ~5%/byte "khong nhan" du lieu (TX stall tu
  // goc nhin Controller) khi co nay bat.
  //-----------------------------------------------------------------
  task automatic receive_program(input logic [31:0] start_addr, input int lanes);
    logic [23:0] cur_addr;
    byte rx_byte;
    int nedges;
    cur_addr = start_addr[23:0];
    wip_bit = 1'b1;
    while (!vif.qspi_cs_n) begin
      if (cfg.inject_error == IS_TRUE && ($urandom_range(0, 19) == 0)) begin
        @(posedge vif.qspi_sclk);
        continue;
      end
      nedges = 8 / lanes;
      rx_byte = 8'h00;
      for (int e = 0; e < nedges; e++) begin
        @(posedge vif.qspi_sclk);
        case (lanes)
          1: rx_byte = {rx_byte[6:0], vif.qspi_io0};
          4: rx_byte = {rx_byte[3:0], vif.qspi_io3, vif.qspi_io2, vif.qspi_io1, vif.qspi_io0};
          default: rx_byte = {rx_byte[6:0], vif.qspi_io0};
        endcase
      end
      flash_mem[cur_addr] = rx_byte;
      cur_addr++;
    end
    wip_bit = 1'b0;
  endtask

  //-----------------------------------------------------------------
  // erase_region / erase_chip
  //-----------------------------------------------------------------
  task automatic erase_region(input logic [31:0] addr, input int region_size);
  logic [23:0] base_addr;
  base_addr = (addr[23:0] / region_size) * region_size;
  wip_bit = 1'b1;
  for (int i = 0; i < region_size; i++) flash_mem[base_addr + i] = 8'hFF;
  wip_bit = 1'b0;
  `uvm_info(my_name, $sformatf("Erase vung [0x%06X : 0x%06X]", base_addr, base_addr + region_size - 1), UVM_MEDIUM)
endtask

task automatic erase_chip();
  wip_bit = 1'b1;
  foreach (flash_mem[i]) flash_mem[i] = 8'hFF;
  wip_bit = 1'b0;
  `uvm_info(my_name, "Chip Erase hoan tat (toan bo 64Mb)", UVM_MEDIUM)
endtask

function void release_all_lines();
  vif.io0_oe <= 1'b0; vif.io1_oe <= 1'b0; vif.io2_oe <= 1'b0; vif.io3_oe <= 1'b0;
endfunction

endclass