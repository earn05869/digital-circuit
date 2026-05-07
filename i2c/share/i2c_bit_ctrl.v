module i2c_bit_ctrl (
	input clk,
	input resetn,
	input enable,
	input ack_phase,

	input [7:0] tx_data,
	input load,
	output [7:0] rx_data,
	output reg rx_valid,
	output reg byte_done,

	output reg sda_sampled,
	output reg sda_oe,
	output sda_out,

	input scl_in,
	input sda_in
);

	localparam PH_IDLE = 2'd0;
	localparam PH_LOW  = 2'd1; // SCL is low, update SDA
	localparam PH_HIGH = 2'd2; // SCL is high, sample SDA

	reg [1:0] phase;
	reg       shift_tx_en;
	reg       shift_rx_en;
	reg [3:0] bit_cnt;
	reg       scl_prev;
	
	wire scl_rise = (scl_prev == 1'b0) && (scl_in == 1'b1);
	wire scl_fall = (scl_prev == 1'b1) && (scl_in == 1'b0);

	i2c_shift_reg shift_register (
		.clk(clk),
		.rst_n(resetn),
		.shift_tx(shift_tx_en),
		.shift_rx(shift_rx_en),
		.load(load),
		.serial_in(sda_in),
		.data_in(tx_data),
		.serial_out(sda_out),
		.data_out(rx_data)
	);

	always @(posedge clk or negedge resetn) begin
		if (!resetn) scl_prev <= 1'b1;
		else         scl_prev <= scl_in;
	end

	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			phase       <= PH_IDLE;
			sda_oe      <= 1'b0;
			shift_tx_en <= 1'b0;
			shift_rx_en <= 1'b0;
			bit_cnt     <= 4'd0;
			rx_valid    <= 1'b0;
			byte_done   <= 1'b0;
			sda_sampled <= 1'b1;
		end else begin
			shift_tx_en <= 1'b0;
			shift_rx_en <= 1'b0;
			byte_done   <= 1'b0;
			rx_valid    <= 1'b0;

			if (!enable) begin
				phase   <= PH_IDLE;
				sda_oe  <= 1'b0;
				bit_cnt <= 4'd0;
			end else begin
				case (phase)
					PH_IDLE: begin
						// On the first entry, Bit 7 is already driven by the shift reg.
						// We just need to set the OE and wait for the first falling edge.
						if (bit_cnt < 8) sda_oe <= 1'b1;
						else             sda_oe <= ack_phase;

						if (scl_fall) begin
							phase <= PH_HIGH; 
						end
					end

					PH_LOW: begin
						if (scl_fall) begin
							phase <= PH_HIGH;
							// Only shift for bits 1 through 8. 
							// Bit 7 (the first bit) was already there at start.
							if (bit_cnt > 0 && bit_cnt <= 7) begin
								shift_tx_en <= 1'b1;
							end
							
							// Set OE for the upcoming HIGH period
							if (bit_cnt < 8) sda_oe <= 1'b1;
							else             sda_oe <= ack_phase;
						end
					end

					PH_HIGH: begin
						if (scl_rise) begin
							phase <= PH_LOW;
							sda_sampled <= sda_in; // Sample data/ACK
							
							if (bit_cnt < 8) begin
								shift_rx_en <= 1'b1;
								bit_cnt     <= bit_cnt + 4'd1;
							end else begin
								// 9th bit finished
								bit_cnt     <= 4'd0;
								byte_done   <= 1'b1;
								rx_valid    <= 1'b1;
								phase       <= PH_IDLE;
							end
						end
					end
				endcase
			end
		end
	end
endmodule