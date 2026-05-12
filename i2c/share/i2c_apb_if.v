/* ============================================================================
** REGISTER MAP (32-bit Word Aligned)
** ----------------------------------------------------------------------------
** Offset 0x00: I2C_CON (Control Register - R/W)
** [0] START      : (M) Write 1 to start; Hardware clears when START is sent.
** [1] STOP       : (M) Write 1 to send STOP when NBYTES reached; (S) N/A.
** [2] RELOAD_EN  : (M/S) 1 = Enable Reload Mode (stall bus at LEN instead of STOP).
** [3] CONTINUE   : (M/S) Write 1 to resume transfer after updating LEN.
** [4] I2C_EN     : (M/S) Global enable (1 = Active, 0 = Reset/Disabled).
** [5] MODE       : (M/S) 1 = Master Mode, 0 = Slave Mode.
** [6] SLV_EN     : (S) 1 = Enable Slave response to Own Address; (M) N/A.
**
** Offset 0x04: I2C_ADDR (Address Register - R/W)
** [7:1] ADDR     : (M) Target Slave Address; (S) Own Slave Address (ID).
** [0]   RW       : (M) 0 = Write, 1 = Read; (S) N/A.
**
** Offset 0x08: I2C_LEN (Length Register - R/W)
** [7:0] NBYTES   : (M/S) Number of bytes to transfer/receive (1-255).
** In Slave, acts as a threshold for DONE interrupt.
**
** Offset 0x0C: I2C_STA (Status Register - Mixed)
** [0] BUSY       : RO, 1 = Bus is active (SCL/SDA moving).
** [1] DONE       : W1C, 1 = LEN bytes reached. Write 1 to clear.
** [2] NACK_ERR   : W1C, 1 = NACK received (M: from Slave / S: from Master).
** [3] RELOAD_REQ : RO, 1 = Waiting for CPU to update LEN & press CONTINUE.
** [6] ARB_LOST   : W1C, 1 = (M) Lost bus to another Master. Write 1 to clear.
** [7] ADDR_MATCH : RO, 1 = (S) Our Own Address detected on bus.
** [8] DIR        : RO, 1 = (S) Master wants to Read us, 0 = Master sending Data.
** [9] STOP_DET   : W1C, 1 = (S) STOP condition detected on bus. Write 1 to clear.
**
** Offset 0x10: I2C_DATA (Data Register - R/W)
** [7:0] DATA     : Port to TX FIFO (Write) / RX FIFO (Read).
**
** Offset 0x14: I2C_PRE (Prescaler - R/W)
** [15:0] DIV     : (M) Clock divider for SCL freq: f_SCL = f_clk / (DIV * 4).
**
** Offset 0x18: I2C_IER (Interrupt Enable - R/W)
** [0] DONE_IE    : Enable interrupt for DONE.
** [1] NACK_IE    : Enable interrupt for NACK_ERR.
** [2] RELOAD_IE  : Enable interrupt for RELOAD_REQ.
** [3] ARB_LOST_IE: Enable interrupt for ARB_LOST.
** [4] ADDR_IE    : (S) Enable interrupt for ADDR_MATCH.
** [5] STOP_IE    : (S) Enable interrupt for STOP_DET.
** ----------------------------------------------------------------------------
** ACCESS RULES: 
** - RO  : Read Only
** - R/W : Read and Write
** - W1C : Write 1 to Clear (Writing '0' has no effect, Writing '1' resets bit).
** ============================================================================
*/

module i2c_dual_apb_if (
	input  wire        PCLK,
	input  wire        PRESETn,
	input  wire [4:0]  PADDR,
	input  wire        PSEL,
	input  wire        PENABLE,
	input  wire        PWRITE,
	input  wire [31:0] PWDATA,
	output reg  [31:0] PRDATA,
	output wire        PREADY,

	// Interface to FSM
	output reg  [6:0]  reg_con,
	output reg  [7:0]  reg_addr,
	output reg  [7:0]  reg_len,
	output reg  [15:0] reg_pre,
	output reg  [5:0]  reg_ier,
	input  wire [9:0]  sta_hw_set, // สัญญาณจาก FSM มาสั่ง Set Status
	
	// FIFO Interface
	output wire        fifo_tx_we,
	output wire        fifo_rx_re,
	input  wire [7:0]  fifo_rx_data,
	
	output wire        irq
);

	assign PREADY = 1'b1;
	wire write_strobe = PSEL && PENABLE && PWRITE;
	wire read_strobe  = PSEL && PENABLE && !PWRITE;

	reg [9:0] reg_sta;

	// --- Write & Status Logic ---
	always @(posedge PCLK or negedge PRESETn) begin
		if (!PRESETn) begin
			reg_con  <= 7'h0;
			reg_addr <= 8'h0;
			reg_len  <= 8'h0;
			reg_pre  <= 16'h0;
			reg_ier  <= 6'h0;
			reg_sta  <= 10'h0;
		end else begin
			// 1. Hardware Sets Status (ลำดับความสำคัญสูงกว่า)
			reg_sta <= reg_sta | sta_hw_set;

			// 2. CPU Access
			if (write_strobe) begin
				case (PADDR)
					5'h00: reg_con  <= PWDATA[6:0];
					5'h04: reg_addr <= PWDATA[7:0];
					5'h08: reg_len  <= PWDATA[7:0];
					5'h0C: begin
						// W1C Logic (Write 1 to Clear)
						if (PWDATA[1]) reg_sta[1] <= 1'b0; // Clear DONE
						if (PWDATA[2]) reg_sta[2] <= 1'b0; // Clear NACK
						if (PWDATA[6]) reg_sta[6] <= 1'b0; // Clear ARB_LOST
						if (PWDATA[9]) reg_sta[9] <= 1'b0; // Clear STOP_DET
					end
					5'h14: reg_pre  <= PWDATA[15:0];
					5'h18: reg_ier  <= PWDATA[5:0];
				endcase
			end
			
			// พิเศษ: HW เคลียร์ START เองหลังจากเริ่มงาน (สมมติ sta_hw_set[0] คือ start_done)
			if (sta_hw_set[0]) reg_con[0] <= 1'b0;
		end
	end

	// --- Read Logic ---
	always @(*) begin
		case (PADDR)
			5'h00: PRDATA = {25'd0, reg_con};
			5'h04: PRDATA = {24'd0, reg_addr};
			5'h08: PRDATA = {24'd0, reg_len};
			5'h0C: PRDATA = {22'd0, reg_sta};
			5'h10: PRDATA = {24'd0, fifo_rx_data};
			5'h14: PRDATA = {16'd0, reg_pre};
			5'h18: PRDATA = {26'd0, reg_ier};
			default: PRDATA = 32'h0;
		endcase
	end

	// FIFO Interface
	assign fifo_tx_we = (PADDR == 5'h10) && write_strobe;
	assign fifo_rx_re = (PADDR == 5'h10) && read_strobe;

	// Interrupt Line (Masking Status with Enable Bits)
	assign irq = |(reg_sta[5:0] & reg_ier);

endmodule