`timescale 1ns/1ps

module tb_i2c_bit_cnt;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg        clk;
	reg        resetn;
	reg        enable;
	reg        clear;
	wire [3:0] count;
	wire       done;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_bit_cnt u_dut (
		.clk       (clk),
		.resetn    (resetn),
		.enable    (enable),
		.clear     (clear),
		.max_count (4'd8),
		.count     (count),
		.done      (done)
	);

	// ─────────────────────────────────────
	// Clock Generation — 10ns period
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Task — apply reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			resetn = 1'b0;
			enable = 1'b0;
			clear  = 1'b0;
			@(posedge clk); #1;
			@(posedge clk); #1;
			resetn = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — check value
	// ─────────────────────────────────────
	task check;
		input [3:0] exp_count;
		input       exp_done;
		input [63:0] test_name;
		begin
			if (count !== exp_count || done !== exp_done) begin
				$display("FAIL [%s] cnt=%0d(exp %0d) done=%b(exp %b)",
						  test_name, count, exp_count, done, exp_done);
			end else begin
				$display("PASS [%s] cnt=%0d done=%b",
						  test_name, count, done);
			end
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	integer i;

	initial begin
		$display("=== tb_i2c_bit_cnt START ===");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		apply_reset;
		check(4'd0, 1'b0, "RESET");

		// ─────────────────────
		// TEST 2 — Count Up
		// ─────────────────────
		enable = 1'b1;
		for (i = 1; i <= 7; i = i + 1) begin
			@(posedge clk); #1;
			check(i, 1'b0, "COUNT_UP");
		end

		// ─────────────────────
		// TEST 3 — Done at 8
		// ─────────────────────
		@(posedge clk); #1;
		check(4'd8, 1'b1, "DONE_AT_8");

		// ─────────────────────
		// TEST 4 — Hold at 8
		// ─────────────────────
		@(posedge clk); #1;
		@(posedge clk); #1;
		check(4'd8, 1'b1, "HOLD_AT_8");

		// ─────────────────────
		// TEST 5 — Enable=0 Holds Count
		// ─────────────────────
		enable = 1'b0;
		apply_reset;
		enable = 1'b1;
		@(posedge clk); #1;
		@(posedge clk); #1;
		@(posedge clk); #1;
		enable = 1'b0;    // stop at 3
		@(posedge clk); #1;
		@(posedge clk); #1;
		check(4'd3, 1'b0, "EN_HOLD");

		// ─────────────────────
		// TEST 6 — Clear
		// ─────────────────────
		enable = 1'b1;
		clear  = 1'b1;
		@(posedge clk); #1;
		clear  = 1'b0;
		check(4'd0, 1'b0, "CLEAR");

		// ─────────────────────
		// TEST 7 — Full Cycle Again After Clear
		// ─────────────────────
		for (i = 1; i <= 8; i = i + 1)
			@(posedge clk); #1;
		check(4'd8, 1'b1, "FULL_CYCLE");

		$display("=== tb_i2c_bit_cnt DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_bit_cnt.vcd");
		$dumpvars(0, tb_i2c_bit_cnt);
	end

	// ─────────────────────────────────────
	// Monitor — print every change
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | en=%b clr=%b | cnt=%0d done=%b",
				  $time, enable, clear, count, done);
	end

endmodule