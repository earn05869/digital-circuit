module i2c_start_stop (
	input  wire clk,
	input  wire resetn,
	input  wire gen_start,
	input  wire gen_stop,
	input  wire scl_in,
	input  wire sda_in,

	output reg  sda_out,
	output reg  sda_oe,
	output reg  start_det,
	output reg  stop_det,
	output reg  done
);

	localparam IDLE         = 3'd0;
	localparam SDA_HIGH     = 3'd1;
	localparam SCL_HIGH     = 3'd2;
	localparam SDA_LOW      = 3'd3;
	localparam SCL_LOW      = 3'd4;
	localparam STOP_SDALOW  = 3'd5;
	localparam STOP_SCLHIGH = 3'd6;
	localparam STOP_SDAHIGH = 3'd7;

	reg [2:0] state, next_state;
	reg       scl_prev;
	reg       sda_prev;
	reg [2:0] hold_cnt;     // ✅ hold counter — prevent instant transition

	// ─────────────────────────────────────
	// SCL / SDA edge tracking
	// ─────────────────────────────────────
	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			scl_prev <= 1'b1;
			sda_prev <= 1'b1;
		end
		else begin
			scl_prev <= scl_in;
			sda_prev <= sda_in;
		end
	end

	// ─────────────────────────────────────
	// START detect — SDA falls while SCL HIGH
	// ─────────────────────────────────────
	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			start_det <= 1'b0;
		else
			start_det <= (sda_prev & ~sda_in) & scl_in;
	end

	// ─────────────────────────────────────
	// STOP detect — SDA rises while SCL HIGH
	// ─────────────────────────────────────
	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			stop_det <= 1'b0;
		else
			stop_det <= (~sda_prev & sda_in) & scl_in;
	end

	// ─────────────────────────────────────
	// State Register + hold counter
	// ─────────────────────────────────────
	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			state    <= IDLE;
			hold_cnt <= 3'd0;
		end
		else begin
			if (next_state != state) begin
				state    <= next_state;
				hold_cnt <= 3'd0;
			end
			else
				hold_cnt <= hold_cnt + 1;
		end
	end

	// ─────────────────────────────────────
	// Done — registered 
	// ─────────────────────────────────────
	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			done <= 1'b0;
		else begin
			done <= 1'b0;
			if (state == SCL_LOW && scl_in == 1'b0)
				done <= 1'b1;
			if (state == STOP_SDAHIGH && sda_in == 1'b1)
				done <= 1'b1;
		end
	end

	// ─────────────────────────────────────
	// Next State + Output Logic
	// ─────────────────────────────────────
	always @(*) begin
		next_state = state;
		sda_out    = 1'b1;
		sda_oe     = 1'b0;

		case (state)

			IDLE: begin
				sda_out = 1'b1;
				sda_oe  = 1'b0;
				if (gen_start)
					next_state = SDA_HIGH;
				else if (gen_stop)
					next_state = STOP_SDALOW;
			end

			// ─────────────────────────
			// START Generation
			// ─────────────────────────
			SDA_HIGH: begin
				sda_out = 1'b1;
				sda_oe  = 1'b1;
				if (sda_in == 1'b1 && hold_cnt >= 2)
					next_state = SCL_HIGH;
			end

			SCL_HIGH: begin
				sda_out = 1'b1;
				sda_oe  = 1'b1;
				if (scl_in == 1'b1 && hold_cnt >= 2)
					next_state = SDA_LOW;
			end

			SDA_LOW: begin
				sda_out = 1'b0;
				sda_oe  = 1'b1;
				if (scl_in == 1'b1 && hold_cnt >= 2)
					next_state = SCL_LOW;
			end

			SCL_LOW: begin
				sda_out = 1'b0;
				sda_oe  = 1'b1;
				if (scl_in == 1'b0)
					next_state = IDLE;
			end

			// ─────────────────────────
			// STOP Generation
			// ─────────────────────────
			STOP_SDALOW: begin
				sda_out = 1'b0;
				sda_oe  = 1'b1;
				if (scl_in == 1'b0 && hold_cnt >= 2)
					next_state = STOP_SCLHIGH;
			end

			STOP_SCLHIGH: begin
				sda_out = 1'b0;
				sda_oe  = 1'b1;
				if (scl_in == 1'b1 && hold_cnt >= 2)
					next_state = STOP_SDAHIGH;
			end

			STOP_SDAHIGH: begin
				sda_out = 1'b1;
				sda_oe  = 1'b1;
				if (sda_in == 1'b1)
					next_state = IDLE;
			end

			default: begin
				next_state = IDLE;
				sda_out    = 1'b1;
				sda_oe     = 1'b0;
			end

		endcase
	end

endmodule