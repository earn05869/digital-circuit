`timescale 1ns/1ps

module tb_i2c_shift_reg;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg        clk;
	reg        rst_n;
	reg        shift_tx;
	reg        shift_rx;
	reg        load;
	reg        serial_in;
	reg  [7:0] data_in;
	wire       serial_out;
	wire [7:0] data_out;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_shift_reg u_dut (
		.clk        (clk),
		.rst_n      (rst_n),
		.shift_tx   (shift_tx),
		.shift_rx   (shift_rx),
		.load       (load),
		.serial_in  (serial_in),
		.data_in    (data_in),
		.serial_out (serial_out),
		.data_out   (data_out)
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
			rst_n     = 1'b0;
			shift_tx  = 1'b0;
			shift_rx  = 1'b0;
			load      = 1'b0;
			serial_in = 1'b0;
			data_in   = 8'h00;
			@(posedge clk); #1;
			@(posedge clk); #1;
			rst_n = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Load Byte
	// ─────────────────────────────────────
	task load_byte;
		input [7:0] byte_val;
		begin
			data_in = byte_val;
			load    = 1'b1;
			@(posedge clk); #1;
			load    = 1'b0;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Shift One Bit
	// ─────────────────────────────────────
	task shift_one;
		input ser_in;
		begin
			serial_in = ser_in;
			shift_tx  = 1'b1;
			shift_rx  = 1'b1;
			@(posedge clk); #1;
			shift_tx  = 1'b0;
			shift_rx  = 1'b0;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check serial_out
	// ─────────────────────────────────────
	task check_serial;
		input       exp_serial;
		input [7:0] exp_data;
		input [80*8:1] test_name;
		begin
			if (serial_out !== exp_serial || data_out !== exp_data) begin
				$display("FAIL [%0s] serial=%b(exp %b) data=0x%02X(exp 0x%02X)",
						  test_name, serial_out, exp_serial,
						  data_out, exp_data);
			end else begin
				$display("PASS [%0s] serial=%b data=0x%02X",
						  test_name, serial_out, data_out);
			end
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	integer     i;
	reg   [7:0] tx_byte;
	reg   [7:0] rx_byte;
	reg         exp_bit;

	initial begin
		$display("=== tb_i2c_shift_reg START ===");

		// ─────────────────────
		// TEST 1 — Reset
		// ─────────────────────
		apply_reset;
		// after reset mem=0xFF → serial_out=1
		if (serial_out !== 1'b1)
			$display("FAIL [RESET] serial_out=%b expected 1", serial_out);
		else
			$display("PASS [RESET] serial_out=1 after reset");

		// ─────────────────────
		// TEST 2 — Parallel Load
		// ─────────────────────
		load_byte(8'hA5);
		// data_out should be 0xA5
		// serial_out should be MSB = 1 (0xA5 = 1010_0101)
		check_serial(1'b1, 8'hA5, "LOAD_0xA5");

		// ─────────────────────
		// TEST 3 — TX Shift Out
		// shift all 8 bits and verify serial_out MSB first
		// 0xA5 = 1010_0101
		// ─────────────────────
		load_byte(8'hA5);
		tx_byte = 8'hA5;

		$display("--- TEST3: TX shift out 0xA5 = 1010_0101 ---");
		for (i = 7; i >= 0; i = i - 1) begin
			exp_bit = tx_byte[i];
			if (serial_out !== exp_bit)
				$display("FAIL [TX_BIT%0d] got=%b exp=%b", i, serial_out, exp_bit);
			else
				$display("PASS [TX_BIT%0d] serial_out=%b", i, serial_out);
			shift_one(1'b0);    // serial_in dont care for TX
		end

		// ─────────────────────
		// TEST 4 — RX Shift In
		// shift in byte 0xB2 = 1011_0010
		// send MSB first
		// ─────────────────────
		apply_reset;
		rx_byte = 8'hB2;    // 1011_0010

		$display("--- TEST4: RX shift in 0xB2 = 1011_0010 ---");
		for (i = 7; i >= 0; i = i - 1) begin
			shift_one(rx_byte[i]);  // shift in MSB first
		end
		// after 8 shifts data_out should = 0xB2
		if (data_out !== rx_byte)
			$display("FAIL [RX_BYTE] got=0x%02X exp=0x%02X",
					  data_out, rx_byte);
		else
			$display("PASS [RX_BYTE] data_out=0x%02X", data_out);

		// ─────────────────────
		// TEST 5 — Load then TX
		// load 0xFF = 1111_1111
		// all serial_out should be 1
		// ─────────────────────
		apply_reset;
		load_byte(8'hFF);

		$display("--- TEST5: TX shift 0xFF all bits should be 1 ---");
		for (i = 0; i < 8; i = i + 1) begin
			if (serial_out !== 1'b1)
				$display("FAIL [TX_FF_BIT%0d] serial_out=%b", i, serial_out);
			else
				$display("PASS [TX_FF_BIT%0d] serial_out=1", i);
			shift_one(1'b0);
		end

		// ─────────────────────
		// TEST 6 — Load then TX 0x00
		// 0x00 = 0000_0000
		// all serial_out should be 0
		// ─────────────────────
		apply_reset;
		load_byte(8'h00);

		$display("--- TEST6: TX shift 0x00 all bits should be 0 ---");
		for (i = 0; i < 8; i = i + 1) begin
			if (serial_out !== 1'b0)
				$display("FAIL [TX_00_BIT%0d] serial_out=%b", i, serial_out);
			else
				$display("PASS [TX_00_BIT%0d] serial_out=0", i);
			shift_one(1'b0);
		end

		// ─────────────────────
		// TEST 7 — RX Full Random Byte
		// shift in 0x37 = 0011_0111
		// ─────────────────────
		apply_reset;
		rx_byte = 8'h37;

		$display("--- TEST7: RX shift in 0x37 = 0011_0111 ---");
		for (i = 7; i >= 0; i = i - 1)
			shift_one(rx_byte[i]);

		if (data_out !== rx_byte)
			$display("FAIL [RX_0x37] got=0x%02X exp=0x%02X",
					  data_out, rx_byte);
		else
			$display("PASS [RX_0x37] data_out=0x%02X", data_out);

		$display("=== tb_i2c_shift_reg DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_shift_reg.vcd");
		$dumpvars(0, tb_i2c_shift_reg);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | load=%b shift_tx=%b shift_rx=%b sin=%b | sout=%b dout=0x%02X",
				  $time, load, shift_tx, shift_rx, serial_in, serial_out, data_out);
	end

endmodule