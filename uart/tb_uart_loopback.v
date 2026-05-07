module tb_loopback_uart();
	reg  clk;
	reg  resetn;
	reg  [1:0] baud_sel;    // 00=9600, 01=19200, 10=38400, 11=115200

	integer err_count;
	integer k;
	integer n;

	// TX
	reg  [7:0] tx_data;
	reg        tx_start;
	wire       tx_busy;
	wire       txd;

	// RX
	// FIX 1: declare as wire and tie to txd for loopback
	wire       rxd;
	wire [7:0] rx_data;
	wire       rx_done;
	wire       rx_framing_err;

	// FIX 1: loopback — TX output drives RX input
	assign rxd = txd;

	// ------------------------------------------------------------------ clock
	initial clk = 0;
	always #10 clk = ~clk;   // 50 MHz  →  20 ns period

	// ------------------------------------------------------------------ DUT
	uart #(
		.CLK_FREQ  (50_000_000),
		.OVERSAMPLE(16)
	) uut (
		.clk           (clk),
		.rst_n         (resetn),
		.baud_sel      (baud_sel),
		.tx_data       (tx_data),
		.tx_start      (tx_start),
		.tx_busy       (tx_busy),
		.txd           (txd),
		.rxd           (rxd),
		.rx_data       (rx_data),
		.rx_done       (rx_done),
		.rx_framing_err(rx_framing_err)
	);

	// ------------------------------------------------------------------ tasks
	task send_byte;
		input [7:0] data;
		begin
			wait (!tx_busy);            // ensure UART is free
			@(posedge clk);
			tx_data  <= data;
			tx_start <= 1'b1;
			@(posedge clk);
			tx_start <= 1'b0;
			wait ( tx_busy);            // transmission started
			// FIX 2: also wait for transmission to FINISH before returning
			wait (!tx_busy);
		end
	endtask

	task check_byte;
		input [7:0] expected;
		begin
			// FIX 3: edge-sensitive — catches a single-cycle rx_done pulse reliably
			@(posedge rx_done);
			@(posedge clk);             // let rx_data settle

			if (rx_framing_err) begin
				$display("FAIL [%0t] framing error", $time);
				err_count = err_count + 1;
			end else if (rx_data !== expected) begin
				$display("FAIL [%0t] expected 0x%02X, got 0x%02X",
						 $time, expected, rx_data);
				err_count = err_count + 1;
			end else
				$display("PASS [%0t] received 0x%02X", $time, rx_data);
		end
	endtask

	// Change baud when idle, allow generator to settle, then round-trip one byte.
	task roundtrip_at_baud;
		input [1:0] rate;
		input [7:0] data;
		begin
			wait (!tx_busy);
			@(posedge clk);
			baud_sel <= rate;
			repeat (20) @(posedge clk);
			fork send_byte(data); check_byte(data); join
		end
	endtask

	// ------------------------------------------------------------------ stimulus
	initial begin
		err_count = 0;

		$dumpfile("tb_uart_loopback.vcd");
		$dumpvars(0, tb_loopback_uart);

		// FIX 4: initialise tx_data so DUT inputs are never X
		resetn   = 1'b0;
		tx_start = 1'b0;
		tx_data  = 8'h00;
		baud_sel = 2'b00;   // 9600 baud
		#100;
		resetn = 1'b1;
		#100;

		// --- basic round-trip @ 9600
		$display("== basic @ 9600");
		fork send_byte(8'h12); check_byte(8'h12); join
		fork send_byte(8'h34); check_byte(8'h34); join

		// --- edge patterns (parity / bit toggling) @ 9600
		$display("== edge patterns @ 9600");
		fork send_byte(8'h00); check_byte(8'h00); join
		fork send_byte(8'hFF); check_byte(8'hFF); join
		fork send_byte(8'h55); check_byte(8'h55); join
		fork send_byte(8'hAA); check_byte(8'hAA); join

		// --- counting sequence @ 9600
		$display("== counting bytes @ 9600");
		for (k = 0; k < 8; k = k + 1)
			fork
				send_byte(k[7:0]);
				check_byte(k[7:0]);
			join

		// --- all standard baud selections
		$display("== baud sweep");
		roundtrip_at_baud(2'b00, 8'hA5);
		roundtrip_at_baud(2'b01, 8'h5A);
		roundtrip_at_baud(2'b10, 8'hC3);
		roundtrip_at_baud(2'b11, 8'h3C);

		// --- return to 9600 and burst without changing baud
		$display("== burst @ 9600");
		baud_sel <= 2'b00;
		wait (!tx_busy);
		repeat (20) @(posedge clk);
		for (n = 0; n < 16; n = n + 1)
			fork
				send_byte(8'h10 + n[7:0]);
				check_byte(8'h10 + n[7:0]);
			join

		// --- deassert reset after traffic: UART should still work
		$display("== after async reset pulse");
		wait (!tx_busy);
		@(posedge clk);
		resetn <= 1'b0;
		repeat (10) @(posedge clk);
		resetn <= 1'b1;
		repeat (20) @(posedge clk);
		fork send_byte(8'hDE); check_byte(8'hDE); join
		fork send_byte(8'hAD); check_byte(8'hAD); join

		if (err_count != 0)
			$display("--- Done: %0d error(s) ---", err_count);
		else
			$display("--- All Tests Passed ---");
		$finish;
	end

endmodule