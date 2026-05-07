module uart_transmitter #(
	parameter integer OVERSAMPLE = 16
) (
	input       clk,
	input       resetn,
	input       baud_tick,
	input [7:0] din,
	input       start,
	output reg  dout,
	output wire busy
);
	localparam integer SCW = $clog2(OVERSAMPLE);

	reg [10:0] shift_reg;
	reg [10:0] state_bit;
	reg [SCW-1:0] s_count;

	wire [10:0] shift_next = {1'b1, shift_reg[10:1]};

	assign busy = (state_bit != 11'b0);

	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			dout       <= 1'b1;
			state_bit  <= 0;
			s_count    <= 0;
		end else if (start && !busy) begin
			shift_reg  <= {1'b1, ^din, din, 1'b0};
			state_bit  <= 11'b1;
			s_count    <= 0;
			dout       <= 1'b0;
		end else if (busy && baud_tick) begin
			if (s_count == OVERSAMPLE - 1) begin
				s_count   <= 0;
				dout      <= shift_next[0];
				shift_reg <= shift_next;
				state_bit <= state_bit << 1;
			end else begin
				s_count <= s_count + 1;
			end
		end
	end
endmodule
