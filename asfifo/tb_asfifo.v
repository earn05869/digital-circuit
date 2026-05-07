`timescale 1ns/1ps
`default_nettype none

module tb_async_fifo();

	parameter DEPTH = 8;
	parameter DWIDTH = 16;
	parameter WCLK_PERIOD = 10;
	parameter RCLK_PERIOD = 11;

	reg wclk, rclk;
	reg wr_rstn, rd_rstn;
	reg wr_ena, rd_ena;
	reg [DWIDTH-1:0] din;
	wire full, empty;
	wire [DWIDTH-1:0] dout;

	localparam MAX_TRANS = 1024;

	async_fifo #(
		.DEPTH(DEPTH),
		.DWIDTH(DWIDTH)
	) fifo_inst (
		.wclk    (wclk),
		.rclk    (rclk),
		.wr_rstn (wr_rstn),
		.rd_rstn (rd_rstn),
		.wr_ena  (wr_ena),
		.rd_ena  (rd_ena),
		.din     (din),
		.full    (full),
		.empty   (empty),
		.dout    (dout)
	);

	/* CLOCKS */
	initial wclk = 0;
	always #(WCLK_PERIOD/2) wclk = ~wclk;

	initial rclk = 0;
	always #(RCLK_PERIOD/2) rclk = ~rclk;

	/* BASIC TASKS */

	task reset_all;
	begin
		wr_rstn = 0;
		rd_rstn = 0;
		wr_ena = 0;
		rd_ena = 0;
		din = {DWIDTH{1'b0}};
		repeat(4) @(posedge wclk);
		repeat(4) @(posedge rclk);
		wr_rstn = 1;
		rd_rstn = 1;
		repeat(2) @(posedge wclk);
		repeat(2) @(posedge rclk);
	end
	endtask

	task do_write;
	input [DWIDTH-1:0] data;
	output accepted;
	begin
		@(negedge wclk);
		if (!full) begin
			din = data;
			wr_ena = 1;
			@(negedge wclk);
			wr_ena = 0;
			accepted = 1'b1;
		end else begin
			wr_ena = 0;
			accepted = 1'b0;
		end
	end
	endtask

	task do_read;
	output [DWIDTH-1:0] data;
	output accepted;
	begin
		@(negedge rclk);
		if (!empty) begin
			rd_ena = 1;
			@(posedge rclk);
			@(negedge rclk);
			rd_ena = 0;
			data = dout;
			accepted = 1'b1;
		end else begin
			data = {DWIDTH{1'b0}};
			accepted = 1'b0;
		end
	end
	endtask

	task sync_delay;
	begin
		repeat(4) @(posedge wclk);
		repeat(4) @(posedge rclk);
	end
	endtask

	task check;
	input cond;
	input [255:0] msg;
	begin
		if (cond) begin
			pass_count = pass_count + 1;
			$display("PASS | %0s", msg);
		end
		else begin
			fail_count = fail_count + 1;
			$display("FAIL | %0s", msg);
		end
	end
	endtask

	reg [DWIDTH-1:0] rdata;
	reg wr_ok, rd_ok;
	reg [DWIDTH-1:0] exp_data;
	reg [DWIDTH-1:0] model_q [0:MAX_TRANS-1];
	integer q_head, q_tail, q_count;
	integer pass_count, fail_count;
	integer i;

	task model_reset;
	begin
		q_head = 0;
		q_tail = 0;
		q_count = 0;
	end
	endtask

	task model_push;
	input [DWIDTH-1:0] data;
	begin
		model_q[q_tail] = data;
		q_tail = (q_tail + 1) % MAX_TRANS;
		q_count = q_count + 1;
	end
	endtask

	task model_pop;
	output [DWIDTH-1:0] data;
	begin
		data = model_q[q_head];
		q_head = (q_head + 1) % MAX_TRANS;
		q_count = q_count - 1;
	end
	endtask

	initial begin
		$dumpfile("fifo.vcd");
		$dumpvars(0, tb_async_fifo);
		pass_count = 0;
		fail_count = 0;
		model_reset;

		/* ================= RESET ================= */

		// TC1
		reset_all;
		model_reset;
		check(full == 0, "TC1 full=0 after wr reset");

		// TC2
		reset_all;
		model_reset;
		check(empty == 1, "TC2 empty=1 after rd reset");

		// TC3
		reset_all;
		model_reset;
		check(empty == 1 && full == 0, "TC3 both reset");

		// TC4
		reset_all;
		model_reset;
		do_write(1, wr_ok);
		if (wr_ok) model_push(1);
		do_write(2, wr_ok);
		if (wr_ok) model_push(2);
		wr_rstn = 0;
		@(posedge wclk);
		check(full == 0, "TC4 wr reset mid-op");
		wr_rstn = 1;
		model_reset;

		/* ================= NORMAL ================= */

		// TC5
		reset_all;
		model_reset;
		do_write(16'hAAAA, wr_ok);
		if (wr_ok) model_push(16'hAAAA);
		sync_delay;
		do_read(rdata, rd_ok);
		check(rd_ok == 1'b1, "TC5 read accepted");
		model_pop(exp_data);
		check(rdata == exp_data, "TC5 single write/read");

		// TC6
		reset_all;
		model_reset;
		for (i = 0; i < DEPTH; i = i + 1)
		begin
			do_write(i, wr_ok);
			if (wr_ok) model_push(i);
		end
		sync_delay;
		check(full == 1, "TC6 burst write full");

		// TC7
		for (i = 0; i < DEPTH; i = i + 1) begin
			do_read(rdata, rd_ok);
			check(rd_ok == 1'b1, "TC7 read accepted");
			model_pop(exp_data);
			check(rdata == exp_data, "TC7 burst read order");
		end

		// TC8
		reset_all;
		model_reset;
		for (i = 0; i < DEPTH; i = i + 1) begin
			do_write(i, wr_ok);
			if (wr_ok) model_push(i);
			sync_delay;
			do_read(rdata, rd_ok);
			check(rd_ok == 1'b1, "TC8 read accepted");
			model_pop(exp_data);
			check(rdata == exp_data, "TC8 alternating");
		end

		/* ================= FULL ================= */

		// TC9
		reset_all;
		model_reset;
		for (i = 0; i < DEPTH; i = i + 1)
		begin
			do_write(i, wr_ok);
			if (wr_ok) model_push(i);
		end
		sync_delay;
		check(full == 1, "TC9 full asserted");

		// TC10
		do_write(16'hDEAD, wr_ok);
		sync_delay;
		check(wr_ok == 0, "TC10 write blocked");
		check(full == 1, "TC10 blocked write");

		// TC11
		do_read(rdata, rd_ok);
		check(rd_ok == 1'b1, "TC11 read accepted");
		model_pop(exp_data);
		check(rdata == exp_data, "TC11 data after full");
		sync_delay;
		check(full == 0, "TC11 full deassert");

		/* ================= EMPTY ================= */

		// TC12
		reset_all;
		model_reset;
		check(empty == 1, "TC12 empty on reset");

		// TC13
		do_read(rdata, rd_ok);
		check(rd_ok == 0, "TC13 read blocked");
		check(empty == 1, "TC13 read blocked");

		// TC14
		do_write(5, wr_ok);
		if (wr_ok) model_push(5);
		sync_delay;
		check(empty == 0, "TC14 empty deassert");

		// TC15
		do_read(rdata, rd_ok);
		check(rd_ok == 1'b1, "TC15 read accepted");
		model_pop(exp_data);
		check(rdata == exp_data, "TC15 readback data");
		sync_delay;
		check(empty == 1, "TC15 empty reassert");

		/* ================= CDC ================= */

		// TC16 fast write slow read
		reset_all;
		model_reset;
		for (i = 0; i < DEPTH; i = i + 1)
		begin
			do_write(i + 100, wr_ok);
			if (wr_ok) model_push(i + 100);
		end
		sync_delay;
		for (i = 0; i < DEPTH; i = i + 1) begin
			do_read(rdata, rd_ok);
			check(rd_ok == 1'b1, "TC16 read accepted");
			model_pop(exp_data);
			check(rdata == exp_data, "TC16 fast wr");
		end

		// TC17 slow write fast read
		reset_all;
		model_reset;
		do_read(rdata, rd_ok);
		check(rd_ok == 0, "TC17 read blocked on empty");
		check(empty == 1, "TC17 no phantom read");

		// TC19 wrap-around
		reset_all;
		model_reset;
		for (i = 0; i < DEPTH * 2; i = i + 1) begin
			do_write(i, wr_ok);
			if (wr_ok) model_push(i);
			sync_delay;
			do_read(rdata, rd_ok);
			check(rd_ok == 1'b1, "TC19 read accepted");
			model_pop(exp_data);
			check(rdata == exp_data, "TC19 wrap");
		end

		// TC20 true dual-clock simultaneous wr/rd
		reset_all;
		model_reset;
		do_write(16'h1234, wr_ok);
		if (wr_ok) model_push(16'h1234);
		sync_delay;

		fork
			begin
				do_write(16'hBEEF, wr_ok);
				if (wr_ok) model_push(16'hBEEF);
			end
			begin
				do_read(rdata, rd_ok);
				if (rd_ok) begin
					model_pop(exp_data);
					check(rdata == exp_data, "TC20 simultaneous data");
				end
			end
		join
		sync_delay;
		do_read(rdata, rd_ok);
		check(rd_ok == 1'b1, "TC20 follow-up read accepted");
		model_pop(exp_data);
		check(rdata == exp_data, "TC20 follow-up data");

		check(q_count == 0, "Model queue drained");
		$display("==== ALL TEST DONE: PASS=%0d FAIL=%0d ====", pass_count, fail_count);
		if (fail_count != 0) begin
			$fatal(1, "Testbench detected %0d failures", fail_count);
		end
		$finish;
	end

endmodule

`default_nettype wire