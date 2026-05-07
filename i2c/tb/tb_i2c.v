`timescale 1ns/1ps

module tb_i2c;

	// ─────────────────────────────────────
	// Parameters & Constants
	// ─────────────────────────────────────
	parameter FIFO_DEPTH = 16;
	parameter CLK_PERIOD = 10;
	parameter PRESCALER  = 16'd5; 

	// ─────────────────────────────────────
	// Global Counters for Reporting
	// ─────────────────────────────────────
	integer pass_count = 0;
	integer fail_count = 0;
	integer test_num   = 0;

	// ─────────────────────────────────────
	// Signal Declaration
	// ─────────────────────────────────────
	reg clk, resetn;

	// Master
	reg        m_enable, m_start, m_rw;
	reg [6:0]  m_slave_addr;
	reg        m_tx_wr_en, m_rx_rd_en;
	reg [7:0]  m_tx_wr_data;
	wire [7:0] m_rx_rd_data, m_int_status;
	wire       m_irq, m_busy, m_tx_empty, m_rx_empty, m_tx_full;

	// Slave
	reg [6:0]  s_slave_addr;
	reg        s_tx_wr_en, s_rx_rd_en;
	reg [7:0]  s_tx_wr_data;
	wire [7:0] s_rx_rd_data;
	wire       s_busy, s_rx_empty, s_rx_full;

	// Bus
	wire scl, sda;
	pullup(scl);
	pullup(sda);

	// ─────────────────────────────────────
	// DUT Instantiations
	// ─────────────────────────────────────
	i2c #(FIFO_DEPTH) u_master (
		.clk(clk), .resetn(resetn), .mode_master(1'b1), .enable(m_enable),
		.start(m_start), .rw(m_rw), .slave_addr(m_slave_addr), .prescaler(PRESCALER),
		.tx_wr_en(m_tx_wr_en), .tx_wr_data(m_tx_wr_data), .rx_rd_en(m_rx_rd_en),
		.rx_rd_data(m_rx_rd_data), .int_en(8'hFF), .int_clr(8'h00),
		.int_status(m_int_status), .irq(m_irq), .busy(m_busy),
		.tx_empty(m_tx_empty), .tx_full(m_tx_full), .rx_empty(m_rx_empty),
		.scl(scl), .sda(sda)
	);

	i2c #(FIFO_DEPTH) u_slave (
		.clk(clk), .resetn(resetn), .mode_master(1'b0), .enable(1'b1),
		.slave_addr(s_slave_addr), .tx_wr_en(s_tx_wr_en), .tx_wr_data(s_tx_wr_data),
		.rx_rd_en(s_rx_rd_en), .rx_rd_data(s_rx_rd_data), .busy(s_busy),
		.rx_empty(s_rx_empty), .rx_full(s_rx_full), .scl(scl), .sda(sda)
	);

	// ─────────────────────────────────────
	// Clock Generation
	// ─────────────────────────────────────
	initial clk = 0;
	always #(CLK_PERIOD/2) clk = ~clk;

	// ─────────────────────────────────────
	// Logging & Verification Tasks
	// ─────────────────────────────────────
	task log_result;
		input condition;
		input [7:0] actual;
		input [511:0] msg;
		begin
			if (condition) begin
				$display("  [PASS] %s (got %h)", msg, actual);
				pass_count = pass_count + 1;
			end else begin
				$display("  [FAIL] %s (got %h)", msg, actual);
				fail_count = fail_count + 1;
			end
		end
	endtask

	task apply_reset;
		begin
			resetn = 0;
			m_enable = 0; m_start = 0; m_tx_wr_en = 0;
			s_tx_wr_en = 0; m_rx_rd_en = 0; s_rx_rd_en = 0;
			#(CLK_PERIOD * 10);
			resetn = 1;
			@(posedge clk); #1;
		end
	endtask

	task master_send;
		input [7:0] data;
		begin
			m_tx_wr_data = data;
			m_tx_wr_en = 1;
			@(posedge clk); #1;
			m_tx_wr_en = 0;
		end
	endtask

	task slave_prepare;
		input [7:0] data;
		begin
			s_tx_wr_data = data;
			s_tx_wr_en = 1;
			@(posedge clk); #1;
			s_tx_wr_en = 0;
		end
	endtask

	// ─────────────────────────────────────
	// Main Simulation Logic
	// ─────────────────────────────────────
	
	initial begin
		$display("\n==================================================");
		$display("   I2C CONTROLLER COMPREHENSIVE TESTBENCH");
		$display("==================================================");
		apply_reset;

		// ────────────────────────────────────────────────
		// TEST 1: MULTI-BYTE WRITE LOOPBACK
		// ────────────────────────────────────────────────
		test_num = 1;
		$display("\nTEST %0d: Multi-Byte Write (0x3C)", test_num);
		s_slave_addr = 7'h3C;
		m_slave_addr = 7'h3C;
		m_rw = 0; m_enable = 1;

		master_send(8'h11);
		master_send(8'h22);
		master_send(8'h33);
		
		m_start = 1; @(posedge clk); #1; m_start = 0;
		wait(m_busy); wait(!m_busy);
		#(CLK_PERIOD*10);

		s_rx_rd_en = 1;
		@(posedge clk); log_result(s_rx_rd_data === 8'h11, s_rx_rd_data, "Byte 1 Received Correctly");
		@(posedge clk); log_result(s_rx_rd_data === 8'h22, s_rx_rd_data, "Byte 2 Received Correctly");
		@(posedge clk); log_result(s_rx_rd_data === 8'h33, s_rx_rd_data, "Byte 3 Received Correctly");
		s_rx_rd_en = 0;

		// ────────────────────────────────────────────────
		// TEST 2: MASTER READ FROM SLAVE
		// ────────────────────────────────────────────────
		test_num = 2;
		$display("\nTEST %0d: Master Read (0x3C)", test_num);
		slave_prepare(8'hAA);
		slave_prepare(8'hBB);
		
		m_rw = 1;
		m_start = 1; @(posedge clk); #1; m_start = 0;
		wait(m_busy); wait(!m_busy);
		#(CLK_PERIOD*10);

		m_rx_rd_en = 1;
		@(posedge clk); log_result(m_rx_rd_data === 8'hAA, m_rx_rd_data, "Master Read Byte 1 Correct");
		@(posedge clk); log_result(m_rx_rd_data === 8'hBB, m_rx_rd_data, "Master Read Byte 2 Correct");
		m_rx_rd_en = 0;

		// ────────────────────────────────────────────────
		// TEST 3: NACK ON WRONG ADDRESS
		// ────────────────────────────────────────────────
		test_num = 3;
		$display("\nTEST %0d: NACK Detection (Addressing 0x7F)", test_num);
		m_slave_addr = 7'h7F; 
		m_rw = 0;
		master_send(8'hFF);
		
		m_start = 1; @(posedge clk); #1; m_start = 0;
		wait(m_busy); wait(!m_busy);
		
		log_result(m_int_status[4], m_int_status, "NACK Flag set in Master Status");
		log_result(s_rx_empty, {7'b0, s_rx_empty}, "Slave RX FIFO remains empty (Correct)");

		// ────────────────────────────────────────────────
		// TEST 4: FIFO OVERFLOW PROTECTION
		// ────────────────────────────────────────────────
		test_num = 4;
		$display("\nTEST %0d: Master TX FIFO Overflow Stress", test_num);
		for (integer i=0; i < FIFO_DEPTH + 2; i++) begin
			master_send(i);
		end
		log_result(m_tx_full, {7'b0, m_tx_full}, "Master TX FIFO reports FULL");
		
		// ────────────────────────────────────────────────
		// TEST 5: REPEATED START (Write then Read)
		// ────────────────────────────────────────────────
		// (Assuming your FSM supports consecutive starts without stop)
		test_num = 5;
		$display("\nTEST %0d: Repeated START (Write Addr -> Read Data)", test_num);
		apply_reset;
		s_slave_addr = 7'h55;
		m_slave_addr = 7'h55;
		slave_prepare(8'hE2); // Data for read phase
		
		m_enable = 1;
		m_rw = 0; master_send(8'h01); // Write command
		m_start = 1; @(posedge clk); #1; m_start = 0;
		wait(m_busy); wait(!m_busy);
		
		m_rw = 1; // Immediately switch to read
		m_start = 1; @(posedge clk); #1; m_start = 0;
		wait(m_busy); wait(!m_busy);

		m_rx_rd_en = 1; @(posedge clk);
		log_result(m_rx_rd_data === 8'hE2, m_rx_rd_data, "Repeated START Read Successful");
		m_rx_rd_en = 0;

		// ─────────────────────────────────────
		// FINAL REPORT
		// ─────────────────────────────────────
		$display("\n==================================================");
		$display("   FINAL TEST REPORT");
		$display("   Tests Run:    %0d", test_num);
		$display("   Passed:       %0d", pass_count);
		$display("   Failed:       %0d", fail_count);
		$display("==================================================");
		
		if (fail_count == 0) $display("   RESULT: SYSTEM VERIFIED");
		else                $display("   RESULT: BUGS DETECTED");
		$display("==================================================\n");
		$finish;
	end

	initial begin
		$dumpfile("tb_i2c.vcd");
		$dumpvars(0, tb_i2c);
	end

endmodule