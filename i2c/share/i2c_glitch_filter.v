module i2c_glitch_filter #(parameter THRESHOLD = 3) (
	input clk,
	input resetn,
	input raw_in,
	output reg filtered_out
);

	// Counts consecutive cycles where raw_in remains at the current stable value.
	// Use a wide counter to avoid width/parameter edge cases.
	reg [31:0] counter;
	reg last_value;

	always @(posedge clk) begin
		if (!resetn) begin
			counter      <= 'd0;
			last_value   <= 1'b1;
			filtered_out <= 1'b1;
		end else begin
			if (raw_in == last_value) begin
				// Hold stable value: increment until THRESHOLD samples collected.
				if (counter < THRESHOLD)
					counter <= counter + 1'b1;

				// Update output once we've accumulated THRESHOLD consecutive samples
				// including the first sample after a change.
				if ((counter + 1'b1) >= THRESHOLD)
					filtered_out <= last_value;
			end else begin
				// Raw changed: start counting the new value (count the first sample now).
				last_value <= raw_in;
				counter    <= 32'd1;
				if (THRESHOLD == 0)
					filtered_out <= raw_in;
				else if (THRESHOLD == 1)
					filtered_out <= raw_in;
			end
		end
	end

endmodule