module i2c_bit_ctrl (
	input  wire       clk,
	input  wire       resetn,
	
	// --- สัญญาณควบคุมระดับ Byte (จาก FSM) ---
	input  wire       enable,       // สั่งให้เริ่มทำงาน
	input  wire       is_read,      // 0 = ส่ง (TX), 1 = รับ (RX)
	input  wire       ack_phase,    // 0 = ACK, 1 = NACK (เมื่อ Master เป็นคนรับข้อมูล)
	input  wire       load,         // สั่งบรรจุข้อมูลลง Shift Reg
	input  wire [7:0] tx_data,      // ข้อมูลที่จะส่ง
	
	// --- สัญญาณส่งกลับให้ FSM ---
	output wire [7:0] rx_data,      // ข้อมูล 8 บิตที่รับสำเร็จ
	output reg        rx_ack,       // สถานะ ACK จาก Slave (0 = ACK, 1 = NACK)
	output reg        byte_done,    // แจ้งว่าทำงานครบ 9 บิตแล้ว
	output reg        arb_lost,     // แจ้งว่าแพ้การประมูลบัส (Multi-master)
	
	// --- สัญญาณเชื่อมต่อ IO Pad ---
	output reg        sda_oe,       // Output Enable สำหรับ SDA (1 = Drive, 0 = High-Z)
	output wire       sda_out,      // ข้อมูลที่จะขับออกไป
	input  wire       scl_in,       // สัญญาณ SCL ที่อ่านได้จริง
	input  wire       sda_in        // สัญญาณ SDA ที่อ่านได้จริง
);

	// ==============================================================
	// 1. Edge Detection (ตรวจจับขอบสัญญาณ SCL)
	// ==============================================================
	reg scl_prev;
	always @(posedge clk or negedge resetn) begin
		if (!resetn) scl_prev <= 1'b1;
		else         scl_prev <= scl_in;
	end
	
	// SCL Rising Edge: จังหวะที่ Master และ Slave ต้องอ่านค่า (Sample)
	wire trigger_sample = (scl_prev == 1'b0) && (scl_in == 1'b1); 
	// SCL Falling Edge: จังหวะที่ Master และ Slave ต้องเปลี่ยนค่า (Setup)
	wire trigger_setup  = (scl_prev == 1'b1) && (scl_in == 1'b0); 

	// ==============================================================
	// 2. Instantiate: Shift Register & Bit Counter
	// ==============================================================
	reg  sda_sampled_bit; 
	reg  shift_en;
	wire shift_out_bit;

	i2c_shift_reg u_shift_reg (
		.clk        (clk),
		.rst_n      (resetn),
		.shift      (shift_en),
		.load       (load),
		.serial_in  (sda_sampled_bit),
		.data_in    (tx_data),
		.serial_out (shift_out_bit),
		.data_out   (rx_data)
	);

	reg  cnt_en;
	reg  cnt_clear;
	wire [3:0] current_bit;
	wire cnt_done;

	i2c_bit_cnt u_bit_counter (
		.clk       (clk),
		.resetn    (resetn),
		.enable    (cnt_en),
		.clear     (cnt_clear),
		.max_count (4'd8),
		.count     (current_bit),
		.done      (cnt_done)
	);

	// ==============================================================
	// 3. Data Out MUX (เลือกว่าจะส่ง Data Bit หรือ ACK/NACK)
	// ==============================================================
	// บิต 0-7 ส่งข้อมูลจาก Shift Reg, บิตที่ 8 (9th clock) ส่งค่า ACK/NACK
	assign sda_out = (current_bit < 4'd8) ? shift_out_bit : ack_phase;

	// ==============================================================
	// 4. Main Bit-Level State Machine
	// ==============================================================
	localparam IDLE        = 2'd0;
	localparam WAIT_SAMPLE = 2'd1; // ช่วง SCL เป็น High
	localparam WAIT_SETUP  = 2'd2; // ช่วง SCL เป็น Low

	reg [1:0] state;

	// ==============================================================
// 5. Main Bit-Level State Machine (FIXED VERSION)
// ==============================================================
always @(posedge clk or negedge resetn) begin
	if (!resetn) begin
		state           <= IDLE;
		sda_oe          <= 1'b0;
		byte_done       <= 1'b0;
		rx_ack          <= 1'b1; 
		sda_sampled_bit <= 1'b1;
		shift_en        <= 1'b0;
		cnt_en          <= 1'b0;
		cnt_clear       <= 1'b0;
		arb_lost        <= 1'b0;
	end else begin
		// --- 🛡️ CONTINUOUS ARBITRATION MONITORING ---
		if (state != IDLE && scl_in && sda_oe && sda_out && !sda_in) begin
			arb_lost <= 1'b1; // เซตเป็น 1 เมื่อเกิดปัญหา
			sda_oe   <= 1'b0; 
			state    <= IDLE; 
		end 
		else begin
			shift_en  <= 1'b0;
			cnt_en    <= 1'b0;
			cnt_clear <= 1'b0;
			byte_done <= 1'b0;

			case (state)
				IDLE: begin
					// ❌ ลบ arb_lost <= 1'b0; ออกจากตรงนี้
					if (enable) begin
						arb_lost  <= 1'b0; // ✅ เคลียร์เฉพาะตอนเริ่มงานใหม่เท่านั้น
						state     <= WAIT_SAMPLE;
						cnt_clear <= 1'b1; 
						sda_oe    <= ~is_read; 
					end else begin
						sda_oe    <= 1'b0;
					end
				end
				// ... (ส่วน WAIT_SAMPLE และ WAIT_SETUP เหมือนเดิม) ...
				WAIT_SAMPLE: begin
					if (trigger_sample) begin
						sda_sampled_bit <= sda_in; 
						if (current_bit == 4'd8) rx_ack <= sda_in; 
						state <= WAIT_SETUP;
					end
				end

				WAIT_SETUP: begin
					if (trigger_setup) begin
						if (current_bit < 4'd8) begin
							shift_en <= 1'b1;
							cnt_en   <= 1'b1; 
							if (current_bit == 4'd7) sda_oe <= is_read;
							else                     sda_oe <= ~is_read;
							state <= WAIT_SAMPLE;
						end else begin
							byte_done <= 1'b1; 
							state     <= IDLE;
						end
					end
				end
			endcase
		end
	end
end

endmodule