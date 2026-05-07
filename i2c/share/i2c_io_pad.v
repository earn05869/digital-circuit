/*IO Pad Driver
 *
 * What Does It Do?
 *   I2C uses open-drain bus — this means:
 *   - Device can only PULL DOWN (drive 0)
 *   - Device cannot drive HIGH — it just releases the line
 *   - Line goes HIGH naturally via external pull-up resistor
 */

module i2c_io_pad (
	input clk,
	input resetn,
	input tx_data,
	input output_enable,
	output reg rx_data,
	inout sda
);

	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			rx_data <= 1'b1; // I2C bus idle state
		else
			rx_data <= sda;  // Sample SDA line
	end

	assign sda = (output_enable && !tx_data) ? 1'b0 : 1'bz;
endmodule