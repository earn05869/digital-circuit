module i2c_master_fsm (
	input clk,
	input resetn,
	input start,
	input rw,
	input [6:0] slave_addr,
	input tx_empty,
	input byte_done,
	input sda_sampled, 
	input start_done,
	input stop_done,
	output reg gen_start,
	output reg gen_stop,
	output reg bit_ctrl_en,
	output reg load,
	output reg tx_rd_en,
	output reg rx_wr_en,
	output reg arb_lost,
	output reg busy,
	output wire ack_phase,
	output wire [3:0] state_out // Export state for top-level mux
);

	localparam IDLE      = 4'd0;
	localparam START     = 4'd1;
	localparam ADDR      = 4'd2;
	localparam ADDR_ACK  = 4'd3;
	localparam DATA_TX   = 4'd4;
	localparam DATA_RX   = 4'd5;
	localparam DATA_ACK  = 4'd6;
	localparam STOP      = 4'd7;
	localparam ARB_LOST  = 4'd8;
	localparam PREFETCH  = 4'd9; // Critical: Wait for FIFO latency

	reg [3:0] state, next_state;
	assign state_out = state;

	// ACK phase logic: Master drives ACK during DATA_RX 9th bit
	assign ack_phase = (state == DATA_RX); 

	always @(posedge clk or negedge resetn) begin
		if (!resetn) state <= IDLE;
		else         state <= next_state;
	end

	always @(*) begin
		next_state = state;
		gen_start = 1'b0; gen_stop = 1'b0;
		bit_ctrl_en = 1'b0; load = 1'b0;
		tx_rd_en = 1'b0; rx_wr_en = 1'b0;
		arb_lost = 1'b0; busy = 1'b1;

		case (state)
			IDLE: begin
				busy = 1'b0;
				if (start) next_state = START;
			end

			START: begin
				gen_start = 1'b1;
				if (start_done) begin
					load = 1'b1; // Load Address Byte from Top-Level Mux
					next_state = ADDR;
				end
			end

			ADDR: begin
				bit_ctrl_en = 1'b1;
				if (byte_done) next_state = ADDR_ACK;
			end

			ADDR_ACK: begin
				bit_ctrl_en = 1'b1;
				if (byte_done) begin
					if (!sda_sampled) begin // Address ACKing
						if (rw) next_state = DATA_RX;
						else if (!tx_empty) begin
							tx_rd_en = 1'b1; // Pulse FIFO read
							next_state = PREFETCH;
						end else begin
							gen_stop = 1'b1;
							next_state = STOP;
						end
					end else begin // Address NACKing
						gen_stop = 1'b1;
						next_state = STOP;
					end
				end
			end

			PREFETCH: begin
				// Wait 1 cycle for FIFO data_out to update
				load = 1'b1; // Load bit_ctrl with fresh FIFO data
				next_state = DATA_TX;
			end

			DATA_TX: begin
				bit_ctrl_en = 1'b1;
				if (byte_done) next_state = DATA_ACK;
			end

			DATA_RX: begin
				bit_ctrl_en = 1'b1;
				if (byte_done) begin
					rx_wr_en = 1'b1; // Save received byte to FIFO
					next_state = DATA_ACK;
				end
			end

			DATA_ACK: begin
				bit_ctrl_en = 1'b1;
				if (byte_done) begin
					// Handle Repeated START or more data
					if (start) begin
						next_state = START;
					end else if (!sda_sampled && !rw && !tx_empty) begin
						tx_rd_en = 1'b1;
						next_state = PREFETCH;
					end else begin
						gen_stop = 1'b1;
						next_state = STOP;
					end
				end
			end

			STOP: begin
				gen_stop = 1'b1;
				if (stop_done) next_state = IDLE;
			end

			default: next_state = IDLE;
		endcase
	end
endmodule