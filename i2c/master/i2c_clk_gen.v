module i2c_clk_gen (
	input clk,
	input resetn,
	input en,
	input [15:0] prescaler,
	output reg scl_out,
	output reg scl_rising,
	output reg scl_falling );

	reg [15:0] clk_cnt;

	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			clk_cnt <= 16'd0;
		else if (!en)
			clk_cnt <= 16'd0;
		else begin
			if (clk_cnt >= prescaler)
				clk_cnt <= 16'd0;
			else
				clk_cnt <= clk_cnt + 16'd1;
		end
	end

	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			scl_out <= 1'b1;
		else if (!en)
			scl_out <= 1'b1;
		else if (clk_cnt == 16'd0)
			scl_out <= ~scl_out;
	end

	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			scl_rising <= 1'b0;
		else
			scl_rising <= (clk_cnt == 16'd0) && (scl_out == 1'b0) && en;
	end

	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			scl_falling <= 1'b0;
		else
			scl_falling <= (clk_cnt == 16'd0) && (scl_out == 1'b1) && en;
	end
endmodule