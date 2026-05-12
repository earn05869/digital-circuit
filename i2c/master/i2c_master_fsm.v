module i2c_master_fsm (
	input  wire       clk,
	input  wire       resetn,
	
	// --- API Control (CPU/Top Interface) ---
	input  wire       i2c_en,
	input  wire       mode_master,
	input  wire       api_start,      
	input  wire       api_stop_req,   
	input  wire       api_reload_en,
	input  wire       api_continue,
	input  wire       api_rw,         // 0 = Write, 1 = Read
	input  wire [6:0] api_slave_addr,
	input  wire [7:0] api_len,
	
	output reg        api_busy,
	output reg        api_arb_lost,
	output reg        api_done,
	output reg        api_reload_req,
	output reg        api_nack_err,
	output wire       api_addr_phase, 
	output wire [3:0] api_state_out,
	
	// --- FIFO Interface ---
	input  wire       fifo_tx_empty,
	output reg        fifo_tx_rd_en,  
	input  wire       fifo_rx_full,
	output reg        fifo_rx_wr_en,  
	
	// --- Bit Ctrl Interface ---
	input  wire       ctrl_byte_done,
	input  wire       ctrl_sda_sampled, 
	input  wire       ctrl_arb_lost,
	output reg        ctrl_en,
	output reg        ctrl_is_read, 
	output reg        ctrl_load,        
	output reg        ctrl_ack_phase,   
	
	// --- Physical Layer Interface ---
	input  wire       phy_start_done,
	input  wire       phy_stop_done,
	input  wire       phy_scl_in,      
	output reg        phy_gen_start,
	output reg        phy_gen_stop,
	
	// --- Clock Stretching Override ---
	output reg        scl_oe,
	output reg        scl_out
);

	localparam M_IDLE            = 4'd0;
	localparam M_START_GEN       = 4'd1;
	localparam M_TX_ADDR_LOAD    = 4'd2;
	localparam M_TX_ADDR         = 4'd3;
	localparam M_TX_DATA_WAIT    = 4'd4;
	localparam M_TX_DATA_PREF    = 4'd5;
	localparam M_TX_DATA         = 4'd6;
	localparam M_RX_DATA_WAIT    = 4'd7;
	localparam M_RX_DATA         = 4'd8;
	localparam M_CHECK_LEN       = 4'd9;
	localparam M_RELOAD_WAIT     = 4'd10;
	localparam M_REP_START_WAIT  = 4'd11;
	localparam M_REP_START_GEN   = 4'd12;
	localparam M_STOP_GEN        = 4'd13;

	reg [3:0] state, next_state;
	reg [7:0] byte_cnt;
	reg       is_read;
	reg       addr_sent;

	assign api_state_out  = state;
	assign api_addr_phase = !addr_sent;

	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			state        <= M_IDLE;
			byte_cnt     <= 8'd0;
			is_read      <= 1'b0;
			addr_sent    <= 1'b0;
			api_arb_lost <= 1'b0;
		end else if (!i2c_en) begin
			state        <= M_IDLE;
			byte_cnt     <= 8'd0;
			is_read      <= 1'b0;
			addr_sent    <= 1'b0;
		end else if (ctrl_arb_lost) begin
			state        <= M_IDLE;
			api_arb_lost <= 1'b1;
		end else begin
			state <= next_state;
			
			if (state == M_IDLE) begin
				byte_cnt     <= 8'd0;
				addr_sent    <= 1'b0;
			end else if (state == M_TX_ADDR && ctrl_byte_done && !ctrl_sda_sampled) begin
				addr_sent <= 1'b1;
				is_read   <= api_rw;
			end else if ((state == M_TX_DATA || state == M_RX_DATA) && ctrl_byte_done) begin
				if (state == M_TX_DATA && ctrl_sda_sampled) begin
					// NACK
				end else begin
					byte_cnt <= byte_cnt + 8'd1;
				end
			end else if (state == M_RELOAD_WAIT && api_continue) begin
				byte_cnt <= 8'd0;
			end else if (state == M_REP_START_WAIT && api_start) begin
				byte_cnt  <= 8'd0;
				addr_sent <= 1'b0;
			end
			
			if (state == M_IDLE && api_start) begin
				api_arb_lost <= 1'b0;
			end
		end
	end

	always @(*) begin
		next_state     = state;
		
		api_busy       = 1'b1;
		api_done       = 1'b0;
		api_reload_req = 1'b0;
		api_nack_err   = 1'b0;

		fifo_tx_rd_en  = 1'b0;
		fifo_rx_wr_en  = 1'b0;

		ctrl_en        = 1'b0;
		ctrl_is_read   = 1'b0;
		ctrl_load      = 1'b0;
		ctrl_ack_phase = 1'b0;

		phy_gen_start  = 1'b0;
		phy_gen_stop   = 1'b0;
		scl_oe         = 1'b0;
		scl_out        = 1'b0;

		case (state)
			M_IDLE: begin
				api_busy = 1'b0;
				if (i2c_en && mode_master && api_start) begin
					next_state = M_START_GEN;
				end
			end

			M_START_GEN: begin
				phy_gen_start = 1'b1;
				if (phy_start_done) begin
					next_state = M_TX_ADDR_LOAD;
				end
			end

			M_TX_ADDR_LOAD: begin
				ctrl_load  = 1'b1;
				next_state = M_TX_ADDR;
			end

			M_TX_ADDR: begin
				ctrl_en      = 1'b1;
				ctrl_is_read = 1'b0;
				if (ctrl_byte_done) begin
					if (ctrl_sda_sampled) begin // NACK
						api_nack_err = 1'b1;
						next_state   = M_STOP_GEN;
					end else begin
						if (api_rw) next_state = M_RX_DATA_WAIT;
						else        next_state = M_TX_DATA_WAIT;
					end
				end
			end

			M_TX_DATA_WAIT: begin
				if (fifo_tx_empty) begin
					scl_oe  = 1'b1;
					scl_out = 1'b0;
				end else begin
					ctrl_load  = 1'b1;
					next_state = M_TX_DATA_PREF;
				end
			end

			M_TX_DATA_PREF: begin
				fifo_tx_rd_en = 1'b1;
				next_state    = M_TX_DATA;
			end

			M_TX_DATA: begin
				ctrl_en      = 1'b1;
				ctrl_is_read = 1'b0;
				if (ctrl_byte_done) begin
					if (ctrl_sda_sampled) begin // NACK
						api_nack_err = 1'b1;
						next_state   = M_STOP_GEN;
					end else begin
						next_state   = M_CHECK_LEN;
					end
				end
			end

			M_RX_DATA_WAIT: begin
				if (fifo_rx_full) begin
					scl_oe  = 1'b1;
					scl_out = 1'b0;
				end else begin
					next_state = M_RX_DATA;
				end
			end

			M_RX_DATA: begin
				ctrl_en        = 1'b1;
				ctrl_is_read   = 1'b1;
				ctrl_ack_phase = (byte_cnt == api_len - 1'b1) ? 1'b1 : 1'b0; // NACK on last byte
				if (ctrl_byte_done) begin
					fifo_rx_wr_en = 1'b1;
					next_state    = M_CHECK_LEN;
				end
			end

			M_CHECK_LEN: begin
				if ((byte_cnt + 1'b1) < api_len) begin
					if (is_read) next_state = M_RX_DATA_WAIT;
					else         next_state = M_TX_DATA_WAIT;
				end else begin
					if (api_reload_en) begin
						api_reload_req = 1'b1;
						api_done       = 1'b1;
						next_state     = M_RELOAD_WAIT;
					end else if (api_stop_req) begin
						api_done   = 1'b1;
						next_state = M_STOP_GEN;
					end else begin
						api_done   = 1'b1;
						next_state = M_REP_START_WAIT;
					end
				end
			end

			M_RELOAD_WAIT: begin
				scl_oe  = 1'b1;
				scl_out = 1'b0;
				api_reload_req = 1'b1;
				if (api_continue) begin
					if (is_read) next_state = M_RX_DATA_WAIT;
					else         next_state = M_TX_DATA_WAIT;
				end
			end

			M_REP_START_WAIT: begin
				scl_oe  = 1'b1;
				scl_out = 1'b0;
				if (api_start) begin
					next_state = M_REP_START_GEN;
				end
			end

			M_REP_START_GEN: begin
				phy_gen_start = 1'b1;
				if (phy_start_done) begin
					next_state = M_TX_ADDR_LOAD;
				end
			end

			M_STOP_GEN: begin
				phy_gen_stop = 1'b1;
				if (phy_stop_done) begin
					next_state = M_IDLE;
				end
			end

			default: next_state = M_IDLE;
		endcase
	end

endmodule