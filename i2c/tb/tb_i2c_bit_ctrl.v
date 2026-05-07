`timescale 1ns/1ps

module tb_i2c_bit_ctrl;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg        clk;
	reg        resetn;
	reg        enable;
	reg  [7:0] tx_data;
	reg        load;
	reg        scl_in;
	reg        sda_in;
	reg        ack_phase;

	wire [7:0] rx_data;
	wire       rx_valid;
	wire       byte_done;
	wire       sda_sampled;
	wire       sda_oe;
	wire       sda_out;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_bit_ctrl u_dut (
		.clk         (clk),
		.resetn      (resetn),
		.enable      (enable),
		.tx_data     (tx_data),
		.load        (load),
		.rx_data     (rx_data),
		.rx_valid    (rx_valid),
		.byte_done   (byte_done),
		.sda_sampled (sda_sampled),
		.sda_oe      (sda_oe),
		.sda_out     (sda_out),
		.scl_in      (scl_in),
		.sda_in      (sda_in),
		.ack_phase   (ack_phase)
	);

	// ─────────────────────────────────────
	// Clock — 10ns period = 100MHz
	// ─────────────────────────────────────
	initial clk = 0;
	always  #5 clk = ~clk;

	// ─────────────────────────────────────
	// Task — Reset
	// ─────────────────────────────────────
	task apply_reset;
		begin
			resetn  = 1'b0;
			enable  = 1'b0;
			load    = 1'b0;
			tx_data = 8'h00;
			scl_in  = 1'b1;     // bus idle HIGH
			sda_in  = 1'b1;     // bus idle HIGH
			ack_phase = 1'b0;
			@(posedge clk); #1;
			@(posedge clk); #1;
			resetn = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Load byte into shift reg
	// ─────────────────────────────────────
	task load_byte;
		input [7:0] byte_val;
		begin
			tx_data = byte_val;
			load    = 1'b1;
			@(posedge clk); #1;
			load    = 1'b0;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Toggle SCL one full cycle
	// simulates one SCL clock cycle
	// bit_ctrl reacts to scl_fall then scl_rise
	// ─────────────────────────────────────
	task scl_cycle;
		input sda_val;      // what SDA should be during this bit
		begin
			// SCL falls — bit_ctrl shifts SDA
			scl_in = 1'b0;
			@(posedge clk); #1;
			@(posedge clk); #1;

			// set SDA for this bit (simulating bus)
			sda_in = sda_val;
			@(posedge clk); #1;

			// SCL rises — bit_ctrl samples SDA
			scl_in = 1'b1;
			@(posedge clk); #1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Send full byte (9 cycles = 8 data + ACK)
	// drives SCL and SDA for full byte transfer
	// ─────────────────────────────────────
	task send_byte_cycles;
		input [7:0] rx_byte;    // what slave puts on SDA (RX)
		input       ack_val;    // ACK=0 NACK=1
		integer     i;
		begin
			// 8 data bits MSB first
			for (i = 7; i >= 0; i = i - 1) begin
				scl_cycle(rx_byte[i]);
			end
			// 9th cycle — ACK/NACK
			scl_cycle(ack_val);
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check output
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
	// Task — Check 8-bit value
	// ─────────────────────────────────────
	task check8;
		input [7:0] exp_val;
		input [7:0] got_val;
		input [80*8:1] test_name;
		begin
			if (got_val !== exp_val)
				$display("FAIL [%0s] got=0x%02X exp=0x%02X at t=%0t",
						  test_name, got_val, exp_val, $time);
			else
				$display("PASS [%0s] got=0x%02X",
						  test_name, got_val);
		end
	endtask

	// ─────────────────────────────────────
	// Capture byte_done event
	// ─────────────────────────────────────
	integer byte_done_count;
	always @(posedge clk) begin
		if (byte_done)
			byte_done_count <= byte_done_count + 1;
	end

	// captured sda_sampled value when byte_done
	reg sda_sampled_captured;
	always @(posedge clk) begin
		if (byte_done)
			sda_sampled_captured <= sda_sampled;
	end

	// captured rx_data value when byte_done
	reg [7:0] rx_data_captured;
	always @(posedge clk) begin
		if (byte_done)
			rx_data_captured <= rx_data;
	end

	// ─────────────────────────────────────
	// TX bit capture — what serial_out drove
	// ─────────────────────────────────────
	reg [7:0] tx_captured;
	integer   tx_bit_idx;

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	integer i;
	reg [7:0] exp_byte;

	initial begin
		$display("=== tb_i2c_bit_ctrl START ===");
		byte_done_count = 0;

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		$display("--- TEST1: Reset ---");
		apply_reset;
		check(1'b0, enable,      "RESET_EN_LOW");
		check(1'b0, sda_oe,      "RESET_SDA_OE_LOW");
		check(1'b0, byte_done,   "RESET_BYTE_DONE_LOW");
		check(1'b0, rx_valid,    "RESET_RX_VALID_LOW");

		// ─────────────────────
		// TEST 2 — TX Single Byte 0xA5
		// load 0xA5 = 1010_0101
		// check serial_out MSB first
		// 1,0,1,0,0,1,0,1
		// ─────────────────────
		$display("--- TEST2: TX byte 0xA5 = 1010_0101 ---");
		apply_reset;
		load_byte(8'hA5);
		enable = 1'b1;

		// capture serial_out on each SCL falling edge
		// serial_out changes after scl_fall in bit_ctrl
		begin : tx_check
			reg [7:0] exp_bits;
			exp_bits = 8'hA5; // 1010_0101

			for (i = 7; i >= 0; i = i - 1) begin
				if (i < 7) begin
					// SCL fall → bit_ctrl shifts → serial_out updates
					scl_in = 1'b0;
					@(posedge clk); #1;
					@(posedge clk); #1;
					@(posedge clk); #1;
				end

				// check serial_out = expected bit
				if (sda_out !== exp_bits[i])
					$display("FAIL [TX_BIT%0d] got=%b exp=%b",
							  i, sda_out, exp_bits[i]);
				else
					$display("PASS [TX_BIT%0d] serial_out=%b", i, sda_out);

				if (i == 7) begin
					scl_in = 1'b0;
					@(posedge clk); #1;
					@(posedge clk); #1;
					@(posedge clk); #1;
				end

				// SCL rises
				scl_in = 1'b1;
				@(posedge clk); #1;
				@(posedge clk); #1;
			end

			// ACK cycle — sda_in=0 (ACK from slave)
			scl_cycle(1'b0);
		end

		// ─────────────────────
		// TEST 3 — RX Single Byte
		// simulate slave driving SDA
		// build byte 0xB2 = 1011_0010
		// ─────────────────────
		$display("--- TEST3: RX byte 0xB2 = 1011_0010 ---");
		apply_reset;
		load_byte(8'hFF);   // TX dont care for RX test
		enable         = 1'b1;
		byte_done_count = 0;

		// drive SDA with 0xB2 bits MSB first
		// ACK = 0 at end
		send_byte_cycles(8'hB2, 1'b0);

		// wait settle
		@(posedge clk); #1;
		@(posedge clk); #1;

		check8(8'hB2, rx_data_captured, "RX_BYTE_0xB2");

		// ─────────────────────
		// TEST 4 — byte_done fires once
		// after 9th SCL cycle
		// ─────────────────────
		$display("--- TEST4: byte_done fires once ---");
		apply_reset;
		load_byte(8'hA5);
		enable          = 1'b1;
		byte_done_count = 0;

		send_byte_cycles(8'hA5, 1'b0);
		@(posedge clk); #1;
		@(posedge clk); #1;

		if (byte_done_count == 1)
			$display("PASS [BYTE_DONE] fired %0d time", byte_done_count);
		else
			$display("FAIL [BYTE_DONE] fired %0d times exp=1", byte_done_count);

		// ─────────────────────
		// TEST 5 — sda_sampled = ACK (0)
		// slave sends ACK on 9th bit
		// ─────────────────────
		$display("--- TEST5: sda_sampled ACK=0 ---");
		apply_reset;
		load_byte(8'hA5);
		enable = 1'b1;

		send_byte_cycles(8'hA5, 1'b0);  // ACK=0
		@(posedge clk); #1;
		@(posedge clk); #1;

		check(1'b0, sda_sampled_captured, "SDA_SAMPLED_ACK");
		$display("    sda_sampled=0 = ACK ✅");

		// ─────────────────────
		// TEST 6 — sda_sampled = NACK (1)
		// slave sends NACK on 9th bit
		// ─────────────────────
		$display("--- TEST6: sda_sampled NACK=1 ---");
		apply_reset;
		load_byte(8'hA5);
		enable = 1'b1;

		send_byte_cycles(8'hA5, 1'b1);  // NACK=1
		@(posedge clk); #1;
		@(posedge clk); #1;

		check(1'b1, sda_sampled_captured, "SDA_SAMPLED_NACK");
		$display("    sda_sampled=1 = NACK ✅");

		// ─────────────────────
		// TEST 7 — Disable mid byte
		// sda_oe must release
		// ─────────────────────
		$display("--- TEST7: Disable mid byte ---");
		apply_reset;
		load_byte(8'hA5);
		enable = 1'b1;

		// send 4 bits then disable
		for (i = 0; i < 4; i = i + 1)
			scl_cycle(1'b0);

		enable = 1'b0;
		@(posedge clk); #1;
		@(posedge clk); #1;

		check(1'b0, sda_oe, "DISABLE_SDA_OE_LOW");
		$display("    SDA released after disable ✅");

		// ─────────────────────
		// TEST 8 — Back to back bytes
		// send two bytes no gap
		// byte_done should fire twice
		// ─────────────────────
		$display("--- TEST8: Back to back bytes ---");
		apply_reset;
		byte_done_count = 0;

		// first byte
		load_byte(8'hA5);
		enable = 1'b1;
		send_byte_cycles(8'hA5, 1'b0);  // ACK
		@(posedge clk); #1;

		// immediately load second byte
		load_byte(8'h3C);
		send_byte_cycles(8'h3C, 1'b0);  // ACK
		@(posedge clk); #1;
		@(posedge clk); #1;

		if (byte_done_count == 2)
			$display("PASS [BACK2BACK] byte_done fired %0d times", byte_done_count);
		else
			$display("FAIL [BACK2BACK] byte_done fired %0d times exp=2", byte_done_count);

		// RX data should be last received byte
		check8(8'h3C, rx_data_captured, "BACK2BACK_RX");

		$display("=== tb_i2c_bit_ctrl DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_bit_ctrl.vcd");
		$dumpvars(0, tb_i2c_bit_ctrl);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | en=%b scl=%b sda_in=%b cnt=%0d | sda_out=%b sda_oe=%b byte_done=%b rx=0x%02X",
				  $time, enable, scl_in, sda_in, u_dut.bit_cnt,
				  sda_out, sda_oe, byte_done, rx_data);
	end

endmodule