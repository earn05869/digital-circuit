module i2c #(
	parameter FIFO_DEPTH = 16
)(
	input  wire        clk,
	input  wire        resetn,
	input  wire        mode_master,
	input  wire        enable,
	input  wire        start,
	input  wire        rw,
	input  wire [6:0]  slave_addr,
	input  wire [15:0] prescaler,

	input  wire        tx_wr_en,
	input  wire [7:0]  tx_wr_data,
	output wire        tx_full,
	output wire        tx_empty,

	input  wire        rx_rd_en,
	output wire [7:0]  rx_rd_data,
	output wire        rx_full,
	output wire        rx_empty,

	input  wire [7:0]  int_en,
	input  wire [7:0]  int_clr,
	output wire [7:0]  int_status,
	output wire        irq,

	output wire        busy,
	output wire        arb_lost,

	inout  wire        scl,
	inout  wire        sda
);

	// ---------------------------------------------------------
	// Signal Declarations
	// ---------------------------------------------------------
	wire scl_filt, sda_filt, scl_gen_out;
	wire gen_start, gen_stop, start_stop_done;
	wire start_det, stop_det;
	wire startstop_sda_out, startstop_sda_oe;
	wire bit_ctrl_en_m, bit_ctrl_en_s, bit_ctrl_en;
	wire load_m, load_s, load_bit_ctrl;
	wire tx_rd_en_m, tx_rd_en_s, tx_rd_en;
	wire rx_wr_en_m, rx_wr_en_s, rx_wr_en;
	wire busy_m, busy_s, arb_lost_m;
	wire ack_phase_m, ack_phase_s, ack_phase;
	wire [7:0] tx_fifo_dout, rx_data;
	wire [3:0] m_state;
	wire sda_sampled, byte_done;
	wire bitctrl_sda_oe, bitctrl_sda_out;
	wire slave_sda_oe, slave_sda_out;

	// ---------------------------------------------------------
	// Control Routing & Address Muxing
	// ---------------------------------------------------------
	assign bit_ctrl_en   = mode_master ? bit_ctrl_en_m : bit_ctrl_en_s;
	assign load_bit_ctrl = mode_master ? load_m         : load_s;
	assign tx_rd_en      = mode_master ? tx_rd_en_m    : tx_rd_en_s;
	assign rx_wr_en      = mode_master ? rx_wr_en_m    : rx_wr_en_s;
	assign ack_phase     = mode_master ? ack_phase_m   : ack_phase_s;
	assign busy          = mode_master ? busy_m        : busy_s;
	assign arb_lost      = mode_master ? arb_lost_m    : 1'b0;

	// Address Mux: state 2 is ADDR
	wire [7:0] m_tx_mux  = (m_state == 4'd2) ? {slave_addr, rw} : tx_fifo_dout;
	wire [7:0] b_ctrl_in = mode_master ? m_tx_mux : tx_fifo_dout;

	// ---------------------------------------------------------
	// Physical Layer (Open-Drain)
	// ---------------------------------------------------------
	assign scl = (mode_master && busy_m && !scl_gen_out) ? 1'b0 : 1'bz;

	assign sda = ( (startstop_sda_oe && !startstop_sda_out) ||
				   (!startstop_sda_oe && slave_sda_oe && !slave_sda_out) ||
				   (!startstop_sda_oe && !slave_sda_oe && bitctrl_sda_oe && !bitctrl_sda_out) ) ? 1'b0 : 1'bz;

	// ---------------------------------------------------------
	// Submodule Instantiations
	// ---------------------------------------------------------
	sync_fifo #(
		.DEPTH(FIFO_DEPTH),
		.DWIDTH(8)
	) tx_fifo (
		.clk     (clk),
		.resetn  (resetn),
		.wr_ena  (tx_wr_en),
		.rd_ena  (tx_rd_en),
		.din     (tx_wr_data),
		.full    (tx_full),
		.empty   (tx_empty),
		.dout    (tx_fifo_dout)
	);

	sync_fifo #(
		.DEPTH(FIFO_DEPTH),
		.DWIDTH(8)
	) rx_fifo (
		.clk     (clk),
		.resetn  (resetn),
		.wr_ena  (rx_wr_en),
		.rd_ena  (rx_rd_en),
		.din     (rx_data),
		.full    (rx_full),
		.empty   (rx_empty),
		.dout    (rx_rd_data)
	);

	i2c_glitch_filter scl_filter (
		.clk          (clk),
		.resetn       (resetn),
		.raw_in       (scl),
		.filtered_out (scl_filt)
	);

	i2c_glitch_filter sda_filter (
		.clk          (clk),
		.resetn       (resetn),
		.raw_in       (sda),
		.filtered_out (sda_filt)
	);

	i2c_clk_gen clk_gen (
		.clk         (clk),
		.resetn      (resetn),
		.en          (mode_master && busy_m),
		.prescaler   (prescaler),
		.scl_out     (scl_gen_out)
	);

	i2c_start_stop start_stop (
		.clk       (clk),
		.resetn    (resetn),
		.gen_start (gen_start),
		.gen_stop  (gen_stop),
		.scl_in    (scl_filt),
		.sda_in    (sda_filt),
		.sda_out   (startstop_sda_out),
		.sda_oe    (startstop_sda_oe),
		.start_det (start_det),
		.stop_det  (stop_det),
		.done      (start_stop_done)
	);

	i2c_bit_ctrl bit_ctrl (
		.clk         (clk),
		.resetn      (resetn),
		.enable      (enable && bit_ctrl_en),
		.ack_phase   (ack_phase),
		.tx_data     (b_ctrl_in),
		.load        (load_bit_ctrl),
		.rx_data     (rx_data),
		.byte_done   (byte_done),
		.sda_sampled (sda_sampled),
		.sda_oe      (bitctrl_sda_oe),
		.sda_out     (bitctrl_sda_out),
		.scl_in      (scl_filt),
		.sda_in      (sda_filt)
	);

	i2c_master_fsm master_fsm (
		.clk         (clk),
		.resetn      (resetn),
		.start       (mode_master ? start : 1'b0),
		.rw          (rw),
		.slave_addr  (slave_addr),
		.sda_sampled (sda_sampled),
		.tx_empty    (mode_master ? tx_empty : 1'b1),
		.byte_done   (byte_done),
		.start_done  (start_stop_done),
		.stop_done   (start_stop_done),
		.gen_start   (gen_start),
		.gen_stop    (gen_stop),
		.bit_ctrl_en (bit_ctrl_en_m),
		.load        (load_m),
		.tx_rd_en    (tx_rd_en_m),
		.rx_wr_en    (rx_wr_en_m),
		.arb_lost    (arb_lost_m),
		.busy        (busy_m),
		.ack_phase   (ack_phase_m),
		.state_out   (m_state)
	);

	i2c_slave_fsm slave_fsm (
		.clk         (clk),
		.resetn      (resetn),
		.slave_addr  (slave_addr),
		.start_det   (start_det),
		.stop_det    (stop_det),
		.byte_done   (byte_done),
		.sda_sampled (sda_sampled),
		.rx_data     (rx_data),
		.tx_empty    (!mode_master ? tx_empty : 1'b1),
		.bit_ctrl_en (bit_ctrl_en_s),
		.load        (load_s),
		.tx_rd_en    (tx_rd_en_s),
		.rx_wr_en    (rx_wr_en_s),
		.sda_oe      (slave_sda_oe),
		.sda_out     (slave_sda_out),
		.busy        (busy_s),
		.ack_phase   (ack_phase_s)
	);

	i2c_int_ctrl int_ctrl (
		.clk        (clk),
		.resetn     (resetn),
		.byte_done  (byte_done),
		.nack_det   (sda_sampled),
		.start_det  (start_det),
		.stop_det   (stop_det),
		.tx_empty   (tx_empty),
		.tx_full    (tx_full),
		.rx_full    (rx_full),
		.arb_lost   (arb_lost),
		.int_en     (int_en),
		.int_clr    (int_clr),
		.int_status (int_status),
		.irq        (irq)
	);

endmodule