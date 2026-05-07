`timescale 1ns/1ps

module tb_i2c_start_stop;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg  clk;
	reg  resetn;
	reg  gen_start;
	reg  gen_stop;
	reg  scl_in;
	reg  sda_in;

	wire sda_out;
	wire sda_oe;
	wire start_det;
	wire stop_det;
	wire done;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_start_stop u_dut (
		.clk       (clk),
		.resetn    (resetn),
		.gen_start (gen_start),
		.gen_stop  (gen_stop),
		.scl_in    (scl_in),
		.sda_in    (sda_in),
		.sda_out   (sda_out),
		.sda_oe    (sda_oe),
		.start_det (start_det),
		.stop_det  (stop_det),
		.done      (done)
	);

	// ─────────────────────────────────────
	// Clock — 10ns period
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Capture flags
	// ─────────────────────────────────────
	reg start_det_captured;
	reg stop_det_captured;
	reg done_captured;

	always @(posedge clk) begin
		if (start_det) start_det_captured <= 1'b1;
		if (stop_det)  stop_det_captured  <= 1'b1;
		if (done)      done_captured      <= 1'b1;
	end

	// ─────────────────────────────────────
	// Task — Reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			resetn    = 1'b0;
			gen_start = 1'b0;
			gen_stop  = 1'b0;
			scl_in    = 1'b1;   // bus idle HIGH
			sda_in    = 1'b1;   // bus idle HIGH
			start_det_captured = 1'b0;
			stop_det_captured  = 1'b0;
			done_captured      = 1'b0;
			@(posedge clk); #1;
			@(posedge clk); #1;
			resetn = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check single bit
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
	// Task — Wait for signal with timeout
	// ─────────────────────────────────────
	task wait_for_signal;
		input      exp_val;
		inout      sig;
		input [31:0] timeout_cycles;
		output     timed_out;
		integer    count;
		begin
			count     = 0;
			timed_out = 1'b0;
			while (sig !== exp_val && count < timeout_cycles) begin
				@(posedge clk); #1;
				count = count + 1;
			end
			if (count >= timeout_cycles) begin
				timed_out = 1'b1;
				$display("TIMEOUT waiting for signal at t=%0t", $time);
			end
		end
	endtask

	// ─────────────────────────────────────
	// Task — simulate SCL high period
	// ─────────────────────────────────────
	task scl_high;
		input [7:0] cycles;
		integer j;
		begin
			scl_in = 1'b1;
			for (j = 0; j < cycles; j = j + 1)
				@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — simulate SCL low period
	// ─────────────────────────────────────
	task scl_low;
		input [7:0] cycles;
		integer j;
		begin
			scl_in = 1'b0;
			for (j = 0; j < cycles; j = j + 1)
				@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — wait for done with timeout
	// ─────────────────────────────────────
	task wait_done;
		input [31:0] timeout;
		integer cnt;
		begin
			cnt = 0;
			while (!done && cnt < timeout) begin
				@(posedge clk); #1;
				cnt = cnt + 1;
			end
			if (cnt >= timeout)
				$display("TIMEOUT waiting for done");
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	initial begin
		$display("=== tb_i2c_start_stop START ===");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		$display("--- TEST1: Reset ---");
		apply_reset;

		check(1'b0, gen_start,  "RESET_GENSTART_LOW");
		check(1'b0, gen_stop,   "RESET_GENSTOP_LOW");
		check(1'b0, sda_oe,     "RESET_SDA_OE_LOW");
		check(1'b0, start_det,  "RESET_STARTDET_LOW");
		check(1'b0, stop_det,   "RESET_STOPDET_LOW");
		check(1'b0, done,       "RESET_DONE_LOW");

		// ─────────────────────
		// TEST 2 — Generate START
		// sequence:
		//   SDA HIGH + SCL HIGH (idle)
		//   assert gen_start
		//   DUT pulls SDA LOW while SCL HIGH = START
		//   then SCL goes LOW
		// ─────────────────────
		// ─────────────────────
		// TEST 2 — Generate START
		// ─────────────────────
		$display("--- TEST2: Generate START ---");
		apply_reset;

		scl_in    = 1'b1;
		sda_in    = 1'b1;
		@(posedge clk); #1;

		// request START — assert ONCE only
		gen_start = 1'b1;
		@(posedge clk); #1;
		gen_start = 1'b0;

		// ✅ FSM now in SDA_HIGH — holds 2 cycles
		// check immediately — sda_out=1 in SDA_HIGH
		@(posedge clk); #1;
		check(1'b1, sda_out, "START_SDA_FIRST_HIGH");

		// wait FSM to reach SDA_LOW
		repeat(8) @(posedge clk); #1;

		// SDA should now be LOW while SCL still HIGH
		if (sda_oe && !sda_out && scl_in)
		    $display("PASS [START_SDA_LOW_SCLHIGH] ✅");
		else
		    $display("FAIL [START_SDA_LOW_SCLHIGH] sda_oe=%b sda_out=%b scl=%b",
		              sda_oe, sda_out, scl_in);

		// SCL goes LOW after START
		scl_low(5);

		// ✅ done is now registered — wait safely
		repeat(5) @(posedge clk); #1;
		check(1'b1, done_captured, "START_DONE");
				$display("    START generation done ✅");

		// ─────────────────────
		// TEST 3 — Detect START
		// drive SDA LOW while SCL HIGH
		// start_det should fire
		// ─────────────────────
		$display("--- TEST3: Detect START ---");
		apply_reset;
		start_det_captured = 1'b0;

		// bus idle
		scl_in = 1'b1;
		sda_in = 1'b1;
		repeat(3) @(posedge clk); #1;

		// SDA falls while SCL HIGH = START condition
		sda_in = 1'b0;          // ← this IS the START
		repeat(3) @(posedge clk); #1;

		check(1'b1, start_det_captured, "START_DET_FIRED");
		$display("    START detected on bus ✅");

		// ─────────────────────
		// TEST 4 — Generate STOP
		// sequence:
		//   SCL LOW + SDA LOW (during data)
		//   assert gen_stop
		//   DUT waits SCL HIGH
		//   DUT pulls SDA HIGH while SCL HIGH = STOP
		// ─────────────────────
		$display("--- TEST4: Generate STOP ---");
		apply_reset;
		done_captured = 1'b0;

		// simulate mid-transfer state
		scl_in = 1'b0;      // SCL LOW
		sda_in = 1'b0;      // SDA LOW
		repeat(3) @(posedge clk); #1;

		// request STOP
		gen_stop = 1'b1;
		@(posedge clk); #1;
		gen_stop = 1'b0;

		// wait for DUT to prepare SDA LOW
		repeat(5) @(posedge clk); #1;

		// SCL rises
		scl_high(5);

		// check SDA goes HIGH while SCL HIGH = STOP
		repeat(3) @(posedge clk); #1;
		$display("    checking SDA goes HIGH while SCL HIGH");
		if (sda_oe && sda_out && scl_in)
			$display("PASS [STOP_SDA_HIGH_SCLHIGH] sda_oe=%b sda_out=%b scl=%b",
					  sda_oe, sda_out, scl_in);
		else
			$display("FAIL [STOP_SDA_HIGH_SCLHIGH] sda_oe=%b sda_out=%b scl=%b",
					  sda_oe, sda_out, scl_in);

		// update sda_in to reflect sda_out
		sda_in = sda_out;
		repeat(5) @(posedge clk); #1;

		check(1'b1, done_captured, "STOP_DONE");
		$display("    STOP generation done ✅");

		// ─────────────────────
		// TEST 5 — Detect STOP
		// drive SDA HIGH while SCL HIGH
		// stop_det should fire
		// ─────────────────────
		$display("--- TEST5: Detect STOP ---");
		apply_reset;
		stop_det_captured = 1'b0;

		// mid transfer state
		scl_in = 1'b1;
		sda_in = 1'b0;      // SDA LOW during data
		repeat(3) @(posedge clk); #1;

		// SDA rises while SCL HIGH = STOP condition
		sda_in = 1'b1;          // ← this IS the STOP
		repeat(3) @(posedge clk); #1;

		check(1'b1, stop_det_captured, "STOP_DET_FIRED");
		$display("    STOP detected on bus ✅");

		// ─────────────────────
		// TEST 6 — No false START
		// SDA changes while SCL LOW
		// should NOT trigger start_det
		// ─────────────────────
		$display("--- TEST6: No false START/STOP ---");
		apply_reset;
		start_det_captured = 1'b0;
		stop_det_captured  = 1'b0;

		// SCL LOW — SDA can change freely
		scl_in = 1'b0;
		sda_in = 1'b1;
		repeat(2) @(posedge clk); #1;

		sda_in = 1'b0;      // SDA falls — but SCL is LOW
		repeat(3) @(posedge clk); #1;

		sda_in = 1'b1;      // SDA rises — but SCL is LOW
		repeat(3) @(posedge clk); #1;

		// no start or stop should be detected
		if (!start_det_captured)
			$display("PASS [NO_FALSE_START] not triggered ✅");
		else
			$display("FAIL [NO_FALSE_START] falsely triggered");

		if (!stop_det_captured)
			$display("PASS [NO_FALSE_STOP] not triggered ✅");
		else
			$display("FAIL [NO_FALSE_STOP] falsely triggered");

		// ─────────────────────
		// TEST 7 — Repeated START
		// START followed by START (no STOP)
		// ─────────────────────
		$display("--- TEST7: Repeated START ---");
		apply_reset;
		start_det_captured = 1'b0;

		// first START
		scl_in = 1'b1;
		sda_in = 1'b1;
		repeat(2) @(posedge clk); #1;
		sda_in = 1'b0;      // first START
		repeat(3) @(posedge clk); #1;

		if (start_det_captured)
			$display("PASS [FIRST_START_DET] detected ✅");
		else
			$display("FAIL [FIRST_START_DET] not detected");

		// reset capture flag
		start_det_captured = 1'b0;

		// SCL goes LOW then HIGH again
		scl_low(3);
		sda_in = 1'b1;      // SDA goes HIGH
		scl_high(3);

		// second START — repeated start
		sda_in = 1'b0;      // SDA falls again while SCL HIGH
		repeat(3) @(posedge clk); #1;

		if (start_det_captured)
			$display("PASS [REPEATED_START_DET] detected ✅");
		else
			$display("FAIL [REPEATED_START_DET] not detected");

		$display("=== tb_i2c_start_stop DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_start_stop.vcd");
		$dumpvars(0, tb_i2c_start_stop);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | scl=%b sda_in=%b | sda_out=%b sda_oe=%b | start=%b stop=%b done=%b",
				  $time, scl_in, sda_in,
				  sda_out, sda_oe,
				  start_det, stop_det, done);
	end

endmodule