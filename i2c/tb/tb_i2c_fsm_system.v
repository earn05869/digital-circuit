`timescale 1ns / 1ps
// ============================================================
//  tb_i2c_fsm_system
//  ─────────────────
//  Integrated testbench: FSM + bit_ctrl + start_stop +
//  glitch_filter + io_pad on a shared open-drain I2C bus.
//
//  Master side:
//    i2c_master_fsm  ← controls everything
//    i2c_clk_gen     ← generates SCL
//    i2c_start_stop  ← generates START/STOP conditions
//    i2c_bit_ctrl    ← shifts data bits
//    i2c_io_pad x2   ← SDA and SCL physical pads
//    i2c_glitch_filter x2 ← filters SDA and SCL
//
//  Slave side:
//    i2c_slave_fsm   ← slave state machine
//    i2c_start_stop  ← detects START/STOP from the bus
//    i2c_bit_ctrl    ← shifts data bits
//    i2c_io_pad x2   ← SDA and SCL pads
//    i2c_glitch_filter x2 ← filters SDA and SCL
// ============================================================
module tb_i2c_fsm_system;

// ============================================================
// 1. System Clock & Reset
// ============================================================
reg clk;
reg resetn;

initial begin
    clk = 0;
    #3;
    forever #10 clk = ~clk;   // 50 MHz system clock (period = 20 ns)
end

// ============================================================
// 2. Open-Drain I2C Bus
//    Passive pull-ups + multiple open-drain drivers
// ============================================================
wire sda_bus;
wire scl_bus;

assign (pull1, highz0) sda_bus = 1'b1;   // pull-up
assign (pull1, highz0) scl_bus = 1'b1;   // pull-up

// ============================================================
// 3. MASTER — all wires declared up-front
// ============================================================

// --- API / Control ---
reg        m_api_start, m_api_stop_req, m_api_reload_en, m_api_continue;
reg        m_api_rw;
reg  [6:0] m_api_slave_addr;
reg  [7:0] m_api_len;
reg        m_fifo_tx_empty, m_fifo_rx_full;
reg  [7:0] m_tx_data_reg;   // byte fed to bit_ctrl for data phase

wire       m_api_busy, m_api_arb_lost, m_api_done, m_api_reload_req;
wire       m_api_nack_err, m_api_addr_phase;
wire [3:0] m_api_state;

// --- FSM → bit_ctrl ---
wire       m_ctrl_en, m_ctrl_is_read, m_ctrl_load, m_ctrl_ack_phase;

// --- FSM → start_stop ---
wire       m_phy_gen_start, m_phy_gen_stop;

// --- FSM SCL stretch ---
wire       m_fsm_scl_oe, m_fsm_scl_out;

// --- bit_ctrl → FSM ---
wire       m_byte_done, m_rx_ack, m_arb_lost_bc;
wire [7:0] m_rx_data_bc;

// --- start_stop outputs ---
wire       m_ss_sda_out, m_ss_sda_oe, m_ss_done;

// --- start/stop done routing ---
reg        m_was_start;   // 1 = last request was START
always @(posedge clk or negedge resetn) begin
    if      (!resetn)        m_was_start <= 1'b0;
    else if (m_phy_gen_start) m_was_start <= 1'b1;
    else if (m_phy_gen_stop)  m_was_start <= 1'b0;
end
wire m_start_done = m_ss_done &  m_was_start;
wire m_stop_done  = m_ss_done & ~m_was_start;

// --- Address byte MUX ---
// During address phase, load {slave_addr, rw} ; otherwise load data byte
wire [7:0] m_bc_tx_data = m_api_addr_phase ? {m_api_slave_addr, m_api_rw} : m_tx_data_reg;

// --- bit_ctrl SDA pads ---
wire       m_bc_sda_oe, m_bc_sda_out;

// --- Filtered signals ---
wire       m_sda_raw, m_sda_filtered;
wire       m_scl_raw, m_scl_filtered;

// --- SDA MUX: start_stop has priority during START/STOP generation ---
wire m_sda_drive_oe  = m_ss_sda_oe  | m_bc_sda_oe;
wire m_sda_drive_out = m_ss_sda_oe  ? m_ss_sda_out : m_bc_sda_out;

// --- SCL: from clk_gen, OR master stretches SCL ---
wire m_scl_gen_out;
wire m_clkgen_en = m_ctrl_en | m_phy_gen_start | m_phy_gen_stop;

// SCL open-drain: clk_gen drives SCL low/high; FSM can stretch (hold low)
assign scl_bus = (!m_scl_gen_out)          ? 1'b0 : 1'bz;  // clk_gen
assign scl_bus = (m_fsm_scl_oe && !m_fsm_scl_out) ? 1'b0 : 1'bz;  // stretch

// Gate bit_ctrl enable until SDA is released after START
// (avoids spurious arb_lost when SDA is still low from start_stop)
wire m_bc_enable = m_ctrl_en & m_sda_filtered;

// --- Master instances ---

i2c_clk_gen u_m_clk_gen (
    .clk         (clk),
    .resetn      (resetn),
    .en          (m_clkgen_en),
    .prescaler   (16'd10),       // SCL = 50MHz / (4*10) = 1.25 MHz
    .scl_out     (m_scl_gen_out),
    .phase_setup  (),
    .phase_sample ()
);

i2c_io_pad u_m_scl_pad (
    .clk           (clk),
    .resetn        (resetn),
    .tx_data       (m_scl_gen_out),
    .output_enable (1'b1),        // master always owns SCL
    .rx_data       (m_scl_raw),
    .sda           (scl_bus)
);

i2c_glitch_filter #(.THRESHOLD(3)) u_m_scl_filt (
    .clk         (clk),
    .resetn      (resetn),
    .raw_in      (m_scl_raw),
    .filtered_out(m_scl_filtered)
);

i2c_io_pad u_m_sda_pad (
    .clk           (clk),
    .resetn        (resetn),
    .tx_data       (m_sda_drive_out),
    .output_enable (m_sda_drive_oe),
    .rx_data       (m_sda_raw),
    .sda           (sda_bus)
);

i2c_glitch_filter #(.THRESHOLD(3)) u_m_sda_filt (
    .clk         (clk),
    .resetn      (resetn),
    .raw_in      (m_sda_raw),
    .filtered_out(m_sda_filtered)
);

i2c_start_stop u_m_start_stop (
    .clk       (clk),
    .resetn    (resetn),
    .gen_start (m_phy_gen_start),
    .gen_stop  (m_phy_gen_stop),
    .scl_in    (m_scl_filtered),
    .sda_in    (m_sda_filtered),
    .sda_out   (m_ss_sda_out),
    .sda_oe    (m_ss_sda_oe),
    .start_det (),
    .stop_det  (),
    .done      (m_ss_done)
);

i2c_bit_ctrl u_master_bc (
    .clk       (clk),
    .resetn    (resetn),
    .enable    (m_bc_enable),
    .is_read   (m_ctrl_is_read),
    .ack_phase (m_ctrl_ack_phase),
    .load      (m_ctrl_load),
    .tx_data   (m_bc_tx_data),
    .rx_data   (m_rx_data_bc),
    .rx_ack    (m_rx_ack),
    .byte_done (m_byte_done),
    .arb_lost  (m_arb_lost_bc),
    .sda_oe    (m_bc_sda_oe),
    .sda_out   (m_bc_sda_out),
    .scl_in    (m_scl_filtered),
    .sda_in    (m_sda_filtered)
);

i2c_master_fsm u_master_fsm (
    .clk              (clk),
    .resetn           (resetn),
    .i2c_en           (1'b1),
    .mode_master      (1'b1),
    .api_start        (m_api_start),
    .api_stop_req     (m_api_stop_req),
    .api_reload_en    (m_api_reload_en),
    .api_continue     (m_api_continue),
    .api_rw           (m_api_rw),
    .api_slave_addr   (m_api_slave_addr),
    .api_len          (m_api_len),
    .api_busy         (m_api_busy),
    .api_arb_lost     (m_api_arb_lost),
    .api_done         (m_api_done),
    .api_reload_req   (m_api_reload_req),
    .api_nack_err     (m_api_nack_err),
    .api_addr_phase   (m_api_addr_phase),
    .api_state_out    (m_api_state),
    .fifo_tx_empty    (m_fifo_tx_empty),
    .fifo_tx_rd_en    (),
    .fifo_rx_full     (m_fifo_rx_full),
    .fifo_rx_wr_en    (),
    .ctrl_byte_done   (m_byte_done),
    .ctrl_sda_sampled (m_rx_ack),
    .ctrl_arb_lost    (m_arb_lost_bc),
    .ctrl_en          (m_ctrl_en),
    .ctrl_is_read     (m_ctrl_is_read),
    .ctrl_load        (m_ctrl_load),
    .ctrl_ack_phase   (m_ctrl_ack_phase),
    .phy_start_done   (m_start_done),
    .phy_stop_done    (m_stop_done),
    .phy_scl_in       (m_scl_filtered),
    .phy_gen_start    (m_phy_gen_start),
    .phy_gen_stop     (m_phy_gen_stop),
    .scl_oe           (m_fsm_scl_oe),
    .scl_out          (m_fsm_scl_out)
);

// ============================================================
// 4. SLAVE — all wires declared up-front
// ============================================================

// --- Slave pad/filter wires ---
wire       s_sda_raw, s_sda_filtered;
wire       s_scl_raw, s_scl_filtered;

// --- Slave start_stop ---
wire       s_start_det, s_stop_det;

// --- Slave FSM outputs ---
wire       s_fsm_bit_ctrl_en, s_fsm_load, s_fsm_tx_rd_en, s_fsm_rx_wr_en;
wire       s_fsm_sda_oe, s_fsm_sda_out;
wire       s_fsm_scl_oe, s_fsm_scl_out;
wire       s_addr_match, s_busy, s_api_done, s_ack_phase;

// --- Slave bit_ctrl wires ---
wire       s_byte_done, s_bc_rx_ack;
wire [7:0] s_rx_data_bc;
wire       s_arb_lost_bc;
wire       s_bc_sda_oe, s_bc_sda_out;

// --- Slave control regs ---
reg  [6:0] s_slave_addr;
reg  [7:0] s_api_len;
reg        s_tx_empty, s_rx_full;
reg  [7:0] s_tx_data_reg;

// --- Slave SDA drive mux ---
// FSM drives SDA directly for ACK/NACK; bit_ctrl drives for data
wire s_sda_drive_oe  = s_fsm_sda_oe | s_bc_sda_oe;
wire s_sda_drive_out = s_fsm_sda_oe ? s_fsm_sda_out : s_bc_sda_out;

// Slave SCL stretch (open-drain)
assign scl_bus = (s_fsm_scl_oe && !s_fsm_scl_out) ? 1'b0 : 1'bz;

// --- Slave instances ---

i2c_io_pad u_s_scl_pad (
    .clk           (clk),
    .resetn        (resetn),
    .tx_data       (1'b1),        // slave never drives SCL during normal operation
    .output_enable (1'b0),
    .rx_data       (s_scl_raw),
    .sda           (scl_bus)
);

i2c_glitch_filter #(.THRESHOLD(5)) u_s_scl_filt (
    .clk         (clk),
    .resetn      (resetn),
    .raw_in      (s_scl_raw),
    .filtered_out(s_scl_filtered)
);

i2c_io_pad u_s_sda_pad (
    .clk           (clk),
    .resetn        (resetn),
    .tx_data       (s_sda_drive_out),
    .output_enable (s_sda_drive_oe),
    .rx_data       (s_sda_raw),
    .sda           (sda_bus)
);

i2c_glitch_filter #(.THRESHOLD(5)) u_s_sda_filt (
    .clk         (clk),
    .resetn      (resetn),
    .raw_in      (s_sda_raw),
    .filtered_out(s_sda_filtered)
);

i2c_start_stop u_s_start_stop (
    .clk       (clk),
    .resetn    (resetn),
    .gen_start (1'b0),
    .gen_stop  (1'b0),
    .scl_in    (s_scl_filtered),
    .sda_in    (s_sda_filtered),
    .sda_out   (),
    .sda_oe    (),
    .start_det (s_start_det),
    .stop_det  (s_stop_det),
    .done      ()
);

// Slave bit_ctrl:
//  - is_read = 1 when slave is receiving (master writes or address phase)
//  - is_read = 0 when slave is transmitting (master reads)
//  The slave FSM sets sda_oe=1 only during TX, so ~s_fsm_sda_oe ≈ is_read
wire s_bc_is_read = ~s_fsm_sda_oe;

i2c_bit_ctrl u_slave_bc (
    .clk       (clk),
    .resetn    (resetn),
    .enable    (s_fsm_bit_ctrl_en),
    .is_read   (s_bc_is_read),
    .ack_phase (s_ack_phase),
    .load      (s_fsm_load),
    .tx_data   (s_tx_data_reg),
    .rx_data   (s_rx_data_bc),
    .rx_ack    (s_bc_rx_ack),
    .byte_done (s_byte_done),
    .arb_lost  (s_arb_lost_bc),
    .sda_oe    (s_bc_sda_oe),
    .sda_out   (s_bc_sda_out),
    .scl_in    (s_scl_filtered),
    .sda_in    (s_sda_filtered)
);

i2c_slave_fsm u_slave_fsm (
    .clk         (clk),
    .resetn      (resetn),
    .i2c_en      (1'b1),
    .slave_addr  (s_slave_addr),
    .api_len     (s_api_len),
    .start_det   (s_start_det),
    .stop_det    (s_stop_det),
    .byte_done   (s_byte_done),
    .sda_sampled (s_bc_rx_ack),
    .rx_data     (s_rx_data_bc),
    .tx_empty    (s_tx_empty),
    .rx_full     (s_rx_full),
    .bit_ctrl_en (s_fsm_bit_ctrl_en),
    .load        (s_fsm_load),
    .tx_rd_en    (s_fsm_tx_rd_en),
    .rx_wr_en    (s_fsm_rx_wr_en),
    .sda_oe      (s_fsm_sda_oe),
    .sda_out     (s_fsm_sda_out),
    .addr_match  (s_addr_match),
    .busy        (s_busy),
    .api_done    (s_api_done),
    .api_stop_det(),
    .dir         (),
    .ack_phase   (s_ack_phase),
    .scl_oe      (s_fsm_scl_oe),
    .scl_out     (s_fsm_scl_out)
);

// ============================================================
// 5. Helpers & Tasks
// ============================================================
integer error_count;

task assert_val;
    input integer   exp;
    input integer   got;
    input [100*8:1] msg;
    begin
        if (exp !== got) begin
            $display("[%0t ns] FAIL %s | Exp=%0h Got=%0h", $time, msg, exp, got);
            error_count = error_count + 1;
        end else
            $display("[%0t ns] PASS %s", $time, msg);
    end
endtask

task wait_master_idle;
    input integer timeout_clks;
    integer t;
    begin
        t = 0;
        while (m_api_busy && t < timeout_clks) begin
            @(posedge clk); t = t + 1;
        end
        if (t >= timeout_clks)
            $display("[%0t ns] TIMEOUT: master stuck busy (state=%0d)", $time, m_api_state);
    end
endtask

task wait_slave_idle;
    input integer timeout_clks;
    integer t;
    begin
        t = 0;
        while (s_busy && t < timeout_clks) begin
            @(posedge clk); t = t + 1;
        end
        if (t >= timeout_clks)
            $display("[%0t ns] TIMEOUT: slave stuck busy", $time);
    end
endtask

task apply_reset;
    begin
        resetn           = 1'b0;
        m_api_start      = 0;   m_api_stop_req = 0;
        m_api_reload_en  = 0;   m_api_continue = 0;
        m_api_rw         = 0;
        m_api_slave_addr = 7'h50;
        m_api_len        = 8'd1;
        m_tx_data_reg    = 8'h00;
        m_fifo_tx_empty  = 1'b1;
        m_fifo_rx_full   = 1'b0;
        s_slave_addr     = 7'h50;
        s_api_len        = 8'd1;
        s_tx_data_reg    = 8'h00;
        s_tx_empty       = 1'b1;
        s_rx_full        = 1'b0;
        error_count      = 0;
        repeat(8) @(posedge clk);
        resetn = 1'b1;
        repeat(5) @(posedge clk);
    end
endtask

// ============================================================
// 6. Waveform & Monitor
// ============================================================
initial begin
    $dumpfile("tb_i2c_fsm_system.vcd");
    $dumpvars(0, tb_i2c_fsm_system);
end

initial begin
    $monitor("[%0t] m_st=%0d s_busy=%b match=%b sda=%b scl=%b | m_done=%b m_nack=%b s_done=%b",
             $time, m_api_state, s_busy, s_addr_match,
             sda_bus, scl_bus,
             m_api_done, m_api_nack_err, s_api_done);
end

// ============================================================
// 7. MAIN TEST
// ============================================================
initial begin
    $display("\n=========================================================");
    $display(" I2C FSM SYSTEM TEST");
    $display(" master_fsm + slave_fsm + bit_ctrl + start_stop");
    $display(" + glitch_filter + io_pad on shared open-drain bus");
    $display("=========================================================\n");

    apply_reset;

    // ─────────────────────────────────────────────────────────
    // SCENARIO 1: Master Write 0xA5 to Slave 0x50
    // ─────────────────────────────────────────────────────────
    $display("--- SCENARIO 1: Master Write 0xA5 → Slave 0x50 ---");
    apply_reset;

    s_slave_addr    = 7'h50;
    s_api_len       = 8'd1;
    s_tx_empty      = 1'b1;   // write transaction, slave has no data to send
    s_rx_full       = 1'b0;

    m_api_slave_addr = 7'h50;
    m_api_rw         = 1'b0;   // WRITE
    m_api_len        = 8'd1;
    m_api_stop_req   = 1'b1;
    m_fifo_tx_empty  = 1'b0;   // TX FIFO has data
    m_tx_data_reg    = 8'hA5;  // byte to write

    @(negedge clk); m_api_start = 1'b1;
    @(negedge clk); m_api_start = 1'b0;

    wait_master_idle(5000);
    wait_slave_idle (5000);
    repeat(30) @(posedge clk);

    assert_val(1, s_addr_match | s_api_done, "SCEN1: Slave acknowledged address");
    assert_val(0, m_api_nack_err,            "SCEN1: No NACK error on master");
    $display("    Slave RX data = 0x%h  (expect 0xA5)", s_rx_data_bc);

    // ─────────────────────────────────────────────────────────
    // SCENARIO 2: Master Read 0xC3 from Slave 0x50
    // ─────────────────────────────────────────────────────────
    $display("\n--- SCENARIO 2: Master Read ← Slave 0x50 (0xC3) ---");
    apply_reset;

    s_slave_addr    = 7'h50;
    s_api_len       = 8'd1;
    s_tx_empty      = 1'b0;    // slave has data ready
    s_rx_full       = 1'b0;
    s_tx_data_reg   = 8'hC3;   // slave will send 0xC3

    m_api_slave_addr = 7'h50;
    m_api_rw         = 1'b1;   // READ
    m_api_len        = 8'd1;
    m_api_stop_req   = 1'b1;
    m_fifo_tx_empty  = 1'b1;
    m_fifo_rx_full   = 1'b0;

    @(negedge clk); m_api_start = 1'b1;
    @(negedge clk); m_api_start = 1'b0;

    wait_master_idle(5000);
    wait_slave_idle (5000);
    repeat(30) @(posedge clk);

    assert_val(8'hC3, m_rx_data_bc, "SCEN2: Master received 0xC3");
    assert_val(0, m_api_nack_err,   "SCEN2: No NACK error");

    // ─────────────────────────────────────────────────────────
    // SCENARIO 3: Wrong Address — Slave Should Ignore
    // ─────────────────────────────────────────────────────────
    $display("\n--- SCENARIO 3: Wrong Address (master→0x51, slave=0x50) ---");
    apply_reset;

    s_slave_addr     = 7'h50;
    m_api_slave_addr = 7'h51;  // wrong!
    m_api_rw         = 1'b0;
    m_api_len        = 8'd1;
    m_api_stop_req   = 1'b1;
    m_fifo_tx_empty  = 1'b0;
    m_tx_data_reg    = 8'hBE;

    @(negedge clk); m_api_start = 1'b1;
    @(negedge clk); m_api_start = 1'b0;

    wait_master_idle(5000);
    repeat(30) @(posedge clk);

    assert_val(0, s_addr_match, "SCEN3: Slave should NOT match");
    assert_val(1, m_api_nack_err, "SCEN3: Master gets NACK (no slave responded)");

    // ─────────────────────────────────────────────────────────
    // SCENARIO 4: Repeated START (Write then Read)
    // ─────────────────────────────────────────────────────────
    $display("\n--- SCENARIO 4: Repeated START: Write then Read ---");
    apply_reset;

    s_slave_addr  = 7'h50;
    s_api_len     = 8'd2;
    s_tx_empty    = 1'b0;
    s_rx_full     = 1'b0;
    s_tx_data_reg = 8'h7E;   // slave will send 0x7E in read phase

    // First phase: WRITE, no STOP → repeated start
    m_api_slave_addr = 7'h50;
    m_api_rw         = 1'b0;
    m_api_len        = 8'd1;
    m_api_stop_req   = 1'b0;
    m_fifo_tx_empty  = 1'b0;
    m_tx_data_reg    = 8'h12;

    @(negedge clk); m_api_start = 1'b1;
    @(negedge clk); m_api_start = 1'b0;

    // Wait for master to reach M_REP_START_WAIT (state 11)
    begin : wait_rep
        integer t2;
        t2 = 0;
        while (m_api_state != 4'd11 && t2 < 3000) begin
            @(posedge clk); t2 = t2 + 1;
        end
        if (t2 >= 3000) $display("[%0t ns] TIMEOUT waiting for REP_START_WAIT", $time);
    end
    $display("[%0t ns] Master in REP_START_WAIT, issuing repeated START...", $time);

    // Repeated START: switch to READ
    m_api_rw       = 1'b1;
    m_api_stop_req = 1'b1;
    @(negedge clk); m_api_start = 1'b1;
    @(negedge clk); m_api_start = 1'b0;

    wait_master_idle(5000);
    wait_slave_idle (5000);
    repeat(30) @(posedge clk);

    assert_val(8'h7E, m_rx_data_bc, "SCEN4: Master read 0x7E via repeated START");

    // ─────────────────────────────────────────────────────────
    // DONE
    // ─────────────────────────────────────────────────────────
    $display("\n=========================================================");
    if (error_count == 0)
        $display(" ALL SCENARIOS PASSED!");
    else
        $display(" %0d ERROR(S) FOUND", error_count);
    $display("=========================================================\n");
    #500 $finish;
end

endmodule
