`timescale 1ns / 1ps

module tb_i2c_master_fsm;

    // --- Signals ---
    reg  clk;
    reg  resetn;
    
    reg  i2c_en;
    reg  mode_master;
    reg  api_start;
    reg  api_stop_req;
    reg  api_reload_en;
    reg  api_continue;
    reg  api_rw;
    reg  [6:0] api_slave_addr;
    reg  [7:0] api_len;
    
    wire api_busy;
    wire api_arb_lost;
    wire api_done;
    wire api_reload_req;
    wire api_nack_err;
    wire api_addr_phase;
    wire [3:0] api_state_out;
    
    reg  fifo_tx_empty;
    wire fifo_tx_rd_en;
    reg  fifo_rx_full;
    wire fifo_rx_wr_en;
    
    reg  ctrl_byte_done;
    reg  ctrl_sda_sampled;
    reg  ctrl_arb_lost;
    wire ctrl_en;
    wire ctrl_is_read;
    wire ctrl_load;
    wire ctrl_ack_phase;
    
    reg  phy_start_done;
    reg  phy_stop_done;
    reg  phy_scl_in;
    wire phy_gen_start;
    wire phy_gen_stop;
    
    wire scl_oe;
    wire scl_out;

    // --- Instantiate FSM ---
    i2c_master_fsm u_fsm (
        .clk(clk), .resetn(resetn),
        .i2c_en(i2c_en), .mode_master(mode_master),
        .api_start(api_start), .api_stop_req(api_stop_req),
        .api_reload_en(api_reload_en), .api_continue(api_continue),
        .api_rw(api_rw), .api_slave_addr(api_slave_addr), .api_len(api_len),
        .api_busy(api_busy), .api_arb_lost(api_arb_lost),
        .api_done(api_done), .api_reload_req(api_reload_req),
        .api_nack_err(api_nack_err), .api_addr_phase(api_addr_phase),
        .api_state_out(api_state_out),
        .fifo_tx_empty(fifo_tx_empty), .fifo_tx_rd_en(fifo_tx_rd_en),
        .fifo_rx_full(fifo_rx_full), .fifo_rx_wr_en(fifo_rx_wr_en),
        .ctrl_byte_done(ctrl_byte_done), .ctrl_sda_sampled(ctrl_sda_sampled),
        .ctrl_arb_lost(ctrl_arb_lost), .ctrl_en(ctrl_en),
        .ctrl_is_read(ctrl_is_read), .ctrl_load(ctrl_load),
        .ctrl_ack_phase(ctrl_ack_phase),
        .phy_start_done(phy_start_done), .phy_stop_done(phy_stop_done),
        .phy_scl_in(phy_scl_in), .phy_gen_start(phy_gen_start),
        .phy_gen_stop(phy_gen_stop),
        .scl_oe(scl_oe), .scl_out(scl_out)
    );

    // --- Clock Generation ---
    initial begin clk = 0; forever #10 clk = ~clk; end

    // --- Helper Tasks ---
    task assert_state(input [3:0] expected, input [100*8:1] label);
        begin
            if (api_state_out !== expected) begin
                $display("[%0t ns] ❌ [FAIL] %s | Exp: %0d, Got: %0d", $time, label, expected, api_state_out);
            end else begin
                $display("[%0t ns] ✅ [PASS] %s (State %0d)", $time, label, api_state_out);
            end
        end
    endtask

    task assert_val(input exp, input act, input [80*8:1] msg);
        if (exp !== act) $display("   ❌ [SIGNAL ERROR] %s | Exp: %b, Got: %b", msg, exp, act);
        else             $display("   ✅ [SIGNAL PASS] %s", msg);
    endtask

    // --- Main Test ---
    initial begin
        // Initialize
        resetn = 0; i2c_en = 1; mode_master = 1;
        api_start = 0; api_stop_req = 0; api_reload_en = 0; api_continue = 0;
        api_rw = 0; api_slave_addr = 7'h50; api_len = 8'd1;
        fifo_tx_empty = 1; fifo_rx_full = 0;
        ctrl_byte_done = 0; ctrl_sda_sampled = 0; ctrl_arb_lost = 0;
        phy_start_done = 0; phy_stop_done = 0; phy_scl_in = 1;
        
        $display("\n=======================================================");
        $display(" 🧠 I2C MASTER FSM UNIT TEST (STEP-BY-STEP)");
        $display("=======================================================\n");

        #100 resetn = 1;
        #20 assert_state(0, "Should be in M_IDLE");

        // ----------------------------------------------------
        // SCENARIO 1: WRITE TRANSACTION (Start -> Addr -> Data -> Stop)
        // ----------------------------------------------------
        $display("\n--- SCENARIO 1: Master Write 1 Byte ---");
        api_start = 1; api_rw = 0; fifo_tx_empty = 0; api_stop_req = 1; api_len = 1;
        @(posedge clk); #2; assert_state(1, "After Start: Move to M_START_GEN");
        api_start = 0;
        
        phy_start_done = 1;
        @(posedge clk); #2; assert_state(2, "Move to M_TX_ADDR_LOAD");
        phy_start_done = 0;
        
        @(posedge clk); #2; assert_state(3, "Move to M_TX_ADDR");

        // จำลองการส่ง Address
        ctrl_byte_done = 1; ctrl_sda_sampled = 0; // ACK
        @(posedge clk); ctrl_byte_done = 0;
        #2; assert_state(4, "Move to M_TX_DATA_WAIT");

        // จำลองมีข้อมูลใน FIFO (fifo_tx_empty = 0)
        @(posedge clk); #2; assert_state(5, "Move to M_TX_DATA_PREF");
        assert_val(1'b1, fifo_tx_rd_en, "Should pulse TX_RD_EN");

        @(posedge clk); #2; assert_state(6, "Move to M_TX_DATA");
        
        ctrl_byte_done = 1; ctrl_sda_sampled = 0; // ACK
        @(posedge clk); ctrl_byte_done = 0;
        #2; assert_state(9, "Move to M_CHECK_LEN");

        // Length = 1, Byte count = 1. Stop = 1 -> M_STOP_GEN
        @(posedge clk); #2; assert_state(13, "Move to M_STOP_GEN");

        phy_stop_done = 1;
        @(posedge clk); #2; assert_state(0, "After Stop Done: Back to M_IDLE");
        phy_stop_done = 0;

        // ----------------------------------------------------
        // SCENARIO 2: REPEATED START
        // ----------------------------------------------------
        $display("\n--- SCENARIO 2: Repeated Start (Stop = 0) ---");
        api_start = 1; api_rw = 0; fifo_tx_empty = 0; api_stop_req = 0; api_len = 1;
        @(posedge clk); #2; 
        api_start = 0; phy_start_done = 1;
        @(posedge clk); phy_start_done = 0;
        @(posedge clk); // M_TX_ADDR_LOAD
        @(posedge clk); // M_TX_ADDR
        ctrl_byte_done = 1; ctrl_sda_sampled = 0;
        @(posedge clk); ctrl_byte_done = 0;
        @(posedge clk); // M_TX_DATA_WAIT
        @(posedge clk); // M_TX_DATA_PREF
        @(posedge clk); // M_TX_DATA
        ctrl_byte_done = 1; ctrl_sda_sampled = 0;
        @(posedge clk); ctrl_byte_done = 0;
        #2; assert_state(9, "Move to M_CHECK_LEN");
        
        @(posedge clk); #2; assert_state(11, "Move to M_REP_START_WAIT (since stop=0)");
        assert_val(1'b1, scl_oe, "Should stretch SCL in M_REP_START_WAIT");
        
        api_start = 1;
        @(posedge clk); #2; assert_state(12, "Move to M_REP_START_GEN");
        api_start = 0;
        
        phy_start_done = 1;
        @(posedge clk); phy_start_done = 0;
        @(posedge clk); #2; assert_state(3, "Move to M_TX_ADDR");
        
        // Stop it
        api_stop_req = 1;
        ctrl_byte_done = 1; ctrl_sda_sampled = 0;
        @(posedge clk); ctrl_byte_done = 0;
        @(posedge clk); // WAIT
        @(posedge clk); // PREF
        @(posedge clk); // DATA
        ctrl_byte_done = 1; ctrl_sda_sampled = 0;
        @(posedge clk); ctrl_byte_done = 0;
        @(posedge clk); // CHECK_LEN
        @(posedge clk); // STOP
        phy_stop_done = 1;
        @(posedge clk); phy_stop_done = 0;
        
        $display("\n=======================================================");
        $display(" 🎉 FSM UNIT TEST COMPLETED!");
        $display("=======================================================\n");
        $finish;
    end

endmodule