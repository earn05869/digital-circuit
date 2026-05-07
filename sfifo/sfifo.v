/*
** SYNCHRONOUS FIFO (First-In First-Out)
**
** A synchronous FIFO is a data buffer used to store and transfer data
** between modules operating under the same clock signal.
**
** Data is written and read in the same order:
** first data in → first data out.
**
** FEATURES:
** - Single clock for both read and write operations
** - Uses write pointer (w_ptr) and read pointer (r_ptr)
** - Internal memory array stores the data
**
** OPERATIONS:
** - Write: stores data at w_ptr when write enable is active
** - Read : outputs data from r_ptr when read enable is active
**
** STATUS FLAGS:
** - empty: asserted when no data is available (w_ptr == r_ptr)
** - full : asserted when buffer is full and cannot accept new data
**
** PURPOSE:
** - Handles temporary data storage
** - Matches data rates between producer and consumer modules
**
** NOTE:
** - depth specifies how many items the structure can hold.
** - data_width specifies how large each item is in bits.
** - Since it uses a single clock, design is simpler and avoids
**   clock domain crossing issues found in asynchronous FIFO.
*/

module sync_fifo #(
	parameter DEPTH  = 8,
	parameter DWIDTH = 16
)(
	input  wire              clk,
	input  wire              resetn,
	input  wire              wr_ena,
	input  wire              rd_ena,
	input  wire [DWIDTH-1:0] din,
	output wire              full,
	output wire              empty,
	output reg  [DWIDTH-1:0] dout
);

	reg [DWIDTH-1:0]       mem [DEPTH-1:0];
	reg [$clog2(DEPTH):0]  wr_ptr;
	reg [$clog2(DEPTH):0]  rd_ptr;

	always @(posedge clk) begin
		if (!resetn)
			wr_ptr <= 0;
		else if (wr_ena & !full) begin
			mem[wr_ptr[$clog2(DEPTH)-1:0]] <= din;
			wr_ptr <= wr_ptr + 1;
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			rd_ptr <= 0;
			dout   <= 0;
		end
		else if (rd_ena & !empty) begin
			dout   <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
			rd_ptr <= rd_ptr + 1;
		end
	end

	assign full  = (wr_ptr[$clog2(DEPTH)]   != rd_ptr[$clog2(DEPTH)]) &&
				   (wr_ptr[$clog2(DEPTH)-1:0] == rd_ptr[$clog2(DEPTH)-1:0]);
	assign empty = (wr_ptr == rd_ptr);

endmodule