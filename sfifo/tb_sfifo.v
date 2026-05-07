`timescale 1ns / 1ps

module tb_sync_fifo();

parameter DEPTH	= 8;
parameter DWIDTH = 16;
parameter CLK_PERIOD = 10;

reg					clk;
reg					resetn;
reg					wr_ena;
reg					rd_ena;
wire				full;
wire				empty;
reg  [DWIDTH-1:0]	din;
wire [DWIDTH-1:0]	dout;

sync_fifo #(
	.DEPTH	(DEPTH),
	.DWIDTH	(DWIDTH)
) fifo_inst (
	.clk	(clk),
	.resetn	(resetn),
	.wr_ena	(wr_ena),
	.rd_ena	(rd_ena),
	.din	(din),
	.full	(full),
	.empty	(empty),
	.dout	(dout)
);

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

task do_reset;
	begin
		resetn = 0;
		wr_ena = 0;
		rd_ena = 0;
		din = 0;
		@(posedge clk); #1;
		resetn = 1;
	end
endtask

task do_write;
	input [DWIDTH-1:0] data;
	begin
		din = data;
		wr_ena = 1;
		@(posedge clk); #1;
		wr_ena = 0;
	end
endtask

task do_read;
	begin
		rd_ena = 1;
		@(posedge clk); #1;
		rd_ena = 0;
	end
endtask

task check;
	input condition;
	input [516:0] label;
	begin
		if (condition)
			$display("PASS | %s", label);
		else
			$display("FAIL | %s", label);
	end
endtask

initial begin
	$dumpfile("tb_sfifo.vcd");
	$dumpvars(0, tb_sync_fifo);

	// ---- TEST 1: Reset state --------------------------------
	do_reset;
	check(empty == 1, "empty after reset");
	check(full  == 0, "not full after reset");

	// ---- TEST 2: Write then read back ----------------------
	do_write(16'hABCD);
	check(empty == 0,       "not empty after write");
	do_read;
	check(dout == 16'hABCD, "correct data read back");

	// ---- TEST 3: Fill to full ------------------------------
	do_reset;
	repeat(DEPTH) do_write($random); // DEPTH-1 because 1 slot is sacrificed
	check(full  == 1, "full after filling");
	check(empty == 0, "not empty when full");

	// ---- TEST 4: Write while full (should be ignored) ------
	do_write(16'hDEAD);
	check(full == 1, "still full after write-while-full");

	// ---- TEST 5: Drain to empty ----------------------------
	repeat(DEPTH) do_read;
	check(empty == 1, "empty after draining");

	// ---- TEST 6: Simultaneous read and write ---------------
	do_reset;
	do_write(16'h1234);
	wr_ena = 1; rd_ena = 1; din = 16'h5678;
	@(posedge clk); #1;
	wr_ena = 0; rd_ena = 0;
	check(dout == 16'h1234, "simultaneous rd+wr: correct data out");

	$display("done");
	$finish;
end

endmodule