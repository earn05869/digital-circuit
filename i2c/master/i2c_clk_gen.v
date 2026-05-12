/*
** ============================================================================
** MODULE: i2c_clk_gen
** DESCRIPTION: 4-Phase SCL Generator for I2C Master.
** Provides strobe signals for sampling (Read) and setup (Write).
** ** TIMING FORMULA: f_SCL = f_clk / (4 * prescaler)
** ============================================================================
*/

module i2c_clk_gen (
	input  wire        clk,           // System Clock
	input  wire        resetn,        // Active Low Reset
	input  wire        en,            // Enable clock generation
	input  wire [15:0] prescaler,     // DIV value from Register Map
	
	output reg         scl_out,       // Generated SCL line (Internal)
	output reg         phase_setup,   // Trigger for changing SDA (at SCL Low)
	output reg         phase_sample   // Trigger for reading SDA (at SCL High)
);

	reg [15:0] clk_cnt;
	reg [1:0]  phase_cnt;

	// 1. Clock Divider Counter
	// Counts from 0 to (prescaler - 1) for each of the 4 phases
	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			clk_cnt <= 16'd0;
		else if (!en)
			clk_cnt <= 16'd0;
		else if (clk_cnt >= prescaler - 16'd1)
			clk_cnt <= 16'd0;
		else
			clk_cnt <= clk_cnt + 16'd1;
	end

	// 2. Phase Counter Logic
	// Transitions to the next phase every time clk_cnt hits the limit
	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			phase_cnt <= 2'd0;
		else if (!en)
			phase_cnt <= 2'd0;
		else if (clk_cnt == prescaler - 16'd1)
			phase_cnt <= phase_cnt + 2'd1;
	end

	// 3. SCL Output & Strobe Signals
	// Logic based on the 4-phase state machine
	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			scl_out      <= 1'b1;
			phase_setup  <= 1'b0;
			phase_sample <= 1'b0;
		end else if (en && clk_cnt == prescaler - 16'd1) begin
			case (phase_cnt)
				2'd0: begin // End of Phase 0
					scl_out      <= 1'b1; 
					phase_setup  <= 1'b0;
					phase_sample <= 1'b0;
				end
				2'd1: begin // End of Phase 1 (SCL High -> Time to Sample)
					scl_out      <= 1'b1;
					phase_setup  <= 1'b0;
					phase_sample <= 1'b1; // Pulse for 1 clk cycle
				end
				2'd2: begin // End of Phase 2
					scl_out      <= 1'b0;
					phase_setup  <= 1'b0;
					phase_sample <= 1'b0;
				end
				2'd3: begin // End of Phase 3 (SCL Low -> Time to Setup/Change)
					scl_out      <= 1'b0;
					phase_setup  <= 1'b1; // Pulse for 1 clk cycle
					phase_sample <= 1'b0;
				end
			endcase
		end else begin
			// Strobes are only high for exactly one 'clk' period
			phase_setup  <= 1'b0;
			phase_sample <= 1'b0;
		end
	end

endmodule