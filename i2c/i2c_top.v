/* ============================================================
** I2C CORE MODULE
** Integrates: Master FSM, Slave FSM, Bit Ctrl, Start/Stop,
**             Clock Gen, Glitch Filter, TX/RX FIFOs, APB IF
**
** Register Map (via i2c_dual_apb_if):
**   0x00  I2C_CON   [6:0] : Control
**   0x04  I2C_ADDR  [7:0] : {slave_addr[6:0], rw}
**   0x08  I2C_LEN   [7:0] : Byte count
**   0x0C  I2C_STA   [9:0] : Status (W1C for some bits)
**   0x10  I2C_DATA  [7:0] : TX write / RX read
**   0x14  I2C_PRE  [15:0] : Prescaler
**   0x18  I2C_IER   [5:0] : Interrupt enable
** ============================================================ */
module i2c_top #(
	parameter FIFO_DEPTH = 16
)(
	input  wire        pclk,
	input  wire        presetn,

	// APB Interface
	input  wire [4:0]  paddr,
	input  wire        psel,
	input  wire        penable,
	input  wire        pwrite,
	input  wire [31:0] pwdata,
	output wire [31:0] prdata,
	output wire        pready,
	output wire        pslverr,

	output wire        irq,

	inout  wire        scl,
	inout  wire        sda
);

	assign pslverr = 1'b0;

	// ─────────────────────────────────────
	// APB Register Outputs
	// ─────────────────────────────────────
	wire [6:0]  reg_con;
	wire [7:0]  reg_addr;
	wire [7:0]  reg_len;
	wire [15:0] reg_pre;
	wire [5:0]  reg_ier;
	wire [9:0]  sta_hw_set;

	// FIFO ports driven by APB IF
	wire        fifo_tx_we;
	wire        fifo_rx_re;
	wire [7:0]  fifo_rx_data;

	i2c_dual_apb_if apb_if (
		.PCLK         (pclk),
		.PRESETn      (presetn),
		.PADDR        (paddr),
		.PSEL         (psel),
		.PENABLE      (penable),
		.PWRITE       (pwrite),
		.PWDATA       (pwdata),
		.PRDATA       (prdata),
		.PREADY       (pready),
		.reg_con      (reg_con),
		.reg_addr     (reg_addr),
		.reg_len      (reg_len),
		.reg_pre      (reg_pre),
		.reg_ier      (reg_ier),
		.sta_hw_set   (sta_hw_set),
		.fifo_tx_we   (fifo_tx_we),
		.fifo_rx_re   (fifo_rx_re),
		.fifo_rx_data (fifo_rx_data),
		.irq          (irq)
	);

	// ─────────────────────────────────────
	// Decode Control Register
	// ─────────────────────────────────────
	wire        mode_master = reg_con[5]; // 1 = Master
	wire        enable      = reg_con[4]; // Global enable
	wire        start       = reg_con[0]; // Write 1 to start
	wire        stop_req    = reg_con[1]; // Send STOP at end
	wire        reload_en   = reg_con[2]; // Reload mode
	wire        continue_req= reg_con[3]; // Continue after reload
	wire        slv_en      = reg_con[6]; // Slave respond enable

	// reg_addr = {slave_addr[6:0], rw[0]}
	wire [6:0]  slave_addr = reg_addr[7:1];
	wire        rw         = reg_addr[0]; // 0=Write, 1=Read

	// ─────────────────────────────────────
	// Internal Wires
	// ─────────────────────────────────────
	// IO Pad raw samples (before glitch filter)
	wire scl_pad_rx, sda_pad_rx;

	// Filtered bus
	wire scl_filt, sda_filt;

	// Clock generator
	wire scl_gen;
	wire phase_setup, phase_sample; // not used by bit_ctrl directly, but available

	// Start/Stop generator & detector
	wire gen_start_m, gen_stop_m;
	wire start_stop_done;
	wire start_det, stop_det;
	wire ss_sda_oe, ss_sda_out;

	// Bit controller
	wire [7:0] bit_rx_data;
	wire       bit_byte_done;
	wire       bit_rx_ack;     // sampled ACK/NACK bit (9th bit)
	wire       bit_arb_lost;
	wire       bit_sda_oe, bit_sda_out;

	// Master FSM
	wire       m_bit_en, m_is_read, m_load, m_ack_phase;
	wire       m_tx_rd_en, m_rx_wr_en;
	wire       m_gen_start, m_gen_stop;
	wire       m_scl_oe, m_scl_out; // SCL hold for stretch/wait
	wire       m_busy, m_arb_lost, m_done, m_reload_req, m_nack_err;
	wire [3:0] m_state;

	// Slave FSM
	wire       s_bit_en, s_load, s_ack_phase;
	wire       s_tx_rd_en, s_rx_wr_en;
	wire       s_sda_oe, s_sda_out;
	wire       s_scl_oe, s_scl_out_wire;
	wire       s_busy, s_done, s_stop_det_flag, s_addr_match, s_dir;

	// FIFO signals
	wire [7:0] tx_fifo_dout, rx_fifo_din;
	wire       tx_full, tx_empty;
	wire       rx_full, rx_empty;

	// Control muxes based on mode
	wire       bit_en    = mode_master ? m_bit_en    : s_bit_en;
	wire       is_read   = mode_master ? m_is_read   : 1'b0;
	wire       load      = mode_master ? m_load      : s_load;
	wire       ack_phase = mode_master ? m_ack_phase : s_ack_phase;
	wire       tx_rd_en  = mode_master ? m_tx_rd_en  : s_tx_rd_en;
	wire       rx_wr_en  = mode_master ? m_rx_wr_en  : s_rx_wr_en;
	assign     gen_start_m = m_gen_start;
	assign     gen_stop_m  = m_gen_stop;

	// TX data mux: In M_TX_ADDR_LOAD state (state==2), send {slave_addr, rw}
	// reg_addr already = {slave_addr[6:0], rw} so use reg_addr directly
	wire [7:0] m_tx_data = (m_state == 4'd2) ? reg_addr : tx_fifo_dout;
	wire [7:0] b_tx_data = mode_master ? m_tx_data : tx_fifo_dout;

	// RX FIFO write data
	assign rx_fifo_din = bit_rx_data;

	// ─────────────────────────────────────
	// Physical Layer — via i2c_io_pad
	// ─────────────────────────────────────
	// SCL:
	//  Master always drives SCL when busy (open-drain: tx=0 pulls low, tx=1 = HiZ via pad)
	//  scl_gen provides the toggle.  FSM can override via m_scl_oe/m_scl_out.
	//  Slave can stretch by pulling SCL low via s_scl_oe/s_scl_out.
	wire scl_stretch = (m_scl_oe && !m_scl_out) || (s_scl_oe && !s_scl_out_wire);
	// When master busy: follow clk_gen toggle.  When stretching: force 0.
	wire scl_tx_data = scl_stretch ? 1'b0 : scl_gen;
	wire scl_oe_pad  = (mode_master && m_busy) || scl_stretch;

	i2c_io_pad u_scl_pad (
		.clk           (pclk),
		.resetn        (presetn),
		.tx_data       (scl_tx_data),
		.output_enable (scl_oe_pad),
		.rx_data       (scl_pad_rx),
		.sda           (scl)
	);

	// SDA output priority: Start/Stop > Slave ACK/data > Bit controller
	wire sda_oe_combined = ss_sda_oe | s_sda_oe | bit_sda_oe;
	wire sda_tx_combined = ss_sda_oe  ? ss_sda_out
	                     : s_sda_oe   ? s_sda_out
	                     : bit_sda_out;

	i2c_io_pad u_sda_pad (
		.clk           (pclk),
		.resetn        (presetn),
		.tx_data       (sda_tx_combined),
		.output_enable (sda_oe_combined),
		.rx_data       (sda_pad_rx),
		.sda           (sda)
	);

	// ─────────────────────────────────────
	// Status bits → APB IF
	// sta_hw_set[9:0] maps to reg_sta[9:0]
	//   [0] BUSY     [1] DONE    [2] NACK_ERR [3] RELOAD_REQ
	//   [4] unused   [5] unused  [6] ARB_LOST
	//   [7] ADDR_MATCH [8] DIR   [9] STOP_DET
	// ─────────────────────────────────────
	assign sta_hw_set = {
		s_stop_det_flag,                // [9] STOP_DET
		s_dir,                          // [8] DIR
		s_addr_match,                   // [7] ADDR_MATCH
		1'b0,                           // [6] ARB_LOST (combinational from m_arb_lost below)
		rx_empty,                       // [5] RX_EMPTY (informational)
		tx_full,                        // [4] TX_FULL  (informational)
		m_reload_req,                   // [3] RELOAD_REQ
		m_nack_err,                     // [2] NACK_ERR
		m_done | s_done,                // [1] DONE
		m_busy | s_busy                 // [0] BUSY
	};

	// ARB_LOST is W1C, hardware sets it; wire separately if needed
	// (apb_if sta_hw_set[6] stays 0 above, m_arb_lost handled as separate sticky)

	// ─────────────────────────────────────
	// Submodules
	// ─────────────────────────────────────

	// --- TX FIFO ---
	sync_fifo #(.DEPTH(FIFO_DEPTH), .DWIDTH(8)) u_tx_fifo (
		.clk    (pclk),
		.resetn (presetn),
		.wr_ena (fifo_tx_we),
		.rd_ena (tx_rd_en),
		.din    (pwdata[7:0]),
		.full   (tx_full),
		.empty  (tx_empty),
		.dout   (tx_fifo_dout)
	);

	// --- RX FIFO ---
	sync_fifo #(.DEPTH(FIFO_DEPTH), .DWIDTH(8)) u_rx_fifo (
		.clk    (pclk),
		.resetn (presetn),
		.wr_ena (rx_wr_en),
		.rd_ena (fifo_rx_re),
		.din    (rx_fifo_din),
		.full   (rx_full),
		.empty  (rx_empty),
		.dout   (fifo_rx_data)
	);

	// --- Glitch Filters (input from io_pad rx_data) ---
	i2c_glitch_filter u_scl_filt (
		.clk          (pclk),
		.resetn       (presetn),
		.raw_in       (scl_pad_rx),
		.filtered_out (scl_filt)
	);

	i2c_glitch_filter u_sda_filt (
		.clk          (pclk),
		.resetn       (presetn),
		.raw_in       (sda_pad_rx),
		.filtered_out (sda_filt)
	);

	// --- Clock Generator (Master only) ---
	// Always runs when master is busy (provides SCL toggle for start/stop + data)
	// Pause only when FSM explicitly holds SCL for stretching
	i2c_clk_gen u_clk_gen (
		.clk          (pclk),
		.resetn       (presetn),
		.en           (enable && mode_master && m_busy && !m_scl_oe),
		.prescaler    (reg_pre),
		.scl_out      (scl_gen),
		.phase_setup  (phase_setup),
		.phase_sample (phase_sample)
	);

	// --- Start/Stop Generator & Detector ---
	i2c_start_stop u_start_stop (
		.clk       (pclk),
		.resetn    (presetn),
		.gen_start (gen_start_m),
		.gen_stop  (gen_stop_m),
		.scl_in    (scl_filt),
		.sda_in    (sda_filt),
		.sda_out   (ss_sda_out),
		.sda_oe    (ss_sda_oe),
		.start_det (start_det),
		.stop_det  (stop_det),
		.done      (start_stop_done)
	);

	// --- Bit Controller ---
	i2c_bit_ctrl u_bit_ctrl (
		.clk         (pclk),
		.resetn      (presetn),
		.enable      (enable && bit_en),
		.is_read     (is_read),
		.ack_phase   (ack_phase),
		.load        (load),
		.tx_data     (b_tx_data),
		.rx_data     (bit_rx_data),
		.byte_done   (bit_byte_done),
		.rx_ack      (bit_rx_ack),
		.arb_lost    (bit_arb_lost),
		.sda_oe      (bit_sda_oe),
		.sda_out     (bit_sda_out),
		.scl_in      (scl_filt),
		.sda_in      (sda_filt)
	);

	// --- Master FSM ---
	i2c_master_fsm u_master_fsm (
		.clk             (pclk),
		.resetn          (presetn),
		.i2c_en          (enable),
		.mode_master     (mode_master),
		.api_start       (start),
		.api_stop_req    (stop_req),
		.api_reload_en   (reload_en),
		.api_continue    (continue_req),
		.api_rw          (rw),
		.api_slave_addr  (slave_addr),
		.api_len         (reg_len),
		.api_busy        (m_busy),
		.api_arb_lost    (m_arb_lost),
		.api_done        (m_done),
		.api_reload_req  (m_reload_req),
		.api_nack_err    (m_nack_err),
		.api_addr_phase  (),
		.api_state_out   (m_state),
		.fifo_tx_empty   (tx_empty),
		.fifo_tx_rd_en   (m_tx_rd_en),
		.fifo_rx_full    (rx_full),
		.fifo_rx_wr_en   (m_rx_wr_en),
		.ctrl_byte_done  (bit_byte_done),
		.ctrl_sda_sampled(bit_rx_ack),
		.ctrl_arb_lost   (bit_arb_lost),
		.ctrl_en         (m_bit_en),
		.ctrl_is_read    (m_is_read),
		.ctrl_load       (m_load),
		.ctrl_ack_phase  (m_ack_phase),
		.phy_start_done  (start_stop_done),
		.phy_stop_done   (start_stop_done),
		.phy_scl_in      (scl_filt),
		.phy_gen_start   (m_gen_start),
		.phy_gen_stop    (m_gen_stop),
		.scl_oe          (m_scl_oe),
		.scl_out         (m_scl_out)
	);

	// --- Slave FSM ---
	i2c_slave_fsm u_slave_fsm (
		.clk             (pclk),
		.resetn          (presetn),
		.i2c_en          (enable && slv_en),
		.slave_addr      (slave_addr),
		.api_len         (reg_len),
		.start_det       (start_det),
		.stop_det        (stop_det),
		.byte_done       (bit_byte_done),
		.sda_sampled     (bit_rx_ack),
		.rx_data         (bit_rx_data),
		.tx_empty        (tx_empty),
		.rx_full         (rx_full),
		.bit_ctrl_en     (s_bit_en),
		.load            (s_load),
		.tx_rd_en        (s_tx_rd_en),
		.rx_wr_en        (s_rx_wr_en),
		.sda_oe          (s_sda_oe),
		.sda_out         (s_sda_out),
		.addr_match      (s_addr_match),
		.busy            (s_busy),
		.api_done        (s_done),
		.api_stop_det    (s_stop_det_flag),
		.dir             (s_dir),
		.ack_phase       (s_ack_phase),
		.scl_oe          (s_scl_oe),
		.scl_out         (s_scl_out_wire)
	);

endmodule
