interface qspi_if();
  // Controller to External Flash
  logic qspi_sclk;
  logic qspi_cs_n;

  // Virtual Pull-up resistors
  tri1  qspi_io0;
  tri1  qspi_io1;
  tri1  qspi_io2;
  tri1  qspi_io3;

  // --- Bổ sung cho QSPI_agt (Flash Slave Model) lái bus ---
  logic io0_oe, io1_oe, io2_oe, io3_oe;
  logic io0_out, io1_out, io2_out, io3_out;

  assign qspi_io0 = io0_oe ? io0_out : 1'bz;
  assign qspi_io1 = io1_oe ? io1_out : 1'bz;
  assign qspi_io2 = io2_oe ? io2_out : 1'bz;
  assign qspi_io3 = io3_oe ? io3_out : 1'bz;

endinterface