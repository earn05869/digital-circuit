module uart_receiver #(
	parameter integer OVERSAMPLE = 16
) (
	input  wire       clk,
	input  wire       reset,
	input  wire       baud_tick,
	input  wire       in,
	output reg  [7:0] out_byte,
	output reg        done,
	output reg        framing_err
);
	localparam IDLE = 0, START = 1, DATA = 2, PARITY = 3, STOP = 4;
	localparam integer START_MID = (OVERSAMPLE / 2) - 1;
	localparam integer BIT_END   = OVERSAMPLE - 1;
	localparam integer SCW       = $clog2(OVERSAMPLE);

	reg [2:0] state;
	reg [SCW-1:0] s_count;
	reg [2:0] bit_count;
	reg [7:0] shift_reg;
	reg       data_xor;

	always @(posedge clk) begin
		if (reset) begin
			state       <= IDLE;
			s_count     <= 0;
			bit_count   <= 0;
			done        <= 0;
			framing_err <= 0;
		end else if (baud_tick) begin
			case (state)
				IDLE: begin
					done        <= 0;
					framing_err <= 1'b0;
					if (in == 0) begin
						s_count <= 0;
						state   <= START;
					end
				end
				START: begin
					if (s_count == START_MID) begin
						s_count   <= 0;
						bit_count <= 0;
						data_xor  <= 1'b0;
						state     <= DATA;
					end else s_count <= s_count + 1;
				end
				DATA: begin
					if (s_count == BIT_END) begin
						s_count   <= 0;
						shift_reg <= {in, shift_reg[7:1]};
						data_xor  <= data_xor ^ in;
						if (bit_count == 7)
							state <= PARITY;
						else
							bit_count <= bit_count + 1;
					end else s_count <= s_count + 1;
				end
				PARITY: begin
					if (s_count == BIT_END) begin
						s_count <= 0;
						state   <= (in == data_xor) ? STOP : IDLE;
					end else s_count <= s_count + 1;
				end
				STOP: begin
					if (s_count == BIT_END) begin
						out_byte    <= shift_reg;
						done        <= 1;
						framing_err <= (in != 1'b1);
						state       <= IDLE;
					end else s_count <= s_count + 1;
				end
			endcase
		end
	end
endmodule
