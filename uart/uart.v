// Full-duplex UART: baud generator + transmitter + receiver (8E1: 8 data bits, even parity, 1 stop).
module uart #(
	parameter CLK_FREQ   = 50_000_000,
	parameter OVERSAMPLE = 16
) (
	input  wire       clk,
	input  wire       rst_n,
	input  wire [1:0] baud_sel, // 00=9600, 01=19200, 10=38400, 11=115200
	// TX
	input  wire [7:0] tx_data,
	input  wire       tx_start,
	output wire       tx_busy,
	output wire       txd,
	// RX
	input  wire       rxd,
	output wire [7:0] rx_data,
	output wire       rx_done,
	output wire       rx_framing_err
);

	wire baud_tick;

	baud_rate_gen #(
		.CLK_FREQ(CLK_FREQ),
		.OVERSAMPLE(OVERSAMPLE)
	) u_baud (
		.clk(clk),
		.reset_n(rst_n),
		.baud_sel(baud_sel),
		.tick(baud_tick)
	);

	uart_transmitter #(
		.OVERSAMPLE(OVERSAMPLE)
	) u_tx (
		.clk(clk),
		.resetn(rst_n),
		.baud_tick(baud_tick),
		.din(tx_data),
		.start(tx_start),
		.dout(txd),
		.busy(tx_busy)
	);

	uart_receiver #(
		.OVERSAMPLE(OVERSAMPLE)
	) u_rx (
		.clk(clk),
		.reset(~rst_n),
		.baud_tick(baud_tick),
		.in(rxd),
		.out_byte(rx_data),
		.done(rx_done),
		.framing_err(rx_framing_err)
	);

endmodule
