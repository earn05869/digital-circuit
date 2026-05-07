`timescale 1ns/1ps

module tb_i2c_clk_gen;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg         clk;
	reg         rst_n;
	reg         en;
	reg  [15:0] prescaler;
	wire        scl_out;
	wire        scl_rising;
	wire        scl_falling;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_clk_gen u_dut (
		.clk         (clk),
		.resetn      (rst_n),
		.en          (en),
		.prescaler   (prescaler),
		.scl_out     (scl_out),
		.scl_rising  (scl_rising),
		.scl_falling (scl_falling)
	);

	// ─────────────────────────────────────
	// Clock — 10ns period = 100MHz
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Counters for edge measurement
	// ─────────────────────────────────────
	integer rise_count;
	integer fall_count;
	integer rise_time_1;
	integer rise_time_2;
	integer period_measured;

	// count rising and falling pulses
	always @(posedge clk) begin
		if (scl_rising)  rise_count <= rise_count + 1;
		if (scl_falling) fall_count <= fall_count + 1;
	end

	// ─────────────────────────────────────
	// Task — Reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			rst_n     = 1'b0;
			en        = 1'b0;
			prescaler = 16'd0;
			rise_count = 0;
			fall_count = 0;
			@(posedge clk); #1;
			@(posedge clk); #1;
			rst_n = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Wait N SCL cycles
	// ─────────────────────────────────────
	task wait_scl_cycles;
		input integer n;
		integer j;
		integer edge_cnt;
		begin
			edge_cnt = 0;
			while (edge_cnt < n) begin
				@(posedge clk);
				if (scl_rising) edge_cnt = edge_cnt + 1;
			end
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check signal value
	// ─────────────────────────────────────
	task check;
		input       exp_val;
		input [80*8:1] test_name;
		begin
			if (scl_out !== exp_val)
				$display("FAIL [%0s] scl_out=%b exp=%b at t=%0t",
						  test_name, scl_out, exp_val, $time);
			else
				$display("PASS [%0s] scl_out=%b",
						  test_name, scl_out);
		end
	endtask

	// ─────────────────────────────────────
	// Task — Measure SCL period
	// ─────────────────────────────────────
	task measure_period;
		output integer period_ns;
		integer t1;
		integer t2;
		begin
			// wait for first rising edge
			@(posedge scl_out);
			t1 = $time;
			// wait for second rising edge
			@(posedge scl_out);
			t2 = $time;
			period_ns = t2 - t1;
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	integer measured;

	initial begin
		$display("=== tb_i2c_clk_gen START ===");
		$display("--- sys_clk = 100MHz (10ns period) ---");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		apply_reset;
		check(1'b1, "RESET_SCL_HIGH");
		$display("    SCL HIGH on reset = idle bus ✅");

		// ─────────────────────
		// TEST 2 — Enable=0
		// SCL should stay HIGH
		// ─────────────────────
		$display("--- TEST2: Enable=0 SCL stays HIGH ---");
		prescaler = 16'd4;
		en        = 1'b0;
		repeat(20) @(posedge clk); #1;
		check(1'b1, "EN0_SCL_HIGH");
		$display("    SCL stays HIGH when disabled ✅");

		// ─────────────────────
		// TEST 3 — Standard 100kHz
		// sys_clk=100MHz prescaler=499
		// period = (499+1)*2*10ns = 10000ns = 100kHz
		// ─────────────────────
		$display("--- TEST3: Standard 100kHz ---");
		apply_reset;
		prescaler = 16'd499;
		en        = 1'b1;

		measure_period(measured);
		$display("    measured period = %0d ns", measured);
		if (measured >= 9900 && measured <= 10100)
			$display("PASS [100KHZ] period=%0dns (expected 10000ns)", measured);
		else
			$display("FAIL [100KHZ] period=%0dns (expected 10000ns)", measured);

		en = 1'b0;
		@(posedge clk); #1;

		// ─────────────────────
		// TEST 4 — Fast 400kHz
		// prescaler = 124
		// period = (124+1)*2*10ns = 2500ns = 400kHz
		// ─────────────────────
		$display("--- TEST4: Fast 400kHz ---");
		apply_reset;
		prescaler = 16'd124;
		en        = 1'b1;

		measure_period(measured);
		$display("    measured period = %0d ns", measured);
		if (measured >= 2400 && measured <= 2600)
			$display("PASS [400KHZ] period=%0dns (expected 2500ns)", measured);
		else
			$display("FAIL [400KHZ] period=%0dns (expected 2500ns)", measured);

		en = 1'b0;
		@(posedge clk); #1;

		// ─────────────────────
		// TEST 5 — scl_rising pulse
		// must fire exactly when SCL goes HIGH
		// ─────────────────────
		$display("--- TEST5: scl_rising pulse check ---");
		apply_reset;
		prescaler  = 16'd4;     // small prescaler for fast test
		rise_count = 0;
		en         = 1'b1;

		// wait 10 SCL cycles — count rising pulses
		wait_scl_cycles(10);
		@(posedge clk); #1;
		en = 1'b0;

		$display("    rise_count = %0d (expected 10)", rise_count);
		if (rise_count == 10)
			$display("PASS [SCL_RISING] count=%0d", rise_count);
		else
			$display("FAIL [SCL_RISING] count=%0d exp=10", rise_count);

		// ─────────────────────
		// TEST 6 — scl_falling pulse
		// ─────────────────────
		$display("--- TEST6: scl_falling pulse check ---");
		apply_reset;
		prescaler  = 16'd4;
		fall_count = 0;
		en         = 1'b1;

		wait_scl_cycles(10);
		@(posedge clk); #1;
		en = 1'b0;

		$display("    fall_count = %0d (expected 10)", fall_count);
		if (fall_count == 10)
			$display("PASS [SCL_FALLING] count=%0d", fall_count);
		else
			$display("FAIL [SCL_FALLING] count=%0d exp=10", fall_count);

		// ─────────────────────
		// TEST 7 — Disable mid transfer
		// SCL must go HIGH immediately
		// ─────────────────────
		$display("--- TEST7: Disable mid transfer ---");
		apply_reset;
		prescaler = 16'd4;
		en        = 1'b1;

		// wait for SCL to go LOW
		@(negedge scl_out);
		#1;
		// disable right when SCL is LOW
		en = 1'b0;
		@(posedge clk); #1;
		@(posedge clk); #1;

		check(1'b1, "DISABLE_MID_SCL_HIGH");
		$display("    SCL released HIGH after disable ✅");

		// ─────────────────────
		// TEST 8 — Re-enable
		// SCL should restart cleanly
		// ─────────────────────
		$display("--- TEST8: Re-enable SCL ---");
		@(posedge clk); #1;
		rise_count = 0;
		en         = 1'b1;

		wait_scl_cycles(5);
		@(posedge clk); #1;
		en = 1'b0;

		if (rise_count == 5)
			$display("PASS [RE-ENABLE] SCL restarted cleanly");
		else
			$display("FAIL [RE-ENABLE] rise_count=%0d exp=5", rise_count);

		$display("=== tb_i2c_clk_gen DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_clk_gen.vcd");
		$dumpvars(0, tb_i2c_clk_gen);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | en=%b pre=%0d | scl=%b rise=%b fall=%b",
				  $time, en, prescaler,
				  scl_out, scl_rising, scl_falling);
	end

endmodule