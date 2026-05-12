`timescale 1ns / 1ps

module tb_i2c_integration;

    // ========================================================
    // 1. Clock & Reset & API Signals
    // ========================================================
    reg clk;
    reg resetn;
    
    // API to FSM
    reg        i2c_en, mode_master, api_start, api_stop_req, api_reload_en, api_continue, api_rw;
    reg [6:0]  api_slave_addr;
    reg [7:0]  api_len;
    wire       api_busy, api_done, api_nack_err;
    wire [3:0] api_state_out;

    // FIFO Mock
    reg [7:0]  mock_tx_fifo [0:15];
    reg [3:0]  tx_fifo_ptr;
    wire       fifo_tx_empty = (tx_fifo_ptr == 0);
    wire       fifo_tx_rd_en;
    reg [7:0]  tx_data_to_ctrl;

    // ========================================================
    // 2. Wires สำหรับต่อระหว่าง Sub-modules
    // ========================================================
    // Clk Gen <-> Bit Ctrl
    wire scl_gen_out, phase_setup, phase_sample;
    
    // FSM <-> Bit Ctrl
    wire ctrl_byte_done, ctrl_sda_sampled, ctrl_arb_lost;
    wire ctrl_en, ctrl_is_read, ctrl_load, ctrl_ack_phase;
    wire [7:0] rx_data_from_ctrl;
    wire rx_ack_from_ctrl;
    wire bit_sda_oe, bit_sda_out;

    // FSM <-> PHY Layer (Start/Stop)
    wire phy_gen_start, phy_gen_stop;
    reg  phy_start_done, phy_stop_done;
    
    // FSM <-> SCL Stretch
    wire fsm_scl_oe, fsm_scl_out;

    // ========================================================
    // 3. I2C Physical Bus (Open-Drain Simulation)
    // ========================================================
    wire scl, sda;
    pullup(scl); // จำลอง R Pull-up นอกชิป
    pullup(sda); // จำลอง R Pull-up นอกชิป

    // ตัวแปรขับสาย (Drive)
    reg phy_scl_drive, phy_scl_val;
    reg phy_sda_drive, phy_sda_val;
    reg slave_sda_drive, slave_sda_val;

    // การรวมสาย SCL/SDA (ใครดึง 0 สายจะเป็น 0 ทันที)
    assign scl = (phy_scl_drive && !phy_scl_val) ? 1'b0 :
                 (fsm_scl_oe && !fsm_scl_out)    ? 1'b0 :
                 (!scl_gen_out && ctrl_en)       ? 1'b0 : 1'bz;

    assign sda = (phy_sda_drive && !phy_sda_val) ? 1'b0 :
                 (bit_sda_oe && !bit_sda_out)    ? 1'b0 : 
                 (slave_sda_drive && !slave_sda_val) ? 1'b0 : 1'bz;

    // ========================================================
    // 4. Instantiate โมดูลลูกทั้งหมด
    // ========================================================
    i2c_clk_gen u_clk_gen (
        .clk(clk), .resetn(resetn), .en(i2c_en), .prescaler(16'd25), // ให้ Clock เร็วหน่อยตอน Sim
        .scl_out(scl_gen_out), .phase_setup(phase_setup), .phase_sample(phase_sample)
    );

    // โมดูลที่คุณเขียนรอบที่แล้ว (รับ phase จาก clk_gen เป็น trigger_setup/sample ได้เลย)
    i2c_bit_ctrl u_bit_ctrl (
        .clk(clk), .resetn(resetn), .enable(ctrl_en), .is_read(ctrl_is_read),
        .ack_phase(ctrl_ack_phase), .load(ctrl_load), .tx_data(tx_data_to_ctrl),
        .rx_data(rx_data_from_ctrl), .rx_ack(ctrl_sda_sampled), .byte_done(ctrl_byte_done),
        .arb_lost(ctrl_arb_lost), .sda_oe(bit_sda_oe), .sda_out(bit_sda_out),
        .scl_in(scl), .sda_in(sda) // อ่านค่าจริงจากบัส
    );

    i2c_master_fsm u_fsm (
        .clk(clk), .resetn(resetn), .i2c_en(i2c_en), .mode_master(mode_master),
        .api_start(api_start), .api_stop_req(api_stop_req), .api_reload_en(api_reload_en),
        .api_continue(api_continue), .api_rw(api_rw), .api_slave_addr(api_slave_addr),
        .api_len(api_len), .api_busy(api_busy), .api_done(api_done), .api_nack_err(api_nack_err),
        .api_state_out(api_state_out),
        .fifo_tx_empty(fifo_tx_empty), .fifo_tx_rd_en(fifo_tx_rd_en),
        .fifo_rx_full(1'b0), // สมมติว่า RX ไม่เคยเต็ม
        .ctrl_byte_done(ctrl_byte_done), .ctrl_sda_sampled(ctrl_sda_sampled),
        .ctrl_arb_lost(ctrl_arb_lost), .ctrl_en(ctrl_en), .ctrl_is_read(ctrl_is_read),
        .ctrl_load(ctrl_load), .ctrl_ack_phase(ctrl_ack_phase),
        .phy_start_done(phy_start_done), .phy_stop_done(phy_stop_done),
        .phy_gen_start(phy_gen_start), .phy_gen_stop(phy_gen_stop),
        .scl_oe(fsm_scl_oe), .scl_out(fsm_scl_out)
    );

    // ========================================================
    // 5. Mock Logic: TX FIFO & Physical Start/Stop
    // ========================================================
    initial clk = 0;
    always #10 clk = ~clk;

    // Mock TX FIFO
    always @(posedge clk) begin
        if (fifo_tx_rd_en && tx_fifo_ptr > 0) begin
            tx_data_to_ctrl <= mock_tx_fifo[tx_fifo_ptr - 1];
            tx_fifo_ptr <= tx_fifo_ptr - 1;
        end
    end

    // --- MOCK PHYSICAL LAYER (FIXED) ---
    // ใช้ always @(posedge) จับสัญญาณคำสั่งตรงๆ แทนการผูกกับ clk
    initial begin
        phy_scl_drive = 0; phy_sda_drive = 0;
        phy_start_done = 0; phy_stop_done = 0;
    end

    // สร้าง START Condition
    always @(posedge phy_gen_start) begin
        phy_sda_drive = 1; phy_sda_val = 0; // ดึง SDA ลง
        #500; 
        phy_scl_drive = 1; phy_scl_val = 0; // ดึง SCL ลงตาม
        #100; 
        phy_start_done = 1; // ส่งสัญญาณบอก FSM ว่าเสร็จแล้ว
        
        wait(!phy_gen_start); // รอจนกว่า FSM จะเอาคำสั่ง start ออก
        phy_start_done = 0;
        // 🛑 สำคัญมาก: ปล่อยสาย SCL/SDA คืนให้ FSM และ Bit Ctrl ควบคุมต่อ!
        phy_scl_drive = 0; 
        phy_sda_drive = 0; 
    end

    // สร้าง STOP Condition
    always @(posedge phy_gen_stop) begin
        phy_sda_drive = 1; phy_sda_val = 0; // ดึง SDA ลงรอไว้ก่อน
        phy_scl_drive = 0; // ปล่อย SCL ขึ้น High
        #500; 
        phy_sda_drive = 0; // ปล่อย SDA ขึ้น High (จังหวะนี้คือ STOP)
        #100; 
        phy_stop_done = 1;
        
        wait(!phy_gen_stop);
        phy_stop_done = 0;
        phy_sda_drive = 0;
    end

    // ========================================================
    // 6. MOCK SLAVE: แกล้งทำตัวเป็น Slave เพื่อตอบ ACK
    // ========================================================
    integer bit_count = 0;
    always @(negedge scl) begin // จับขอบขาลงของ SCL
        if (ctrl_en) begin
            bit_count = bit_count + 1;
            if (bit_count == 8) begin
                // จังหวะบิตที่ 9 (ACK Phase)
                slave_sda_drive <= 1; 
                slave_sda_val <= 0; // ดึง 0 = ACK
            end else if (bit_count == 9) begin
                // จบไบต์ ปล่อยสายและรีเซ็ต
                slave_sda_drive <= 0;
                bit_count = 0;
            end
        end
    end
    always @(negedge ctrl_en) bit_count = 0; // รีเซ็ตตัวนับเมื่อจบเฟส

    // ========================================================
    // 7. ลำดับเหตุการณ์ทดสอบ (The Sequence)
    // ========================================================
    initial begin
        $dumpfile("tb_i2c_integration.vcd");
        $dumpvars(0, tb_i2c_integration);

        // Init
        resetn = 0; i2c_en = 0; mode_master = 1;
        api_start = 0; api_stop_req = 0; api_rw = 0;
        phy_scl_drive = 0; phy_sda_drive = 0; slave_sda_drive = 0;
        tx_fifo_ptr = 0;

        #100 resetn = 1; i2c_en = 1;
        #100;

        $display("\n🚀 STARTING I2C FULL INTEGRATION TEST 🚀\n");

        // ยัดข้อมูล 2 ไบต์ลง TX FIFO สมมติ (0xAA และ 0x55)
        mock_tx_fifo[0] = 8'h55; // ไบต์ที่ 2
        mock_tx_fifo[1] = 8'hAA; // ไบต์ที่ 1
        tx_fifo_ptr = 2;

        // สั่ง FSM เริ่มงาน: ส่งไปที่ Slave 0x5A, จำนวน 2 ไบต์, เขียนจบให้ Stop
        api_slave_addr = 7'h5A; 
        api_rw = 0; 
        api_len = 2; 
        api_stop_req = 1;

        @(posedge clk); api_start = 1;
        @(posedge clk); api_start = 0;

        // รอจนกว่า FSM จะทำงานเสร็จ (api_done = 1)
        wait(api_done);
        $display("[%0t] ✅ I2C Transaction Completed Successfully!", $time);

        #2000;
        $finish;
    end

endmodule