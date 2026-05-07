module baud_rate_gen #(
	parameter CLK_FREQ = 50_000_000,
	parameter OVERSAMPLE = 16
)(
	input  wire       clk,
	input  wire       reset_n,
	input  wire [1:0] baud_sel, // sel: 00=9600, 01=19200, 10=38400, 11=115200
	output reg        tick
);

	localparam DIV_9600   = CLK_FREQ / (9600   * OVERSAMPLE);
	localparam DIV_19200  = CLK_FREQ / (19200  * OVERSAMPLE);
	localparam DIV_38400  = CLK_FREQ / (38400  * OVERSAMPLE);
	localparam DIV_115200 = CLK_FREQ / (115200 * OVERSAMPLE);

	localparam WIDTH = $clog2(DIV_9600);

	reg [WIDTH-1:0] counter;
	reg [WIDTH-1:0] current_divisor;
	reg [1:0]       baud_sel_reg;

	always @(*) begin
		case (baud_sel_reg)
			2'b00:   current_divisor = DIV_9600[WIDTH-1:0];
			2'b01:   current_divisor = DIV_19200[WIDTH-1:0];
			2'b10:   current_divisor = DIV_38400[WIDTH-1:0];
			2'b11:   current_divisor = DIV_115200[WIDTH-1:0];
			default: current_divisor = DIV_9600[WIDTH-1:0];
		endcase
	end

	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			baud_sel_reg <= 2'b00;
			counter      <= {WIDTH{1'b0}};
			tick         <= 1'b0;
		end else if (baud_sel != baud_sel_reg) begin
			baud_sel_reg <= baud_sel;
			counter      <= {WIDTH{1'b0}};
			tick         <= 1'b0;
		end else if (counter >= (current_divisor - 1'b1)) begin
			counter <= {WIDTH{1'b0}};
			tick    <= 1'b1;
		end else begin
			counter <= counter + 1'b1;
			tick    <= 1'b0;
		end
	end

endmodule
