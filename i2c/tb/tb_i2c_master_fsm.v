`timescale 1ns/1ps

module tb_i2c_master_fsm;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg        clk;
	reg        resetn;

	// APB register inputs
	reg        start_req;
	reg        rw;
	reg  [6:0] slave_addr;

	// FIFO status
	reg        tx_empty;

	// bit_ctrl inputs
	reg        byte_done;
	reg        sda_sampled;

	// start_stop inputs
	reg        start_done;
	reg        stop_done;

	// outputs
	wire       gen_start;
	wire       gen_stop;
	wire       bit_ctrl_en;
	wire       load;
	wire       tx_rd_en;
	wire       rx_wr_en;
	wire       arb_lost;
	wire       busy;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_master_fsm u_dut (
		.clk         (clk),
		.resetn      (resetn),
		.start       (start_req),
		.rw          (rw),
		.slave_addr  (slave_addr),
		.tx_empty    (tx_empty),
		.byte_done   (byte_done),
		.sda_sampled (sda_sampled),
		.start_done  (start_done),
		.stop_done   (stop_done),
		.gen_start   (gen_start),
		.gen_stop    (gen_stop),
		.bit_ctrl_en (bit_ctrl_en),
		.load        (load),
		.tx_rd_en    (tx_rd_en),
		.rx_wr_en    (rx_wr_en),
		.arb_lost    (arb_lost),
		.busy        (busy)
	);

	// ─────────────────────────────────────
	// Clock — 10ns period
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Capture flags
	// ─────────────────────────────────────
	reg gen_start_captured;
	reg gen_stop_captured;
	reg load_captured;
	reg tx_rd_en_captured;
	reg rx_wr_en_captured;
	reg busy_captured;

	always @(posedge clk) begin
		if (gen_start) gen_start_captured <= 1'b1;
		if (gen_stop)  gen_stop_captured  <= 1'b1;
		if (load)      load_captured      <= 1'b1;
		if (tx_rd_en)  tx_rd_en_captured  <= 1'b1;
		if (rx_wr_en)  rx_wr_en_captured  <= 1'b1;
		if (busy)      busy_captured      <= 1'b1;
	end

	// ─────────────────────────────────────
	// Task — Reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			resetn      = 1'b0;
			start_req   = 1'b0;
			rw          = 1'b0;
			slave_addr  = 7'h50;
			tx_empty    = 1'b0;
			byte_done   = 1'b0;
			sda_sampled = 1'b0;   // ACK by default
			start_done  = 1'b0;
			stop_done   = 1'b0;

			gen_start_captured = 1'b0;
			gen_stop_captured  = 1'b0;
			load_captured      = 1'b0;
			tx_rd_en_captured  = 1'b0;
			rx_wr_en_captured  = 1'b0;
			busy_captured      = 1'b0;

			@(posedge clk); #1;
			@(posedge clk); #1;
			resetn = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check 1-bit signal
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
	// Task — Pulse 1-cycle signal
	// ─────────────────────────────────────
	task pulse;
		inout sig;
		begin
			sig = 1'b1;
			@(posedge clk); #1;
			sig = 1'b0;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Clear capture flags
	// ─────────────────────────────────────
	task clear_captures;
		begin
			gen_start_captured = 1'b0;
			gen_stop_captured  = 1'b0;
			load_captured      = 1'b0;
			tx_rd_en_captured  = 1'b0;
			rx_wr_en_captured  = 1'b0;
			busy_captured      = 1'b0;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Simulate full write transaction
	// IDLE→START→ADDR→ADDR_ACK→DATA_TX→DATA_ACK→STOP→IDLE
	// ─────────────────────────────────────
	task do_write_transfer;
		input ack_addr;   // 0=ACK, 1=NACK
		input ack_data;   // 0=ACK, 1=NACK
		input more_data;  // 1=send one more data byte after first
		begin
			rw = 1'b0;  // write

			// IDLE → START
			start_req = 1'b1;
			@(posedge clk); #1;
			start_req = 1'b0;
			repeat(2) @(posedge clk); #1;

			// START → ADDR
			start_done = 1'b1;
			@(posedge clk); #1;
			start_done = 1'b0;
			repeat(2) @(posedge clk); #1;

			// ADDR → ADDR_ACK
			byte_done = 1'b1;
			@(posedge clk); #1;
			byte_done = 1'b0;
			repeat(2) @(posedge clk); #1;

			// ADDR_ACK — drive ACK/NACK
			sda_sampled = ack_addr;
			byte_done   = 1'b1;
			@(posedge clk); #1;
			byte_done   = 1'b0;
			repeat(2) @(posedge clk); #1;

			// If address NACK, FSM should go straight to STOP
			if (ack_addr) begin
				stop_done = 1'b1;
				@(posedge clk); #1;
				stop_done = 1'b0;
				repeat(2) @(posedge clk); #1;
			end
			else begin
				// DATA_TX → DATA_ACK (1st data byte)
				byte_done = 1'b1;
				@(posedge clk); #1;
				byte_done = 1'b0;
				repeat(2) @(posedge clk); #1;

				// DATA_ACK — ACK/NACK for data byte
				// tx_empty is sampled in/around DATA_ACK to decide continue vs STOP
				tx_empty    = ~more_data;
				sda_sampled = ack_data;
				byte_done   = 1'b1;
				@(posedge clk); #1;
				byte_done   = 1'b0;
				repeat(2) @(posedge clk); #1;

				// Optional second data byte (only if more_data and data was ACKed)
				if (more_data && (ack_data == 1'b0)) begin
					tx_empty = 1'b0;
					byte_done = 1'b1;
					@(posedge clk); #1;
					byte_done = 1'b0;
					repeat(2) @(posedge clk); #1;

					// Second DATA_ACK → stop (no more data)
					tx_empty    = 1'b1;
					sda_sampled = 1'b0;  // ACK
					byte_done   = 1'b1;
					@(posedge clk); #1;
					byte_done   = 1'b0;
					repeat(2) @(posedge clk); #1;
				end

				// STOP
				stop_done = 1'b1;
				@(posedge clk); #1;
				stop_done = 1'b0;
				repeat(2) @(posedge clk); #1;
			end
		end
	endtask


	// ─────────────────────────────────────
	// Task — Simulate full read transaction
	// IDLE→START→ADDR→ADDR_ACK→DATA_RX→DATA_ACK→STOP→IDLE
	// ─────────────────────────────────────
	task do_read_transfer;
		begin
			rw = 1'b1;  // read

			// IDLE → START
			start_req = 1'b1;
			@(posedge clk); #1;
			start_req = 1'b0;
			repeat(2) @(posedge clk); #1;

			// START → ADDR
			start_done = 1'b1;
			@(posedge clk); #1;
			start_done = 1'b0;
			repeat(2) @(posedge clk); #1;

			// ADDR → ADDR_ACK
			byte_done = 1'b1;
			@(posedge clk); #1;
			byte_done = 1'b0;
			repeat(2) @(posedge clk); #1;

			// ADDR_ACK — ACK received
			sda_sampled = 1'b0;     // ACK
			byte_done   = 1'b1;
			@(posedge clk); #1;
			byte_done   = 1'b0;
			repeat(2) @(posedge clk); #1;

			// DATA_RX → DATA_ACK
			byte_done = 1'b1;
			@(posedge clk); #1;
			byte_done = 1'b0;
			repeat(2) @(posedge clk); #1;

			// DATA_ACK — send NACK to stop
			sda_sampled = 1'b1;     // NACK = done reading
			byte_done   = 1'b1;
			@(posedge clk); #1;
			byte_done   = 1'b0;
			repeat(2) @(posedge clk); #1;

			// STOP
			stop_done = 1'b1;
			@(posedge clk); #1;
			stop_done = 1'b0;
			repeat(2) @(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	initial begin
		$display("=== tb_i2c_master_fsm START ===");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		$display("--- TEST1: Reset ---");
		apply_reset;

		check(1'b0, gen_start,   "RESET_GEN_START");
		check(1'b0, gen_stop,    "RESET_GEN_STOP");
		check(1'b0, bit_ctrl_en, "RESET_BITCTRL_EN");
		check(1'b0, load,        "RESET_LOAD");
		check(1'b0, busy,        "RESET_BUSY");

		// ─────────────────────
		// TEST 2 — IDLE no start
		// FSM stays IDLE
		// ─────────────────────
		$display("--- TEST2: IDLE no start_req ---");
		apply_reset;
		repeat(10) @(posedge clk); #1;

		check(1'b0, busy,      "IDLE_NOT_BUSY");
		check(1'b0, gen_start, "IDLE_NO_GENSTART");
		$display("    FSM stays IDLE without start_req ✅");

		// ─────────────────────
		// TEST 3 — START generation
		// start_req → gen_start fires
		// ─────────────────────
		$display("--- TEST3: START generation ---");
		apply_reset;
		clear_captures;

		start_req = 1'b1;
		@(posedge clk); #1;
		start_req = 1'b0;
		repeat(3) @(posedge clk); #1;

		check(1'b1, gen_start_captured, "GEN_START_FIRES");
		check(1'b1, busy,               "BUSY_IN_START");
		$display("    gen_start fired on start_req ✅");

		// ─────────────────────
		// TEST 4 — ADDR load after start_done
		// start_done → load + bit_ctrl_en
		// ─────────────────────
		$display("--- TEST4: ADDR load after start_done ---");
		apply_reset;
		clear_captures;

		// trigger START
		start_req  = 1'b1;
		@(posedge clk); #1;
		start_req  = 1'b0;
		repeat(2) @(posedge clk); #1;

		// assert start_done
		start_done = 1'b1;
		@(posedge clk); #1;
		start_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b1, load_captured,    "LOAD_ON_START_DONE");
		check(1'b1, bit_ctrl_en,      "BITCTRL_EN_ADDR");
		$display("    addr loaded into shift_reg after start_done ✅");

		// ─────────────────────
		// TEST 5 — Write with ACK
		// full write sequence
		// ─────────────────────
		$display("--- TEST5: Full write with ACK ---");
		apply_reset;
		clear_captures;
		rw       = 1'b0;    // write
		tx_empty = 1'b0;    // data available

		do_write_transfer(
			1'b0,  // ack_addr (0=ACK)
			1'b0,  // ack_data (0=ACK)
			1'b0   // more_data
		);

		check(1'b1, gen_start_captured, "WRITE_GEN_START");
		check(1'b1, load_captured,      "WRITE_LOAD");
		check(1'b1, tx_rd_en_captured,  "WRITE_TX_RD_EN");
		check(1'b1, gen_stop_captured,  "WRITE_GEN_STOP");
		$display("    full write ACK sequence complete ✅");

		// ─────────────────────
		// TEST 6 — Write with NACK on address
		// NACK → go to STOP immediately
		// ─────────────────────
		$display("--- TEST6: NACK on address ---");
		apply_reset;
		clear_captures;
		rw = 1'b0;

		// IDLE → START
		start_req  = 1'b1;
		@(posedge clk); #1;
		start_req  = 1'b0;
		repeat(2) @(posedge clk); #1;

		// START done
		start_done = 1'b1;
		@(posedge clk); #1;
		start_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		// ADDR done
		byte_done  = 1'b1;
		@(posedge clk); #1;
		byte_done  = 1'b0;
		repeat(2) @(posedge clk); #1;

		// ADDR_ACK — NACK received
		sda_sampled = 1'b1;     // NACK
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(3) @(posedge clk); #1;

		// should go straight to STOP
		check(1'b1, gen_stop_captured,  "NACK_GEN_STOP");
		// should NOT go to DATA_TX
		check(1'b0, tx_rd_en_captured,  "NACK_NO_TX_RD");
		$display("    NACK on address → STOP immediately ✅");

		// STOP done
		stop_done = 1'b1;
		@(posedge clk); #1;
		stop_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b0, busy, "NACK_BACK_IDLE");
		$display("    back to IDLE after NACK ✅");

		// ─────────────────────
		// TEST 7 — Full Read
		// ─────────────────────
		$display("--- TEST7: Full read ---");
		apply_reset;
		clear_captures;

		do_read_transfer;

		check(1'b1, gen_start_captured, "READ_GEN_START");
		check(1'b1, load_captured,      "READ_LOAD_ADDR");
		check(1'b1, rx_wr_en_captured,  "READ_RX_WR_EN");
		check(1'b1, gen_stop_captured,  "READ_GEN_STOP");
		$display("    full read sequence complete ✅");

		// ─────────────────────
		// TEST 8 — Busy flag
		// busy=1 during transfer
		// busy=0 in IDLE
		// ─────────────────────
		$display("--- TEST8: Busy flag ---");
		apply_reset;
		clear_captures;
		rw       = 1'b0;
		tx_empty = 1'b0;

		// check not busy before start
		check(1'b0, busy, "NOT_BUSY_BEFORE");

		// trigger transfer
		start_req  = 1'b1;
		@(posedge clk); #1;
		start_req  = 1'b0;
		repeat(2) @(posedge clk); #1;

		// should be busy now
		check(1'b1, busy, "BUSY_DURING_XFER");

		// complete transfer
		start_done  = 1'b1;
		@(posedge clk); #1;
		start_done  = 1'b0;
		repeat(2) @(posedge clk); #1;

		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		sda_sampled = 1'b0;
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		tx_empty    = 1'b1;
		sda_sampled = 1'b0;
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		stop_done   = 1'b1;
		@(posedge clk); #1;
		stop_done   = 1'b0;
		repeat(3) @(posedge clk); #1;

		check(1'b0, busy, "NOT_BUSY_AFTER");
		$display("    busy flag correct throughout ✅");

		// ─────────────────────
		// TEST 9 — Multi byte write
		// tx_empty=0 → continue
		// tx_empty=1 → STOP
		// ─────────────────────
		$display("--- TEST9: Multi byte write ---");
		apply_reset;
		clear_captures;
		rw       = 1'b0;
		tx_empty = 1'b0;    // 2 bytes available

		// START
		start_req  = 1'b1;
		@(posedge clk); #1;
		start_req  = 1'b0;
		repeat(2) @(posedge clk); #1;

		start_done = 1'b1;
		@(posedge clk); #1;
		start_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		// ADDR
		byte_done  = 1'b1;
		@(posedge clk); #1;
		byte_done  = 1'b0;
		repeat(2) @(posedge clk); #1;

		// ADDR ACK
		sda_sampled = 1'b0;
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		// BYTE 1 DATA_TX
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		// BYTE 1 DATA_ACK — more data
		tx_empty    = 1'b0;     // still more data
		sda_sampled = 1'b0;
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		// check tx_rd_en fired for next byte
		check(1'b1, tx_rd_en_captured, "MULTI_TX_RD_EN");
		$display("    tx_rd_en fires for next byte ✅");

		// BYTE 2 DATA_TX
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(2) @(posedge clk); #1;

		// BYTE 2 DATA_ACK — no more data
		tx_empty    = 1'b1;     // FIFO empty now
		sda_sampled = 1'b0;
		byte_done   = 1'b1;
		@(posedge clk); #1;
		byte_done   = 1'b0;
		repeat(3) @(posedge clk); #1;

		// should go to STOP now
		check(1'b1, gen_stop_captured, "MULTI_GEN_STOP");
		$display("    STOP after last byte ✅");

		stop_done = 1'b1;
		@(posedge clk); #1;
		stop_done = 1'b0;
		repeat(2) @(posedge clk); #1;

		check(1'b0, busy, "MULTI_BACK_IDLE");
		$display("    back to IDLE after multi-byte write ✅");

		$display("=== tb_i2c_master_fsm DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_master_fsm.vcd");
		$dumpvars(0, tb_i2c_master_fsm);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | start=%b stop=%b bce=%b load=%b | busy=%b arb=%b",
				  $time,
				  gen_start, gen_stop,
				  bit_ctrl_en, load,
				  busy, arb_lost);
	end

endmodule