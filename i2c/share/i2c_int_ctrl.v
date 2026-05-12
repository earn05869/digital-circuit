module i2c_int_ctrl (
	input  wire       clk,
	input  wire       resetn,

	// Hardware Events
	input  wire       byte_done,
	input  wire       nack_det,
	input  wire       start_det,
	input  wire       stop_det,
	input  wire       tx_empty,
	input  wire       tx_full,
	input  wire       rx_full,
	input  wire       arb_lost,

	// APB Bus Interface
	input  wire [7:0] int_en,
	input  wire [7:0] int_clr, // W1C (Write 1 to Clear)

	// CPU Interrupt
	output reg  [7:0] int_status,
	output wire       irq
);

	// =========================================================
	// 1. จัดเรียงบิตให้ตรงกับ Register Map
	// =========================================================
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

	// =========================================================
	// 2. Interrupt Status Register (W1C Logic with Hardware Priority)
	// =========================================================
	always @(posedge clk or negedge resetn) begin
		if (!resetn) begin
			int_status <= 8'h00;
		end else begin
			// -------------------------------------------------
			// อธิบายสมการ:
			// int_status & ~int_clr : เก็บค่าเดิมไว้ ยกเว้นบิตที่ CPU สั่งล้าง (1->0)
			// | int_sources         : ถ้ามี Hardware Event ใหม่เข้ามา ให้เซ็ตเป็น 1 เสมอ (ชนะ)
			// -------------------------------------------------
			int_status <= (int_status & ~int_clr) | int_sources;
		end
	end

	// =========================================================
	// 3. IRQ Generation
	// =========================================================
	// ใช้ Reduction OR (|) กับผลลัพธ์ที่ผ่านการ Mask (Enable) แล้ว
	assign irq = |(int_status & int_en);

endmodule