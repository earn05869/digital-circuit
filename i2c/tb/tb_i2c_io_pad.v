`timescale 1ns/1ps

module tb_i2c_io_pad;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg  clk;
	reg  rst_n;
	reg  tx_data;
	reg  oe;
	wire rx_data;
	wire sda;           // bidirectional bus pin

	// ─────────────────────────────────────
	// External pull-up resistor simulation
	// SDA floats HIGH when no one drives it
	// ─────────────────────────────────────
	reg  ext_drive;         // external device drives SDA
	reg  ext_value;         // external device value

	// simulate pull-up + external device
	assign sda = ext_drive ? ext_value : 1'bz;

	// ─────────────────────────────────────
	// DUT Instantiation
	// ─────────────────────────────────────
	i2c_io_pad u_dut (
		.clk      (clk),
		.resetn    (rst_n),
		.tx_data  (tx_data),
		.output_enable       (oe),
		.rx_data  (rx_data),
		.sda      (sda)
	);

	// ─────────────────────────────────────
	// Pull up resistor — bus HIGH when idle
	// simulated as weak pull-up
	// ─────────────────────────────────────
	assign (weak1, highz0) sda = 1'b1;

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
			tx_data   = 1'b1;
			oe        = 1'b0;
			ext_drive = 1'b0;
			ext_value = 1'b1;
			@(posedge clk); #1;
			@(posedge clk); #1;
			rst_n = 1'b1;
			@(posedge clk); #1;
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check rx_data
	// ─────────────────────────────────────
	task check_rx;
		input       exp_val;
		input [80*8:1] test_name;
		begin
			if (rx_data !== exp_val)
				$display("FAIL [%0s] rx_data=%b exp=%b at t=%0t",
						  test_name, rx_data, exp_val, $time);
			else
				$display("PASS [%0s] rx_data=%b",
						  test_name, rx_data);
		end
	endtask

	// ─────────────────────────────────────
	// Task — Check SDA bus value
	// ─────────────────────────────────────
	task check_sda;
		input       exp_val;
		input [80*8:1] test_name;
		begin
			if (sda !== exp_val)
				$display("FAIL [%0s] sda=%b exp=%b at t=%0t",
						  test_name, sda, exp_val, $time);
			else
				$display("PASS [%0s] sda=%b",
						  test_name, sda);
		end
	endtask

	// ─────────────────────────────────────
	// Main Stimulus
	// ─────────────────────────────────────
	initial begin
		$display("=== tb_i2c_io_pad START ===");

		// ─────────────────────
		// TEST 1 — Reset
		// rx_data=1 bus idle
		// ─────────────────────
		$display("--- TEST1: Reset ---");
		apply_reset;
		@(posedge clk); #1;

		check_rx(1'b1, "RESET_RX_HIGH");
		$display("    rx_data=1 on reset = bus idle ✅");

		// ─────────────────────
		// TEST 2 — OE=0 Receive Mode
		// DUT releases SDA
		// pull-up takes SDA HIGH
		// ─────────────────────
		$display("--- TEST2: OE=0 receive mode ---");
		oe      = 1'b0;
		tx_data = 1'b0;     // doesnt matter — OE=0
		@(posedge clk); #1;
		@(posedge clk); #1;

		// SDA should be HIGH from pull-up (DUT not driving)
		check_sda(1'b1, "OE0_SDA_PULLUP_HIGH");
		$display("    SDA=1 from pull-up when OE=0 ✅");

		// ─────────────────────
		// TEST 3 — OE=1 tx=0
		// DUT drives SDA LOW
		// ─────────────────────
		$display("--- TEST3: OE=1 tx=0 drive LOW ---");
		oe      = 1'b1;
		tx_data = 1'b0;
		@(posedge clk); #1;
		@(posedge clk); #1;

		check_sda(1'b0, "OE1_TX0_SDA_LOW");
		$display("    SDA=0 DUT pulls bus LOW ✅");

		// ─────────────────────
		// TEST 4 — OE=1 tx=1
		// DUT releases SDA (tri-state)
		// pull-up takes HIGH
		// ─────────────────────
		$display("--- TEST4: OE=1 tx=1 release SDA ---");
		oe      = 1'b1;
		tx_data = 1'b1;
		@(posedge clk); #1;
		@(posedge clk); #1;

		check_sda(1'b1, "OE1_TX1_SDA_HIGH");
		$display("    SDA=1 DUT releases bus ✅");

		// ─────────────────────
		// TEST 5 — Sample SDA HIGH
		// external device releases
		// DUT receives HIGH
		// ─────────────────────
		$display("--- TEST5: Sample SDA HIGH ---");
		oe        = 1'b0;       // receive mode
		ext_drive = 1'b0;       // no external drive
		@(posedge clk); #1;
		@(posedge clk); #1;

		check_rx(1'b1, "SAMPLE_SDA_HIGH");
		$display("    rx_data=1 sampled from bus ✅");

		// ─────────────────────
		// TEST 6 — Sample SDA LOW
		// external device drives LOW
		// DUT receives LOW
		// ─────────────────────
		$display("--- TEST6: Sample SDA LOW ---");
		oe        = 1'b0;       // receive mode
		ext_drive = 1'b1;       // external drives
		ext_value = 1'b0;       // drives LOW
		@(posedge clk); #1;
		@(posedge clk); #1;

		check_rx(1'b0, "SAMPLE_SDA_LOW");
		$display("    rx_data=0 sampled from bus ✅");

		// ─────────────────────
		// TEST 7 — Bus Contention
		// DUT drives LOW
		// external also drives LOW
		// bus = LOW (both agree)
		// ─────────────────────
		$display("--- TEST7: Bus contention both LOW ---");
		oe        = 1'b1;
		tx_data   = 1'b0;       // DUT drives LOW
		ext_drive = 1'b1;
		ext_value = 1'b0;       // external drives LOW
		@(posedge clk); #1;
		@(posedge clk); #1;

		check_sda(1'b0, "CONTENTION_BOTH_LOW");
		$display("    SDA=0 both devices pull LOW ✅");

		// ─────────────────────
		// TEST 8 — Arbitration
		// DUT drives HIGH (releases)
		// external drives LOW
		// external wins = bus LOW
		// This is how I2C arbitration works
		// ─────────────────────
		$display("--- TEST8: Arbitration DUT=H ext=L ---");
		oe        = 1'b1;
		tx_data   = 1'b1;       // DUT releases (tx=1 = Z)
		ext_drive = 1'b1;
		ext_value = 1'b0;       // external drives LOW
		@(posedge clk); #1;
		@(posedge clk); #1;

		// bus should be LOW — external wins
		check_sda(1'b0, "ARB_EXT_WINS_LOW");
		// DUT should sample LOW — sees it lost arbitration
		check_rx(1'b0,  "ARB_RX_SEES_LOW");
		$display("    external wins arbitration ✅");
		$display("    DUT samples LOW = detects arb loss ✅");

		// ─────────────────────
		// TEST 9 — TX sequence
		// simulate sending byte 0xA5
		// check SDA matches each bit
		// ─────────────────────
		$display("--- TEST9: TX sequence 0xA5 = 1010_0101 ---");
		ext_drive = 1'b0;   // no external interference
		oe        = 1'b1;

		begin : tx_seq
			reg [7:0] byte_val;
			integer   i;
			byte_val = 8'hA5;   // 1010_0101

			for (i = 7; i >= 0; i = i - 1) begin
				tx_data = byte_val[i];
				@(posedge clk); #1;
				@(posedge clk); #1;

				if (sda !== byte_val[i])
					$display("FAIL [TX_BIT%0d] sda=%b exp=%b",
							  i, sda, byte_val[i]);
				else
					$display("PASS [TX_BIT%0d] sda=%b", i, sda);
			end
		end

		// ─────────────────────
		// TEST 10 — Release after TX
		// OE goes LOW
		// SDA returns to HIGH
		// ─────────────────────
		$display("--- TEST10: Release after TX ---");
		oe = 1'b0;
		@(posedge clk); #1;
		@(posedge clk); #1;

		check_sda(1'b1, "RELEASE_SDA_HIGH");
		$display("    SDA returns HIGH after release ✅");

		$display("=== tb_i2c_io_pad DONE ===");
		$finish;
	end

	// ─────────────────────────────────────
	// Waveform Dump
	// ─────────────────────────────────────
	initial begin
		$dumpfile("tb_i2c_io_pad.vcd");
		$dumpvars(0, tb_i2c_io_pad);
	end

	// ─────────────────────────────────────
	// Monitor
	// ─────────────────────────────────────
	initial begin
		$monitor("t=%0t | oe=%b tx=%b ext=%b extval=%b | sda=%b rx=%b",
				  $time, oe, tx_data,
				  ext_drive, ext_value,
				  sda, rx_data);
	end

endmodule