module i2c_glitch_filter #(parameter THRESHOLD = 3) (
	input  wire clk,
	input  wire resetn,
	input  wire raw_in,
	output reg  filtered_out
);

	localparam CNT_WIDTH = (THRESHOLD > 1) ? $clog2(THRESHOLD + 1) : 2;

	reg [CNT_WIDTH-1:0] counter;
	reg last_value;

	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			counter      <= 0;
			last_value   <= 1'b1;
			filtered_out <= 1'b1;
		end else begin
			if (raw_in == last_value) begin
				if (counter < THRESHOLD) begin
					counter <= counter + 1'b1;
				end
				

				if (counter == THRESHOLD - 1) begin
					filtered_out <= last_value;
				end
			end else begin
				last_value <= raw_in;
				counter    <= 1;
				
				if (THRESHOLD == 0 || THRESHOLD == 1) begin
					filtered_out <= raw_in;
				end
			end
		end
	end

endmodule