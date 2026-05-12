`timescale 1ns / 1ps

module tb_i2c_bit_ctrl;

	// ========================================================
	// 1. System Clock & Reset
	// ========================================================
	reg clk;
	reg resetn;
	
	initial begin 
		clk = 0; 
		#3; // Offset หนี Race Condition
		forever #10 clk = ~clk; 
	end

	// ========================================================
	// 2. I2C Bus Physics (Pull-ups & External Noise)
	// ========================================================
	wire sda_bus;
	wire scl_bus;
	
	assign (pull1, highz0) sda_bus = 1'b1;
	assign (pull1, highz0) scl_bus = 1'b1;

	reg m_scl_drive;
	assign scl_bus = m_scl_drive ? 1'b0 : 1'bz;

	reg compete_sda_drive; // สำหรับเทส Arbitration
	assign sda_bus = compete_sda_drive ? 1'b0 : 1'bz;

	reg noise_inject; // ⭐️ สำหรับจำลองสัญญาณรบกวน (Glitch)
	assign sda_bus = noise_inject ? 1'b0 : 1'bz;

	// ========================================================
	// 3. MASTER INSTANCE (Logic -> Pad -> Filter -> Logic)
	// ========================================================
	reg        m_enable, m_is_read, m_ack_phase, m_load;
	reg  [7:0] m_tx_data;
	wire [7:0] m_rx_data;
	wire       m_rx_ack, m_byte_done, m_arb_lost;
	wire       m_sda_oe, m_sda_out;
	
	// Wires for Interconnection
	wire m_sda_raw, m_sda_filtered;
	wire m_scl_filtered;

	// 3.1 Master Logic
	i2c_bit_ctrl u_master (
		.clk(clk), .resetn(resetn), 
		.enable(m_enable), .is_read(m_is_read), .ack_phase(m_ack_phase),
		.load(m_load), .tx_data(m_tx_data),
		.rx_data(m_rx_data), .rx_ack(m_rx_ack), .byte_done(m_byte_done),
		.arb_lost(m_arb_lost),
		.sda_oe(m_sda_oe), .sda_out(m_sda_out), 
		.scl_in(m_scl_filtered), .sda_in(m_sda_filtered)
	);

	// 3.2 Master IO Pad
	i2c_io_pad u_master_pad (
		.clk(clk), .resetn(resetn),
		.tx_data(m_sda_out), .output_enable(m_sda_oe),
		.rx_data(m_sda_raw), .sda(sda_bus)
	);

	// 3.3 Master Glitch Filters
	i2c_glitch_filter #(.THRESHOLD(3)) u_m_sda_filter (
		.clk(clk), .resetn(resetn), .raw_in(m_sda_raw), .filtered_out(m_sda_filtered)
	);
	i2c_glitch_filter #(.THRESHOLD(3)) u_m_scl_filter (
		.clk(clk), .resetn(resetn), .raw_in(scl_bus), .filtered_out(m_scl_filtered)
	);

	// ========================================================
	// 4. SLAVE INSTANCE
	// ========================================================
	reg        s_enable, s_is_read, s_ack_phase, s_load;
	reg  [7:0] s_tx_data;
	wire [7:0] s_rx_data;
	wire       s_rx_ack, s_byte_done, s_arb_lost;
	wire       s_sda_oe, s_sda_out;
	
	wire s_sda_raw, s_sda_filtered;
	wire s_scl_filtered;

	i2c_bit_ctrl u_slave (
		.clk(clk), .resetn(resetn), 
		.enable(s_enable), .is_read(s_is_read), .ack_phase(s_ack_phase),
		.load(s_load), .tx_data(s_tx_data),
		.rx_data(s_rx_data), .rx_ack(s_rx_ack), .byte_done(s_byte_done),
		.arb_lost(s_arb_lost),
		.sda_oe(s_sda_oe), .sda_out(s_sda_out), 
		.scl_in(s_scl_filtered), .sda_in(s_sda_filtered)
	);

	i2c_io_pad u_slave_pad (
		.clk(clk), .resetn(resetn),
		.tx_data(s_sda_out), .output_enable(s_sda_oe),
		.rx_data(s_sda_raw), .sda(sda_bus)
	);

	i2c_glitch_filter #(.THRESHOLD(5)) u_s_sda_filter (
		.clk(clk), .resetn(resetn), .raw_in(s_sda_raw), .filtered_out(s_sda_filtered)
	);
	i2c_glitch_filter #(.THRESHOLD(5)) u_s_scl_filter (
		.clk(clk), .resetn(resetn), .raw_in(scl_bus), .filtered_out(s_scl_filtered)
	);

	// ========================================================
	// 5. Tasks & Helpers
	// ========================================================
	integer error_count = 0;
	task assert_val(input integer exp, input integer got, input [100*8:1] msg);
		begin
			if (exp !== got) begin
				$display("[%0t ns] ❌ [FAIL] %s | Exp: %h, Got: %h", $time, msg, exp, got);
				error_count = error_count + 1;
			end else $display("[%0t ns] ✅ [PASS] %s", $time, msg);
		end
	endtask

	task gen_scl;
		begin
			#1000; m_scl_drive = 0; // SCL High
			#2500; m_scl_drive = 1; // SCL Low
			#1500;
		end
	endtask

	// ========================================================
	// 6. MAIN SIMULATION
	// ========================================================
	integer i;
	initial begin
		$dumpfile("tb_i2c_glitch_system.vcd");
		$dumpvars(0, tb_i2c_bit_ctrl);

		resetn = 0; m_scl_drive = 0; compete_sda_drive = 0; noise_inject = 0;
		{m_enable, m_load, m_is_read, m_tx_data, m_ack_phase} = 0;
		{s_enable, s_load, s_is_read, s_tx_data, s_ack_phase} = 0;
		#100 resetn = 1; 

		$display("\n=======================================================");
		$display(" 🚀 I2C SYSTEM TEST WITH GLITCH FILTERS & IO PADS");
		$display("=======================================================\n");

	// --- 📝 SCENARIO 1: Master Writes 0xA5 ---
		$display("--- 📝 SCENARIO 1: Master Writes 0xA5 ---");
		m_scl_drive = 1; #1000;
		m_is_read = 0; m_tx_data = 8'hA5;
		
		@(negedge clk); m_load = 1; m_enable = 1;
		@(negedge clk); m_load = 0; m_enable = 0;
		
		s_is_read = 1; s_ack_phase = 0; // Slave เตรียมส่ง ACK (0)
		@(negedge clk); s_enable = 1;
		@(negedge clk); s_enable = 0;

		for (i = 0; i < 9; i = i + 1) gen_scl();

		// ✅ ตรวจสอบข้อมูลที่ Slave ได้รับ
		assert_val(8'hA5, s_rx_data, "Slave received 0xA5 correctly");
		
		// ✅ ตรวจสอบ ACK ที่ Master ได้รับ (ต้องเป็น 0)
		assert_val(1'b0, m_rx_ack, "Master received ACK from Slave (0 = ACK)");

		// --- 📖 SCENARIO 2: Master Reads 0xC3 from Slave ---
		$display("\n--- 📖 SCENARIO 2: Master Reads 0xC3 from Slave ---");

		// 1. Setup Slave (คนส่ง)
		s_is_read = 0; s_tx_data = 8'hC3;
		@(negedge clk); s_load = 1; s_enable = 1;
		@(negedge clk); s_load = 0; s_enable = 0;

		// 2. Setup Master (คนรับ)
		m_is_read = 1; m_ack_phase = 1; // Master จะตอบ NACK เพื่อจบการอ่าน
		@(negedge clk); m_enable = 1;
		@(negedge clk); m_enable = 0;

		// 3. ปล่อย SCL 9 คล็อค
		for (i = 0; i < 9; i = i + 1) gen_scl();

		// 4. เช็คผล
		assert_val(8'hC3, m_rx_data, "Master received 0xC3 correctly");
		assert_val(1'b1, s_rx_ack, "Slave received NACK from Master");

		// --- SCENARIO 3: Arbitration Lost ---
		$display("\n--- ⚔️ SCENARIO 3: Arbitration Lost ---");
		m_is_read = 0; m_tx_data = 8'hFF;
		@(negedge clk); m_load = 1; m_enable = 1; @(negedge clk); m_load = 0; m_enable = 0;
		gen_scl(); // Bit 0 normal
		#1000; m_scl_drive = 0; // SCL High
		#500;  compete_sda_drive = 1; // 💥 แย่งบัส
		repeat(6) @(posedge clk); // รอดีเลย์จาก Pad + Filter + Logic
		assert_val(1'b1, m_arb_lost, "Arbitration Lost detected through filter");
		compete_sda_drive = 0;
		repeat(10) @(posedge clk);

		// --- 🛡️ SCENARIO 4: Glitch Suppression Test (Corrected) ---
		$display("\n--- 🛡️ SCENARIO 4: Glitch Suppression Test ---");
		
		// ⭐️ แก้เป็น 8'hFF เพื่อให้ Master ส่ง 1 ตลอดเวลา
		m_is_read = 0; m_tx_data = 8'hFF; 
		@(negedge clk); m_load = 1; m_enable = 1; @(negedge clk); m_load = 0; m_enable = 0;
		
		#1000; m_scl_drive = 0; // SCL High (เข้าช่วง Sample)

		// กรณีที่ 1: หนามสั้น (20ns) -> ต้องเงียบ
		$display("Injecting 20ns glitch...");
		#500; noise_inject = 1; #20; noise_inject = 0; 
		repeat(10) @(negedge clk);
		assert_val(1'b0, m_arb_lost, "Filter ignored the short glitch");

		// กรณีที่ 2: สัญญาณรบกวนยาว (200ns) -> ต้อง Error!
		$display("Injecting 200ns fake signal...");
		#500; noise_inject = 1; // ดึง SDA เป็น 0
		
		// รอให้สัญญาณไหลผ่าน Pad + Filter (ใช้เวลาประมาณ 5-6 คล็อค)
		repeat(10) @(negedge clk); 
		
		assert_val(1'b1, m_arb_lost, "System detected long interference");
		
		#100; noise_inject = 0; // ปล่อย Noise

		$display("\n=======================================================");
		if (error_count == 0) $display(" 🎉 MISSION ACCOMPLISHED: System is Glitch-Proof!");
		else                  $display(" 💥 SYSTEM VULNERABLE: %d Errors found", error_count);
		$display("=======================================================\n");
		#500 $finish;
	end
endmodule