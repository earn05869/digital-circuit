// Two UART instances cross-connected: A.txd -> B.rxd, B.txd -> A.rxd (full duplex).
module tb_uart_dual();
	reg  clk;
	reg  rst_n;
	reg  [1:0] baud_sel;

	integer err_count;

	// UART A
	reg  [7:0] a_tx_data;
	reg        a_tx_start;
	wire       a_tx_busy;
	wire       a_txd;
	wire [7:0] a_rx_data;
	wire       a_rx_done;
	wire       a_rx_framing_err;

	// UART B
	reg  [7:0] b_tx_data;
	reg        b_tx_start;
	wire       b_tx_busy;
	wire       b_txd;
	wire [7:0] b_rx_data;
	wire       b_rx_done;
	wire       b_rx_framing_err;

	// Cross-connect
	wire a_to_b;
	wire b_to_a;
	assign a_to_b = a_txd;
	assign b_to_a = b_txd;

	// ------------------------------------------------------------------ clock
	initial clk = 0;
	always #10 clk = ~clk;   // 50 MHz

	// ------------------------------------------------------------------ DUTs
	uart #(
		.CLK_FREQ  (50_000_000),
		.OVERSAMPLE(16)
	) u_a (
		.clk           (clk),
		.rst_n         (rst_n),
		.baud_sel      (baud_sel),
		.tx_data       (a_tx_data),
		.tx_start      (a_tx_start),
		.tx_busy       (a_tx_busy),
		.txd           (a_txd),
		.rxd           (b_to_a),
		.rx_data       (a_rx_data),
		.rx_done       (a_rx_done),
		.rx_framing_err(a_rx_framing_err)
	);

	uart #(
		.CLK_FREQ  (50_000_000),
		.OVERSAMPLE(16)
	) u_b (
		.clk           (clk),
		.rst_n         (rst_n),
		.baud_sel      (baud_sel),
		.tx_data       (b_tx_data),
		.tx_start      (b_tx_start),
		.tx_busy       (b_tx_busy),
		.txd           (b_txd),
		.rxd           (a_to_b),
		.rx_data       (b_rx_data),
		.rx_done       (b_rx_done),
		.rx_framing_err(b_rx_framing_err)
	);

	// ------------------------------------------------------------------ tasks: A TX
	task send_a;
		input [7:0] data;
		begin
			wait (!a_tx_busy);
			@(posedge clk);
			a_tx_data  <= data;
			a_tx_start <= 1'b1;
			@(posedge clk);
			a_tx_start <= 1'b0;
			wait (a_tx_busy);
			wait (!a_tx_busy);
		end
	endtask

	// ------------------------------------------------------------------ tasks: B TX
	task send_b;
		input [7:0] data;
		begin
			wait (!b_tx_busy);
			@(posedge clk);
			b_tx_data  <= data;
			b_tx_start <= 1'b1;
			@(posedge clk);
			b_tx_start <= 1'b0;
			wait (b_tx_busy);
			wait (!b_tx_busy);
		end
	endtask

	task check_a;
		input [7:0] expected;
		begin
			@(posedge a_rx_done);
			@(posedge clk);
			if (a_rx_framing_err) begin
				$display("FAIL [%0t] A framing error", $time);
				err_count = err_count + 1;
			end else if (a_rx_data !== expected) begin
				$display("FAIL [%0t] A expected 0x%02X, got 0x%02X",
						 $time, expected, a_rx_data);
				err_count = err_count + 1;
			end else
				$display("PASS [%0t] A received 0x%02X", $time, a_rx_data);
		end
	endtask

	task check_b;
		input [7:0] expected;
		begin
			@(posedge b_rx_done);
			@(posedge clk);
			if (b_rx_framing_err) begin
				$display("FAIL [%0t] B framing error", $time);
				err_count = err_count + 1;
			end else if (b_rx_data !== expected) begin
				$display("FAIL [%0t] B expected 0x%02X, got 0x%02X",
						 $time, expected, b_rx_data);
				err_count = err_count + 1;
			end else
				$display("PASS [%0t] B received 0x%02X", $time, b_rx_data);
		end
	endtask

	task roundtrip_baud;
		input [1:0] rate;
		begin
			wait (!a_tx_busy && !b_tx_busy);
			@(posedge clk);
			baud_sel <= rate;
			repeat (20) @(posedge clk);
		end
	endtask

	// ------------------------------------------------------------------ stimulus
	initial begin
		err_count = 0;

		$dumpfile("tb_uart_dual.vcd");
		$dumpvars(0, tb_uart_dual);

		rst_n     = 1'b0;
		a_tx_start = 1'b0;
		b_tx_start = 1'b0;
		a_tx_data  = 8'h00;
		b_tx_data  = 8'h00;
		baud_sel   = 2'b00;
		#100;
		rst_n = 1'b1;
		#100;

		$display("== A -> B @ 9600");
		fork send_a(8'h12); check_b(8'h12); join

		$display("== B -> A @ 9600");
		fork send_b(8'h34); check_a(8'h34); join

		$display("== alternating directions");
		fork send_a(8'h55); check_b(8'h55); join
		fork send_b(8'hAA); check_a(8'hAA); join
		fork send_a(8'h00); check_b(8'h00); join
		fork send_b(8'hFF); check_a(8'hFF); join

		$display("== full duplex (both links at once)");
		fork
			send_a(8'hC3);
			send_b(8'h3C);
			check_b(8'hC3);
			check_a(8'h3C);
		join

		$display("== baud 115200 both directions");
		roundtrip_baud(2'b11);
		fork send_a(8'hDE); check_b(8'hDE); join
		fork send_b(8'hAD); check_a(8'hAD); join

		$display("== after reset");
		wait (!a_tx_busy && !b_tx_busy);
		@(posedge clk);
		rst_n <= 1'b0;
		repeat (10) @(posedge clk);
		rst_n <= 1'b1;
		repeat (20) @(posedge clk);
		baud_sel <= 2'b00;
		repeat (20) @(posedge clk);
		fork send_a(8'h01); check_b(8'h01); join
		fork send_b(8'hFE); check_a(8'hFE); join

		if (err_count != 0)
			$display("--- Done: %0d error(s) ---", err_count);
		else
			$display("--- All Tests Passed ---");
		$finish;
	end

endmodule
