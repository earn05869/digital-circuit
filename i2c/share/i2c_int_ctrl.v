

/*
 * i2c_int_ctrl.v — Detailed RTL Design
 *
 * What Does It Do?
 * Collects event signals from all modules and generates IRQ to CPU
 * All modules ──► i2c_int_ctrl ──► IRQ pin ──► CPU
 *
 * What Events Trigger Interrupt?
 * From bit_ctrl:
 * ├── byte_done     ← transfer complete
 * └── sda_sampled   ← NACK received
 *
 * From start_stop:
 * ├── start_det     ← START seen on bus
 * └── stop_det      ← STOP seen on bus
 *
 * From tx_fifo:
 * ├── tx_empty      ← need more data to send
 * └── tx_full       ← CPU wrote too fast
 *
 * From rx_fifo:
 * ├── rx_full       ← CPU must read data
 * └── rx_empty      ← nothing received yet
 *
 * From master_fsm:
 * └── arb_lost      ← arbitration lost
 *
 * How Interrupt Works
 * Step 1 — event happens        byte_done = 1
 * Step 2 — flag sets            int_status[0] = 1
 * Step 3 — if masked enabled    int_en[0] = 1
 * Step 4 — IRQ fires            irq = 1
 * Step 5 — CPU reads status     finds int_status
 * Step 6 — CPU clears flag      writes 1 to bit = W1C
 * Step 7 — IRQ clears           irq = 0
 *
 * Register Bits
 * INT_STATUS / INT_EN — same bit position
 *
 * Bit 0 → BYTE_DONE    transfer complete
 * Bit 1 → NACK_DET     NACK received
 * Bit 2 → START_DET    START on bus
 * Bit 3 → STOP_DET     STOP on bus
 * Bit 4 → TX_EMPTY     TX FIFO empty
 * Bit 5 → TX_FULL      TX FIFO full
 * Bit 6 → RX_FULL      RX FIFO full
 * Bit 7 → ARB_LOST     arbitration lost
 */


module i2c_int_ctrl (
	input  wire        clk,
	input  wire        resetn,

	input  wire        byte_done,
	input  wire        nack_det,
	input  wire        start_det,
	input  wire        stop_det,
	input  wire        tx_empty,
	input  wire        tx_full,
	input  wire        rx_full,
	input  wire        arb_lost,

	input wire [7:0]   int_en,
	input wire [7:0]   int_clr,

	output reg [7:0]   int_status,
	output wire        irq
);

	localparam BIT_BYTE_DONE = 0;
	localparam BIT_NACK_DET  = 1;
	localparam BIT_START_DET = 2;
	localparam BIT_STOP_DET  = 3;
	localparam BIT_TX_EMPTY  = 4;
	localparam BIT_TX_FULL   = 5;
	localparam BIT_RX_FULL   = 6;
	localparam BIT_ARB_LOST  = 7;

	wire [7:0] int_sources = {
			arb_lost,       // bit 7
			rx_full,        // bit 6
			tx_full,        // bit 5
			tx_empty,       // bit 4
			stop_det,       // bit 3
			start_det,      // bit 2
			nack_det,       // bit 1
			byte_done       // bit 0
		};

	integer i;

	always @(posedge clk or negedge resetn) begin
		if (!resetn)
			int_status <= 8'h00;
		else begin
			for (i = 0; i < 8; i = i + 1) begin
				if (int_clr[i])
					int_status[i] <= 1'b0;      // W1C clear
				else if (int_sources[i])
					int_status[i] <= 1'b1;      // set on event
			end
		end
	end

	assign irq = |(int_status & int_en);

endmodule 