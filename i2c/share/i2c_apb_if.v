module i2c_apb_if (
	input  wire        pclk,
	input  wire        presetn,
	input  wire        psel,
	input  wire        penable,
	input  wire        pwrite,
	input  wire [31:0] paddr,
	input  wire [31:0] pwdata,
	output reg  [31:0] prdata,
	output reg         pready,
	output reg         pslverr
);

	parameter IDLE   = 2'b00;
	parameter SETUP  = 2'b01;
	parameter ACCESS = 2'b10;

	reg [1:0] state, next_state;
	reg [31:0] mem [0:31];

	wire apb_write = psel &  penable &  pwrite;  // write in ACCESS
	wire apb_read  = psel &  penable & ~pwrite;  // read  in ACCESS

	always @(*) begin
		next_state = IDLE;
		pready     = 1'b0;
		pslverr    = 1'b0;
		prdata     = 32'h0;

		case (state)
			IDLE: begin
				if (psel & ~penable)
					next_state = SETUP;
				else
					next_state = IDLE;
			end

			SETUP: begin
				if (psel & penable)
					next_state = ACCESS;
				else
					next_state = IDLE;
			end

			ACCESS: begin
				pready  = 1'b1;
				pslverr = 1'b0;

				if (apb_read)
					prdata = mem[paddr[4:0]];

				if (psel & ~penable)
					next_state = SETUP;
				else if (~psel)
					next_state = IDLE;
				else
					next_state = ACCESS;
			end

			default: next_state = IDLE;
		endcase
	end

	always @(posedge pclk or negedge presetn) begin
		if (!presetn)
			state <= IDLE;
		else
			state <= next_state;
	end

	always @(posedge pclk or negedge presetn) begin
		if (!presetn) begin
			mem[0] <= 32'h0000_0000;   // CTRL       — disabled
			mem[1] <= 32'h0000_0000;   // STATUS     — clear
			mem[2] <= 32'h0000_0000;   // ADDR       — no address
			mem[3] <= 32'h0000_0000;   // DATA_TX    — empty
			mem[4] <= 32'h0000_0000;   // DATA_RX    — empty
			mem[5] <= 32'h0000_0063;   // PRESCALER  — 100kHz default
			mem[6] <= 32'h0000_0000;   // INT_EN     — all masked
			mem[7] <= 32'h0000_0000;   // INT_STATUS — no pending
		end
		else if (apb_write) begin
			mem[paddr[4:0]] <= pwdata;
		end
	end

endmodule