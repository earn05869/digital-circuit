module i2c_slave_fsm (
	input  wire       clk,
	input  wire       resetn,
	input  wire [6:0] slave_addr,
	input  wire       start_det,
	input  wire       stop_det,
	input  wire       byte_done,
	input  wire       sda_sampled,
	input  wire [7:0] rx_data,      // received byte
	input  wire       tx_empty,     // nothing to send
	output reg        bit_ctrl_en,  // enable bit_ctrl
	output reg        load,         // load TX byte
	output reg        tx_rd_en,     // pop TX FIFO
	output reg        rx_wr_en,     // push RX FIFO
	output reg        sda_oe,       // drive SDA
	output reg        sda_out,      // SDA value
	output reg        addr_match,   // address matched
	output reg        busy,         // slave busy
	output wire       ack_phase
);

	// ─────────────────────────────────────
	// State Encoding
	// ─────────────────────────────────────
	localparam IDLE         = 4'd0;
	localparam ADDR_RX      = 4'd1;
	localparam ADDR_ACK     = 4'd2;
	localparam DATA_TX      = 4'd3;
	localparam DATA_TX_ACK  = 4'd4;
	localparam DATA_RX      = 4'd5;
	localparam DATA_RX_ACK  = 4'd6;

	reg [3:0] state, next_state;

	// ─────────────────────────────────────
	// Extract received address and RW bit
	// ─────────────────────────────────────
	wire [6:0] rx_addr = rx_data[7:1];  // upper 7 bits
	wire       rx_rw   = rx_data[0];    // LSB = R/W bit

	// ─────────────────────────────────────
	// Address Match Check
	// ─────────────────────────────────────
	wire addr_hit = (rx_addr == slave_addr);

	assign ack_phase = (state == ADDR_ACK) || (state == DATA_TX_ACK) || (state == DATA_RX_ACK);

	// ─────────────────────────────────────
	// State Register
	// ─────────────────────────────────────
	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			state <= IDLE;
		else
			state <= next_state;
	end

	// ─────────────────────────────────────
	// Next State + Output Logic
	// ─────────────────────────────────────
	always @(*) begin
		// defaults
		next_state  = state;
		bit_ctrl_en = 1'b0;
		load        = 1'b0;
		tx_rd_en    = 1'b0;
		rx_wr_en    = 1'b0;
		sda_oe      = 1'b0;
		sda_out     = 1'b1;   // default release SDA
		addr_match  = 1'b0;
		busy        = 1'b0;

		// Global bus condition handling:
		// - STOP always terminates the current transaction immediately.
		// - Repeated START restarts address reception (even mid-transfer).
		if (stop_det) begin
			next_state = IDLE;
		end
		else if (start_det && (state != IDLE)) begin
			next_state = ADDR_RX;
		end
		else begin
		case (state)

			// ─────────────────────────
			IDLE: begin
				busy = 1'b0;
				// wait for START condition
				if (start_det)
					next_state = ADDR_RX;
			end

			// ─────────────────────────
			ADDR_RX: begin
				// receive address byte from master
				busy        = 1'b1;
				bit_ctrl_en = 1'b1;     // enable bit_ctrl to receive

				if (byte_done) begin
					if (addr_hit) begin
						// address matches — send ACK
						addr_match = 1'b1;
						next_state = ADDR_ACK;
					end
					else begin
						// not our address — go back to IDLE
						next_state = IDLE;
					end
				end

				// START or STOP resets state
				if (stop_det)
					next_state = IDLE;
			end

			// ─────────────────────────
			ADDR_ACK: begin
				// pull SDA low = ACK
				busy    = 1'b1;
				bit_ctrl_en = 1'b1;
				sda_oe  = 1'b1;
				sda_out = 1'b0;         // ACK = SDA low

				if (byte_done) begin
					if (rx_rw == 1'b1) begin
						// master wants to READ from us
						// load first TX byte
						tx_rd_en   = 1'b1;
						load       = 1'b1;
						next_state = DATA_TX;
					end
					else begin
						// master wants to WRITE to us
						next_state = DATA_RX;
					end
				end
			end

			// ─────────────────────────
			DATA_TX: begin
				// slave sends data to master
				busy        = 1'b1;
				bit_ctrl_en = 1'b1;     // bit_ctrl sends from shift_reg
				sda_oe      = 1'b1;

				if (byte_done)
					next_state = DATA_TX_ACK;
			end

			// ─────────────────────────
			DATA_TX_ACK: begin
				// wait for master ACK/NACK
				busy        = 1'b1;
				bit_ctrl_en = 1'b1;

				if (byte_done) begin
					if (sda_sampled == 1'b0) begin
						// master ACK — send more data
						if (!tx_empty) begin
							tx_rd_en   = 1'b1;  // pop next byte
							load       = 1'b1;  // load shift_reg
							next_state = DATA_TX;
						end
						else begin
							// nothing left to send
							next_state = IDLE;
						end
					end
					else begin
						// master NACK — done reading
						next_state = IDLE;
					end
				end

				if (stop_det)
					next_state = IDLE;
			end

			// ─────────────────────────
			DATA_RX: begin
				// slave receives data from master
				busy        = 1'b1;
				bit_ctrl_en = 1'b1;     // bit_ctrl receives into shift_reg

				if (byte_done) begin
					rx_wr_en   = 1'b1;  // push received byte to RX FIFO
					next_state = DATA_RX_ACK;
				end

				if (stop_det)
					next_state = IDLE;
			end

			// ─────────────────────────
			DATA_RX_ACK: begin
				// slave sends ACK to master
				busy    = 1'b1;
				bit_ctrl_en = 1'b1;
				sda_oe  = 1'b1;
				sda_out = 1'b0;         // ACK = pull SDA low

				if (byte_done) begin
					// more data coming?
					if (!stop_det)
						next_state = DATA_RX;
					else
						next_state = IDLE;
				end

				if (stop_det)
					next_state = IDLE;
			end

			default: next_state = IDLE;

		endcase
		end
	end

endmodule