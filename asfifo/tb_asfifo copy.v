`timescale 1ns/1ps

module tb_async_fifo();

	parameter DSIZE = 8;                // Data width
	parameter ASIZE = 3;                // Address width
	parameter DEPTH  = 1 << ASIZE;      // FIFO depth
	parameter WCLK_PERIOD = 10;         // Write clock period
	parameter RCLK_PERIOD = 20;         // Read clock period

	reg wclk = 0;
	reg rclk = 0;
	reg wrst_n = 1;
	reg rrst_n = 1;
	reg winc = 0;
	reg rinc = 0;
	reg [DSIZE-1:0] wdata = 0;
	wire [DSIZE-1:0] rdata;
	wire wfull;
	wire rempty;

	reg [DSIZE-1:0] expected [0:DEPTH-1];
	reg [DSIZE-1:0] recv;
	integer i;
	integer seed = 1;

	async_fifo #(
		.DEPTH(DEPTH),
		.DWIDTH(DSIZE)
	) fifo_inst (
		.wclk    (wclk),
		.rclk    (rclk),
		.wr_rstn (wrst_n),
		.rd_rstn (rrst_n),
		.wr_ena  (winc),
		.rd_ena  (rinc),
		.din     (wdata),
		.full    (wfull),
		.empty   (rempty),
		.dout    (rdata)
	);

	always #(WCLK_PERIOD/2) wclk = ~wclk;
	always #(RCLK_PERIOD/2) rclk = ~rclk;

	task reset_all;
	begin
		wrst_n = 0;
		rrst_n = 0;
		winc = 0;
		rinc = 0;
		wdata = 0;
		repeat (4) @(posedge wclk);
		repeat (4) @(posedge rclk);
		wrst_n = 1;
		rrst_n = 1;
		repeat (4) @(posedge wclk);
		repeat (4) @(posedge rclk);
	end
	endtask

	task do_write;
		input [DSIZE-1:0] data;
	begin
		@(negedge wclk);        // ← drive on negedge, not posedge
		if (!wfull) begin
			wdata = data;
			winc  = 1;
			@(negedge wclk);
			winc  = 0;
		end else begin
			winc = 0;
		end
	end
	endtask
	
	task do_read;
		output reg [DSIZE-1:0] data;
	begin
		@(negedge rclk);        // ← same fix
		if (!rempty) begin
			rinc = 1;
			@(posedge rclk);    // wait for FIFO to latch (NBA takes effect)
			@(negedge rclk);    // sample after NBA settle
			rinc = 0;
			data = rdata;
		end else begin
			data = {DSIZE{1'b0}};
		end
	end
	endtask

	task sync_delay;
	begin
		repeat (4) @(posedge wclk);
		repeat (4) @(posedge rclk);
	end
	endtask

	task check;
		input cond;
		input [255:0] msg;
	begin
		if (cond)
			$display("PASS | %0s", msg);
		else
			$display("FAIL | %0s", msg);
	end
	endtask

	initial begin
		$dumpfile("fifo.vcd");
		$dumpvars(0, tb_async_fifo);
		for (i = 0; i < DEPTH; i = i + 1) begin
			$dumpvars(0, fifo_inst.mem[i]);
		end

		// Reset and verify initial empty/full states
		reset_all;
		check(rempty == 1, "TC0 empty after reset");
		check(wfull == 0, "TC0 not full after reset");

		// TEST CASE 1: write random data and read it back
		reset_all;
		for (i = 0; i < DEPTH; i = i + 1) begin
			expected[i] = $random(seed);
			do_write(expected[i]);
			sync_delay;
		end

		sync_delay;
		for (i = 0; i < DEPTH; i = i + 1) begin
			do_read(recv);
			check(recv == expected[i], "TC1 read back correct order");
		end

		// TEST CASE 2: fill FIFO and block extra writes
		reset_all;
		for (i = 0; i < DEPTH; i = i + 1)
			do_write($random(seed));
		sync_delay;
		check(wfull == 1, "TC2 FIFO full after depth writes");

		@(posedge wclk);
		if (!wfull) begin
			wdata = $random(seed);
			winc = 1;
		end
		else begin
			winc = 0;
		end
		@(posedge wclk);
		winc = 0;
		sync_delay;
		check(wfull == 1, "TC2 extra write blocked when full");

		// TEST CASE 3: read from empty FIFO and block reads
		reset_all;
		@(posedge rclk);
		if (!rempty) begin
			rinc = 1;
			@(posedge rclk);
			rinc = 0;
		end
		sync_delay;
		check(rempty == 1, "TC3 read blocked on empty FIFO");

		$display("==== ALL TEST DONE ====");
		$finish;
	end

endmodule
