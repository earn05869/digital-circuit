module i2c_slave_fsm (
	input  wire       clk,
	input  wire       resetn,
	
	input  wire       i2c_en,
	input  wire [6:0] slave_addr,
	input  wire [7:0] api_len,
	
	input  wire       start_det,
	input  wire       stop_det,
	input  wire       byte_done,
	input  wire       sda_sampled,
	input  wire [7:0] rx_data,
	
	input  wire       tx_empty,
	input  wire       rx_full,
	
	output reg        bit_ctrl_en,
	output reg        load,
	output reg        tx_rd_en,
	output reg        rx_wr_en,
	output reg        sda_oe,
	output reg        sda_out,
	
	output reg        addr_match,
	output reg        busy,
	output reg        api_done,
	output reg        api_stop_det,
	output reg        dir, // 0 = Master Write to us, 1 = Master Read from us
	output wire       ack_phase,
	
	output reg        scl_oe,
	output reg        scl_out
);

	localparam S_IDLE          = 4'd0;
	localparam S_LISTEN_ADDR   = 4'd1;
	localparam S_SEND_ACK_ADDR = 4'd2;
	localparam S_TX_DATA_WAIT  = 4'd3;
	localparam S_TX_DATA_LOAD  = 4'd4;
	localparam S_TX_DATA_PREF  = 4'd5;
	localparam S_TX_DATA       = 4'd6;
	localparam S_RX_DATA_WAIT  = 4'd7;
	localparam S_RX_DATA       = 4'd8;

	reg [3:0] state, next_state;
	reg [7:0] slv_byte_cnt;
	
	wire [6:0] rx_addr = rx_data[7:1];
	wire       rx_rw   = rx_data[0];
	wire       addr_hit = (rx_addr == slave_addr);

	// Qualified start_det: only act on START when not already listening to address.
	// This prevents glitch-filter delay from creating false START events during
	// data bit transmission (SDA=0 while SCL_filt still sees old high value).
	wire start_det_q = start_det && (state != S_LISTEN_ADDR);

	assign ack_phase = (state == S_RX_DATA) ? rx_full : 1'b0;

	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			state        <= S_IDLE;
			slv_byte_cnt <= 8'd0;
			dir          <= 1'b0;
			api_stop_det <= 1'b0;
		end else if (!i2c_en) begin
			state        <= S_IDLE;
			slv_byte_cnt <= 8'd0;
			dir          <= 1'b0;
		end else if (stop_det) begin
			state        <= S_IDLE;
			api_stop_det <= 1'b1; // W1C by CPU
		end else begin
			state <= next_state;
			
		if (start_det_q) api_stop_det <= 1'b0;

			if (state == S_IDLE) begin
				slv_byte_cnt <= 8'd0;
			end else if (state == S_LISTEN_ADDR && byte_done && addr_hit) begin
				dir          <= rx_rw;
				slv_byte_cnt <= 8'd0;
			end else if ((state == S_RX_DATA || state == S_TX_DATA) && byte_done) begin
				if (slv_byte_cnt + 1'b1 == api_len) begin
					slv_byte_cnt <= 8'd0;
				end else begin
					slv_byte_cnt <= slv_byte_cnt + 8'd1;
				end
			end
		end
	end

	always @(*) begin
		next_state  = state;
		
		bit_ctrl_en = 1'b0;
		load        = 1'b0;
		tx_rd_en    = 1'b0;
		rx_wr_en    = 1'b0;
		sda_oe      = 1'b0;
		sda_out     = 1'b1;
		scl_oe      = 1'b0;
		scl_out     = 1'b0;
		
		addr_match  = 1'b0;
		busy        = 1'b0;
		api_done    = 1'b0;

		// Repeated START detection:
		// - From any state except IDLE and LISTEN_ADDR → restart address phase
		// - During LISTEN_ADDR, a spurious start_det (SDA low during SCL high
		//   which can look like START) must NOT reset the bit counter.
		//   Only move to LISTEN_ADDR if state > S_LISTEN_ADDR (i.e. mid-data).
		if (start_det_q && state > S_LISTEN_ADDR) begin
			next_state  = S_LISTEN_ADDR;
			bit_ctrl_en = 1'b1; // keep bit ctrl alive during transition
		end else begin
			case (state)
				S_IDLE: begin
					if (start_det_q && i2c_en) next_state = S_LISTEN_ADDR;
				end
				
				S_LISTEN_ADDR: begin
					busy        = 1'b1;
					bit_ctrl_en = 1'b1;
					if (byte_done) begin
						if (addr_hit) begin
							addr_match = 1'b1;
							next_state = S_SEND_ACK_ADDR;
						end else begin
							next_state = S_IDLE;
						end
					end
				end

				S_SEND_ACK_ADDR: begin
					busy        = 1'b1;
					bit_ctrl_en = 1'b1;
					sda_oe      = 1'b1;
					sda_out     = 1'b0; // ACK
					if (byte_done) begin
						if (dir == 1'b1) begin
							next_state = S_TX_DATA_WAIT;
						end else begin
							next_state = S_RX_DATA_WAIT;
						end
					end
				end

				S_TX_DATA_WAIT: begin
					busy = 1'b1;
					if (tx_empty) begin
						scl_oe  = 1'b1;
						scl_out = 1'b0;
					end else begin
						load       = 1'b1;
						next_state = S_TX_DATA_PREF;
					end
				end

				S_TX_DATA_PREF: begin
					busy     = 1'b1;
					tx_rd_en = 1'b1;
					next_state = S_TX_DATA;
				end

				S_TX_DATA: begin
					busy        = 1'b1;
					bit_ctrl_en = 1'b1;
					sda_oe      = 1'b1;
					if (byte_done) begin
						if (sda_sampled == 1'b0) begin // Master ACK
							if (slv_byte_cnt + 1'b1 == api_len) api_done = 1'b1;
							next_state = S_TX_DATA_WAIT;
						end else begin
							// Master NACK -> End of Read
							next_state = S_IDLE;
						end
					end
				end

				S_RX_DATA_WAIT: begin
					busy = 1'b1;
					if (rx_full) begin
						// Wait, slave shouldn't stretch clock if rx is full before receiving the byte.
						// Actually, if RX is full, we should just let it receive and send NACK!
						// But if we want to stretch clock, we could... no, the spec says send NACK.
						// So we just proceed to S_RX_DATA immediately.
					end
					next_state = S_RX_DATA;
				end

				S_RX_DATA: begin
					busy        = 1'b1;
					bit_ctrl_en = 1'b1;
					if (byte_done) begin
						if (!rx_full) rx_wr_en = 1'b1;
						if (slv_byte_cnt + 1'b1 == api_len) api_done = 1'b1;
						
						// Proceed to next byte wait
						next_state = S_RX_DATA_WAIT;
					end
				end

				default: next_state = S_IDLE;
			endcase
		end
	end

endmodule