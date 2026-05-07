/* i2c_bit_cnt.v — Bit Counter
 *
 * What Does It Do?
 *   Counts 0 to 8 for every I2C byte transfer:
 *   - Bits 0–7: 8 data bits
 *   - Bit 8: ACK/NACK bit
 */

module i2c_bit_cnt (
	input clk,
	input resetn,
	input enable,
	input clear,
	input [3:0] max_count,
	output reg [3:0] count,
	output done );

	always @(posedge clk) begin
		if (!resetn)
			count <= 4'd0;
		else if (clear)
			count <= 4'd0;
		else if (enable && !done)
			count <= count + 1;
	end

	assign done = (count == max_count);
endmodule