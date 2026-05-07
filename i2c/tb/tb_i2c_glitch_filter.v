`timescale 1ns/1ps

module tb_i2c_glitch_filter;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg  clk;
	reg  rst_n;
	reg  raw_in;
	wire filtered_out;

	// ─────────────────────────────────────
	// DUT Instantiation
	// FILTER_DEPTH=3 means needs 3 same
	// samples before output changes
	// ─────────────────────────────────────
	i2c_glitch_filter #(
		.THRESHOLD(3)
	) u_dut (
		.clk          (clk),
		.resetn       (rst_n),
		.raw_in       (raw_in),
		.filtered_out (filtered_out)
	);

	// ─────────────────────────────────────
	// Clock — 10ns period
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Task — Reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			rst_n  = 1'b0;
			raw_in = 1'b1;      // bus idle HIGH
			@(posedge clk); #1;
			@(posedge clk); #1;
			rst_n  = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Drive stable input N cycles
	// ─────────────────────────────────────
	task drive_stable;
		input      val;
		input [7:0] cycles;
		integer     j;
		begin
			raw_in = val;
			for (j = 0; j < cycles; j = j + 1)
				@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Inject glitch N cycles wide
	// ─────────────────────────────────────
	task inject_glitch;
		input      glitch_val;   // glitch value (opposite of stable)
		input [7:0] width;       // glitch width in cycles
		integer     j;
		begin
			raw_in = glitch_val;
			for (j = 0; j < width; j = j + 1)
				@(posedge clk); #1;
			raw_in = ~glitch_val;   // restore original
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check output
	// ─────────────────────────────────────
	task check;
		input       exp_out;
		input [80*8:1] test_name;
		begin
			if (filtered_out !== exp_out)
				$display("FAIL [%0s] got=%b exp=%b at t=%0t",
						  test_name, filtered_out, exp_out, $time);
			else
				$display("PASS [%0s] filtered_out=%b",
						  test_name, filtered_out);
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	initial begin
		$display("=== tb_i2c_glitch_filter START ===");
		$display("--- FILTER_DEPTH = 3 ---");
		$display("--- needs 3 same samples to change output ---");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		apply_reset;
		check(1'b1, "RESET_HIGH");
		$display("    output HIGH on reset = bus idle ✅");

		// ─────────────────────
		// TEST 2 — Stable HIGH
		// drive HIGH for 5 cycles
		// output should stay HIGH
		// ─────────────────────
		drive_stable(1'b1, 5);
		check(1'b1, "STABLE_HIGH");

		// ─────────────────────
		// TEST 3 — Stable LOW
		// drive LOW for FILTER_DEPTH+ cycles
		// output should go LOW
		// ─────────────────────
		drive_stable(1'b0, 5);  // 5 cycles > depth=3
		check(1'b0, "STABLE_LOW");

		// ─────────────────────
		// TEST 4 — Glitch on HIGH line
		// line is HIGH
		// inject 1 cycle LOW spike
		// output must stay HIGH
		// ─────────────────────
		$display("--- TEST4: Glitch on HIGH line ---");
		drive_stable(1'b1, 5);      // make sure output = HIGH
		check(1'b1, "PRE_GLITCH_HIGH");

		inject_glitch(1'b0, 1);     // 1 cycle LOW glitch
		// output should NOT change — glitch too short
		check(1'b1, "GLITCH_1CYC_ON_HIGH");
		$display("    1 cycle glitch suppressed ✅");

		// ─────────────────────
		// TEST 5 — Glitch on LOW line
		// line is LOW
		// inject 1 cycle HIGH spike
		// output must stay LOW
		// ─────────────────────
		$display("--- TEST5: Glitch on LOW line ---");
		drive_stable(1'b0, 5);      // make sure output = LOW
		check(1'b0, "PRE_GLITCH_LOW");

		inject_glitch(1'b1, 1);     // 1 cycle HIGH glitch
		// output should NOT change
		@(posedge clk); #1;         // wait settle
		check(1'b0, "GLITCH_1CYC_ON_LOW");
		$display("    1 cycle glitch suppressed ✅");

		// ─────────────────────
		// TEST 6 — 2 cycle glitch
		// still shorter than FILTER_DEPTH=3
		// output should still hold
		// ─────────────────────
		$display("--- TEST6: 2 cycle glitch ---");
		drive_stable(1'b1, 5);
		inject_glitch(1'b0, 2);     // 2 cycle glitch
		@(posedge clk); #1;
		check(1'b1, "GLITCH_2CYC_ON_HIGH");
		$display("    2 cycle glitch suppressed ✅");

		// ─────────────────────
		// TEST 7 — Real Transition
		// drive LOW for THRESHOLD cycles
		// output SHOULD change
		// ─────────────────────
		$display("--- TEST7: Real LOW transition ---");
		drive_stable(1'b1, 5);      // start HIGH
		check(1'b1, "BEFORE_REAL_TRANS");

		drive_stable(1'b0, 4);      // 4 cycles > depth=3
		check(1'b0, "REAL_TRANS_LOW");
		$display("    real transition accepted ✅");

		// ─────────────────────
		// TEST 8 — Real HIGH transition
		// ─────────────────────
		$display("--- TEST8: Real HIGH transition ---");
		drive_stable(1'b1, 4);      // 4 cycles > depth=3
		check(1'b1, "REAL_TRANS_HIGH");
		$display("    real transition accepted ✅");

		// ─────────────────────
		// TEST 9 — Multiple Glitches
		// several short spikes
		// all must be suppressed
		// ─────────────────────
		$display("--- TEST9: Multiple glitches ---");
		drive_stable(1'b1, 5);

		inject_glitch(1'b0, 1);     // spike 1
		@(posedge clk); #1;
		inject_glitch(1'b0, 1);     // spike 2
		@(posedge clk); #1;
		inject_glitch(1'b0, 1);     // spike 3
		@(posedge clk); #1;

		check(1'b1, "MULTI_GLITCH");
		$display("    multiple glitches suppressed ✅");

		$display("=== tb_i2c_glitch_filter DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_glitch_filter.vcd");
		$dumpvars(0, tb_i2c_glitch_filter);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | raw_in=%b | filtered_out=%b",
				  $time, raw_in, filtered_out);
	end

endmodule