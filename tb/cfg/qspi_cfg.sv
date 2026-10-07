class qspi_cfg extends uvm_object;

    `uvm_object_utils(qspi_cfg)

    string   my_name;

    rand bool_t     inject_error;
    bool_t          verbosity_control_arr[string];

    //
    // NEW
    //
    function new(string name = "");
        super.new(name);
        my_name = name;
        verbosity_control_arr["driver"]     = IS_DISABLE; // switch to enable messages for driver
        verbosity_control_arr["monitor"]    = IS_DISABLE; // switch to enable messages for monitor
        verbosity_control_arr["scoreboard"] = IS_DISABLE; // switch to enable messages for scoreboard
        verbosity_control_arr["coverage"]   = IS_DISABLE; // switch to enable messages for coverage
        verbosity_control_arr["uvm_top"]    = IS_DISABLE; // switch to enable messages for others
    endfunction


    //
    // This function is called when the following code executes
    //    obj.print()
    //
    function void do_print(uvm_printer printer);
        printer.print_field("inject_error",inject_error,$bits(inject_error));
        printer.print_field("monitor",verbosity_control_arr["monitor"],$bits(verbosity_control_arr["monitor"]));
    endfunction

    //
    // Constraint block
    //
    constraint default_config_c {
        inject_error == IS_FALSE;
    }

endclass
