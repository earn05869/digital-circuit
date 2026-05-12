/*
I2C SHIFT REGISTER - Bidirectional Byte Shifter
════════════════════════════════════════════════

TRANSMIT MODE (Master→Slave)
────────────────────────────
1. Master loads 8-bit data via parallel input (data_in)
2. On each SCL clock pulse, MSB shifts out to SDA line (serial_out)
3. Slave samples SDA while SCL is high
4. Remaining bits shift left each cycle until all 8 bits transmitted
5. Next byte can be loaded after 8 shifts

RECEIVE MODE (Slave→Master)
───────────────────────────
1. Slave drives SDA line bit-by-bit
2. Master samples SDA on each SCL rising edge
3. Sampled bit enters shift register via serial_in
4. Previous bits shift left to make room
5. After 8 shifts, complete byte available on data_out
6. Ready for next byte after load reset

OPERATION
─────────
• load:      Parallel load mode (TX)—stores data_in into 8-bit register
• shift:     Serial shift mode—shifts all bits left, captures serial_in at LSB
• serial_in: Input from SDA bus (RX mode) or don't-care (TX mode)
• serial_out: MSB of register (drives open-drain SDA line in TX mode)
• data_out:  Full 8-bit register value (available after 8 shifts in RX mode)
• Reset:     Sets register to 0xFF (idle bus—open-drain high)
*/

module i2c_shift_reg (
	input  wire       clk,
	input  wire       rst_n,
	input  wire       shift,
	input  wire       load,
	input  wire       serial_in,
	input  wire [7:0] data_in,
	output wire       serial_out,
	output wire [7:0] data_out );

	reg [7:0] mem;

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			mem <= 8'hFF;
		end else begin
			if (load) begin
				mem <= data_in;
			end
			else if (shift) begin
				mem <= {mem[6:0], serial_in};
			end
		end
	end

	assign serial_out = mem[7];
	assign data_out   = mem;

endmodule