`timescale 1ns/1ps

module tb_i2c_slave_fsm;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg        clk;
	reg        resetn;

	// own address
	reg  [6:0] slave_addr;

	// from start_stop
	reg        start_det;
	reg        stop_det;

	// from bit_ctrl
	reg        byte_done;
	reg        sda_sampled;

	// from shift_reg
	reg  [7:0] rx_data;

	// from fifo
	reg        tx_empty;

	// outputs
	wire       bit_ctrl_en;
	wire       load;
	wire       tx_rd_en;
	wire       rx_wr_en;
	wire       sda_oe;
	wire       sda_out;
	wire       addr_match;
	wire       busy;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_slave_fsm u_dut (
		.clk         (clk),
		.resetn      (resetn),
		.i2c_en      (1'b1),
		.slave_addr  (slave_addr),
		.api_len     (8'd2),
		.start_det   (start_det),
		.stop_det    (stop_det),
		.byte_done   (byte_done),
		.sda_sampled (sda_sampled),
		.rx_data     (rx_data),
		.tx_empty    (tx_empty),
		.rx_full     (1'b0),
		.bit_ctrl_en (bit_ctrl_en),
		.load        (load),
		.tx_rd_en    (tx_rd_en),
		.rx_wr_en    (rx_wr_en),
		.sda_oe      (sda_oe),
		.sda_out     (sda_out),
		.addr_match  (addr_match),
		.busy        (busy),
		.api_done    (),
		.api_stop_det(),
		.dir         (),
		.ack_phase   (),
		.scl_oe      (),
		.scl_out     ()
	);

	// ─────────────────────────────────────
	// Clock — 10ns period
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Capture flags
	// ─────────────────────────────────────
	reg addr_match_captured;
	reg rx_wr_en_captured;
	reg tx_rd_en_captured;
	reg load_captured;
	reg sda_oe_captured;
	reg busy_captured;

	always @(posedge clk) begin
		if (addr_match) addr_match_captured <= 1'b1;
		if (rx_wr_en)   rx_wr_en_captured   <= 1'b1;
		if (tx_rd_en)   tx_rd_en_captured   <= 1'b1;
		if (load)       load_captured       <= 1'b1;
		if (sda_oe)     sda_oe_captured     <= 1'b1;
		if (busy)       busy_captured       <= 1'b1;
	end

	// ─────────────────────────────────────
	// Task — Reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			resetn      = 1'b0;
			slave_addr  = 7'h50;
			start_det   = 1'b0;
			stop_det    = 1'b0;
			byte_done   = 1'b0;
			sda_sampled = 1'b0;
			rx_data     = 8'h00;
			tx_empty    = 1'b0;

			addr_match_captured = 1'b0;
			rx_wr_en_captured   = 1'b0;
			tx_rd_en_captured   = 1'b0;
			load_captured       = 1'b0;
			sda_oe_captured     = 1'b0;
			busy_captured       = 1'b0;

			@(posedge clk); #1;
			@(posedge clk); #1;
			resetn = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Clear captures
	// ─────────────────────────────────────
	task clear_captures;
		begin
			addr_match_captured = 1'b0;
			rx_wr_en_captured   = 1'b0;
			tx_rd_en_captured   = 1'b0;
			load_captured       = 1'b0;
			sda_oe_captured     = 1'b0;
			busy_captured       = 1'b0;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check 1-bit
	// ─────────────────────────────────────
	task check;
		input       exp_val;
		input       got_val;
		input [80*8:1] test_name;
		begin
			if (got_val !== exp_val)
				$display("FAIL [%0s] got=%b exp=%b at t=%0t",
						  test_name, got_val, exp_val, $time);
			else
				$display("PASS [%0s] got=%b",
						  test_name, got_val);
		end
	endtask

	// ─────────────────────────────────────
	// Task — Send START then address
	// addr_byte = {slave_addr, rw}
	// ─────────────────────────────────────
	task send_addr;
		input [7:0] addr_byte;  // {7-bit addr, rw}
		begin
			// pulse start_det
			start_det = 1'b1;
			@(posedge clk); #1;
			start_det = 1'b0;
			repeat(2) @(posedge clk); #1;

			// put address on rx_data
			rx_data  = addr_byte;

			// pulse byte_done — address received
			byte_done = 1'b1;
			@(posedge clk); #1;
			byte_done = 1'b0;
			repeat(2) @(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Send data byte
	// ─────────────────────────────────────
	task send_data_byte;
		input [7:0] data;
		begin
			rx_data   = data;
			byte_done = 1'b1;
			@(posedge clk); #1;
			byte_done = 1'b0;
			repeat(2) @(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Send STOP
	// ─────────────────────────────────────
	task send_stop;
		begin
			stop_det  = 1'b1;
			@(posedge clk); #1;
			stop_det  = 1'b0;
			repeat(2) @(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	initial begin
		$display("=== tb_i2c_slave_fsm START ===");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		$display("--- TEST1: Reset ---");
		apply_reset;

		check(1'b0, bit_ctrl_en, "RESET_BITCTRL_EN");
		check(1'b0, load,        "RESET_LOAD");
		check(1'b0, rx_wr_en,    "RESET_RX_WR_EN");
		check(1'b0, sda_oe,      "RESET_SDA_OE");
		check(1'b0, addr_match,  "RESET_ADDR_MATCH");
		check(1'b0, busy,        "RESET_BUSY");

		// ─────────────────────
		// TEST 2 — IDLE no start
		// stays IDLE without start_det
		// ─────────────────────
		$display("--- TEST2: IDLE without start_det ---");
		apply_reset;
		repeat(10) @(posedge clk); #1;

		check(1'b0, busy,        "IDLE_NOT_BUSY");
		check(1'b0, bit_ctrl_en, "IDLE_BITCTRL_OFF");
		$display("    FSM stays IDLE ✅");

		// ─────────────────────
		// TEST 3 — Wrong address
		// address does not match
		// slave goes back to IDLE
		// ─────────────────────
		$display("--- TEST3: Wrong address no match ---");
		apply_reset;
		clear_captures;
		slave_addr = 7'h50;

		// send wrong address 0x51 write
		send_addr(8'hA2);   // 0x51 << 1 | 0 = 0xA2
		repeat(3) @(posedge clk); #1;

		check(1'b0, addr_match_captured, "WRONG_ADDR_NO_MATCH");
		check(1'b0, busy,                "WRONG_ADDR_BACK_IDLE");
		check(1'b0, sda_oe_captured,     "WRONG_ADDR_NO_ACK");
		$display("    wrong address ignored ✅");

		// ─────────────────────
		// TEST 4 — Correct address match
		// slave sends ACK
		// ─────────────────────
		$display("--- TEST4: Correct address match ---");
		apply_reset;
		clear_captures;
		slave_addr = 7'h50;

		// send correct address 0x50 write
		// addr_byte = {7'h50, 1'b0} = 8'hA0
		send_addr(8'hA0);
		repeat(2) @(posedge clk); #1;

		check(1'b1, addr_match_captured, "CORRECT_ADDR_MATCH");
		check(1'b1, busy,                "ADDR_MATCH_BUSY");
		// slave should drive SDA low = ACK
		check(1'b1, sda_oe_captured,     "ADDR_ACK_SDA_OE");
		$display("    address matched → ACK sent ✅");

		// ─────────────────────
		// TEST 5 — Master write
		// master writes data to slave
		// rx_wr_en fires to push RX FIFO
		// ─────────────────────
		$display("--- TEST5: Master write to slave ---");
		apply_reset;
		clear_captures;
		slave_addr = 7'h50;

		// address phase write
		send_addr(8'hA0);   // 0x50 write
		repeat(2) @(posedge clk); #1;

		// ACK phase done
		byte_done = 1'b1;
		@(posedge clk); #1;
		byte_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		// master sends data byte
		send_data_byte(8'h42);
		repeat(2) @(posedge clk); #1;

		check(1'b1, rx_wr_en_captured, "WRITE_RX_WR_EN");
		$display("    rx_wr_en fires on received byte ✅");

		// slave ACKs data
		byte_done = 1'b1;
		@(posedge clk); #1;
		byte_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		// send another byte
		clear_captures;
		send_data_byte(8'hFF);
		repeat(2) @(posedge clk); #1;

		check(1'b1, rx_wr_en_captured, "WRITE_RX_WR_EN_2");
		$display("    rx_wr_en fires again for 2nd byte ✅");

		// STOP
		send_stop;
		repeat(2) @(posedge clk); #1;
		check(1'b0, busy, "WRITE_STOP_IDLE");
		$display("    STOP → back to IDLE ✅");

		// ─────────────────────
		// TEST 6 — Master read
		// master reads data from slave
		// tx_rd_en fires to pop TX FIFO
		// load fires to load shift_reg
		// ─────────────────────
		$display("--- TEST6: Master read from slave ---");
		apply_reset;
		clear_captures;
		slave_addr = 7'h50;
		tx_empty   = 1'b0;  // TX FIFO has data

		// address phase READ
		// addr_byte = {7'h50, 1'b1} = 8'hA1
		send_addr(8'hA1);
		repeat(2) @(posedge clk); #1;

		// ACK phase done
		byte_done = 1'b1;
		@(posedge clk); #1;
		byte_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b1, tx_rd_en_captured, "READ_TX_RD_EN");
		check(1'b1, load_captured,     "READ_LOAD");
		$display("    tx_rd_en + load fires for TX byte ✅");

		// slave sends data byte — master ACKs
		sda_sampled = 1'b0;     // master ACK = more data
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		// master sends NACK = done reading
		sda_sampled = 1'b1;     // NACK
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		// STOP
		send_stop;
		repeat(2) @(posedge clk); #1;
		check(1'b0, busy, "READ_BACK_IDLE");
		$display("    read complete → back to IDLE ✅");

		// ─────────────────────
		// TEST 7 — STOP mid transfer
		// stop_det during DATA_RX
		// → back to IDLE immediately
		// ─────────────────────
		$display("--- TEST7: STOP mid transfer ---");
		apply_reset;
		clear_captures;
		slave_addr = 7'h50;

		// start address match
		send_addr(8'hA0);
		repeat(2) @(posedge clk); #1;

		// ACK sent
		byte_done = 1'b1;
		@(posedge clk); #1;
		byte_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b1, busy, "MID_XFER_BUSY");

		// STOP arrives mid transfer
		send_stop;
		repeat(3) @(posedge clk); #1;

		check(1'b0, busy, "STOP_MID_IDLE");
		$display("    stop_det → IDLE immediately ✅");

		// ─────────────────────
		// TEST 8 — New START during transfer
		// repeated start → reset to ADDR_RX
		// ─────────────────────
		$display("--- TEST8: Repeated START ---");
		apply_reset;
		clear_captures;
		slave_addr = 7'h50;

		// first transfer starts
		send_addr(8'hA0);
		repeat(2) @(posedge clk); #1;

		byte_done = 1'b1;
		@(posedge clk); #1;
		byte_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b1, busy, "FIRST_XFER_BUSY");

		// repeated START — new transfer begins
		clear_captures;
		start_det = 1'b1;
		@(posedge clk); #1;
		start_det = 1'b0;
		repeat(2) @(posedge clk); #1;

		// send new address
		rx_data   = 8'hA0;
		byte_done = 1'b1;
		@(posedge clk); #1;
		byte_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b1, addr_match_captured, "REPEATED_START_MATCH");
		$display("    repeated START handled correctly ✅");

		// ─────────────────────
		// TEST 9 — Busy flag
		// busy=0 in IDLE
		// busy=1 during transfer
		// ─────────────────────
		$display("--- TEST9: Busy flag ---");
		apply_reset;

		check(1'b0, busy, "BUSY_IDLE_LOW");

		// trigger transfer
		send_addr(8'hA0);
		repeat(2) @(posedge clk); #1;

		check(1'b1, busy, "BUSY_XFER_HIGH");

		// end transfer
		send_stop;
		repeat(2) @(posedge clk); #1;

		check(1'b0, busy, "BUSY_STOP_LOW");
		$display("    busy flag correct ✅");

		$display("=== tb_i2c_slave_fsm DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_slave_fsm.vcd");
		$dumpvars(0, tb_i2c_slave_fsm);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | bce=%b load=%b rxwe=%b txre=%b | match=%b busy=%b sda_oe=%b sda_out=%b",
				  $time,
				  bit_ctrl_en, load,
				  rx_wr_en, tx_rd_en,
				  addr_match, busy,
				  sda_oe, sda_out);
	end

endmodule