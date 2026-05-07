`timescale 1ns/1ps
`default_nettype none

/*
** ASYNCHRONOUS FIFO (First-In First-Out)
**
** An asynchronous FIFO is a data buffer used to transfer data
** between two modules operating under different clock signals.
**
** Data is written and read in the same order:
** first data in → first data out.
**
** FEATURES:
** - Separate clocks:
**     wr_clk for write operations
**     rd_clk for read operations
** - Uses independent write pointer (w_ptr) and read pointer (r_ptr)
** - Requires pointer synchronization between clock domains
**
** OPERATIONS:
** - Write: stores data at w_ptr using wr_clk when write enable is active
** - Read : outputs data from r_ptr using rd_clk when read enable is active
**
** STATUS FLAGS:
** - empty: asserted when no data is available
** - full : asserted when buffer is full
** - Flags require synchronization to avoid incorrect detection
**
** PURPOSE:
** - Safely transfers data between different clock domains
** - Handles systems where producer and consumer run at different speeds
**
** DIFFERENCE FROM SYNCHRONOUS FIFO:
** - Uses two clocks instead of one
** - More complex design due to clock domain crossing
** - Requires synchronization (e.g., Gray code pointers, flip-flop sync)
** - Risk of metastability if not designed properly
**
** NOTE:
** - Commonly uses Gray-coded pointers to ensure safe crossing
**   between clock domains and reduce timing errors.
*/

module async_fifo #(parameter DEPTH=8, DWIDTH=16) (
	input wclk,
	input rclk,
	input wr_rstn,
	input rd_rstn,
	input wr_ena,
	input rd_ena,
	input [DWIDTH-1:0] din,
	output reg full,
	output reg empty,
	output reg [DWIDTH-1:0] dout
);

	localparam MSB = $clog2(DEPTH);

	// Standard Gray-pointer asynchronous FIFO implementation assumes:
	// 1) DEPTH is power-of-2
	// 2) At least 4 entries (so address bits >= 2)
	initial begin
		if (DEPTH < 4) begin
			$error("async_fifo DEPTH must be >= 4. Got %0d", DEPTH);
			$finish;
		end
		if ((DEPTH & (DEPTH - 1)) != 0) begin
			$error("async_fifo DEPTH must be power-of-2. Got %0d", DEPTH);
			$finish;
		end
	end

	reg  [MSB:0] w_ptr, r_ptr;
	wire [MSB:0] w_ptr_gray, r_ptr_gray;
	wire [MSB:0] w_ptr_gray_sync, r_ptr_gray_sync;

	// Pointer next-value logic (clearer conditional form)
	wire [MSB:0] w_ptr_next = wr_ena && !full ? w_ptr + 1 : w_ptr;
	wire [MSB:0] w_ptr_gray_next = (w_ptr_next >> 1) ^ w_ptr_next;

	wire [MSB:0] r_ptr_next = rd_ena && !empty ? r_ptr + 1 : r_ptr;
	wire [MSB:0] r_ptr_gray_next = (r_ptr_next >> 1) ^ r_ptr_next;

	reg [DWIDTH-1:0] mem [0:DEPTH-1];

	synchronizer #(.WIDTH(MSB+1)) sync_w2r (
		.clk    (rclk),
		.resetn (rd_rstn),
		.din    (w_ptr_gray),
		.dout   (w_ptr_gray_sync)
	);

	synchronizer #(.WIDTH(MSB+1)) sync_r2w (
		.clk    (wclk),
		.resetn (wr_rstn),
		.din    (r_ptr_gray),
		.dout   (r_ptr_gray_sync)
	);

	b2g #(.WIDTH(MSB+1)) b2g_w (
		.bin  (w_ptr),
		.gray (w_ptr_gray)
	);

	b2g #(.WIDTH(MSB+1)) b2g_r (
		.bin  (r_ptr),
		.gray (r_ptr_gray)
	);

	// Write logic (write clock domain)
	always @(posedge wclk) begin
		if (!wr_rstn) begin
			w_ptr <= 0;
		end
		else if (wr_ena && !full) begin
			mem[w_ptr[MSB-1:0]] <= din;
			w_ptr <= w_ptr + 1;
		end
	end

	// Read logic (read clock domain)
	always @(posedge rclk) begin
		if (!rd_rstn) begin
			r_ptr <= 0;
			dout  <= 0;
		end
		else if (rd_ena && !empty) begin
			dout  <= mem[r_ptr[MSB-1:0]];
			r_ptr <= r_ptr + 1;
		end
	end

	always @(posedge wclk) begin
		if (!wr_rstn)
			full <= 0;
		else
			// Use w_ptr_gray_NEXT — catches full on the same cycle as the filling write
			full <= (w_ptr_gray_next == {~r_ptr_gray_sync[MSB:MSB-1], r_ptr_gray_sync[MSB-2:0]});
	end
	
	always @(posedge rclk) begin
		if (!rd_rstn)
			empty <= 1;
		else
			// Use r_ptr_gray_NEXT — catches empty on the same cycle as the draining read
			empty <= (r_ptr_gray_next == w_ptr_gray_sync);
	end

endmodule


module synchronizer #(parameter WIDTH=4) (
	input              clk,
	input              resetn,
	input  [WIDTH-1:0] din,
	output reg [WIDTH-1:0] dout
);
	reg [WIDTH-1:0] q1;

	always @(posedge clk) begin
		if (!resetn) begin
			q1   <= 0;
			dout <= 0;
		end
		else begin
			q1   <= din;
			dout <= q1;
		end
	end
endmodule


module b2g #(parameter WIDTH=4) (
	input  [WIDTH-1:0] bin,
	output [WIDTH-1:0] gray
);
	assign gray = (bin >> 1) ^ bin;
endmodule

`default_nettype wire