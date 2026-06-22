/*
 * Copyright (c) 2026 nativechips.ai
 * Author: Mohamed Shalan (shalan@nativechips.ai)
 * License: Apache-2.0
 */

`default_nettype none

// -----------------------------------------------------------------------------
// Module: nc_mcu_fabric
// Description: 3x AHB-Lite masters to 3x external AHB-Lite slaves plus an
//              internal AHB-to-APB bridge feeding a 16-slave APB3 splitter.
// -----------------------------------------------------------------------------
module nc_mcu_fabric #(
	parameter W_ADDR  = 32,
	parameter W_DATA  = 32,
	parameter W_PADDR = 16,
	parameter APB1_ENABLE = 1
) (
	input  wire                   clk,
	input  wire                   rst_n,

	// ============================
	// AHB-Lite master ports (3x)
	// ============================
	// Master 0 (CPU imem)
	input  wire [W_ADDR-1:0]      m0_haddr,
	input  wire [1:0]             m0_htrans,
	input  wire                   m0_hwrite,
	input  wire [2:0]             m0_hsize,
	input  wire [2:0]             m0_hburst,
	input  wire [3:0]             m0_hprot,
	input  wire [W_DATA-1:0]      m0_hwdata,
	output wire [W_DATA-1:0]      m0_hrdata,
	output wire                   m0_hready,
	output wire                   m0_hresp,

	// Master 1 (CPU dmem)
	input  wire [W_ADDR-1:0]      m1_haddr,
	input  wire [1:0]             m1_htrans,
	input  wire                   m1_hwrite,
	input  wire [2:0]             m1_hsize,
	input  wire [2:0]             m1_hburst,
	input  wire [3:0]             m1_hprot,
	input  wire [W_DATA-1:0]      m1_hwdata,
	output wire [W_DATA-1:0]      m1_hrdata,
	output wire                   m1_hready,
	output wire                   m1_hresp,

	// Master 2 (DMAC)
	input  wire [W_ADDR-1:0]      m2_haddr,
	input  wire [1:0]             m2_htrans,
	input  wire                   m2_hwrite,
	input  wire [2:0]             m2_hsize,
	input  wire [2:0]             m2_hburst,
	input  wire [3:0]             m2_hprot,
	input  wire [W_DATA-1:0]      m2_hwdata,
	output wire [W_DATA-1:0]      m2_hrdata,
	output wire                   m2_hready,
	output wire                   m2_hresp,

	// ============================
	// AHB-Lite slave ports (3x)
	// ============================
	// Slave 0 @ 0x0000_0000
	output wire [W_ADDR-1:0]      s0_haddr,
	output wire [1:0]             s0_htrans,
	output wire                   s0_hwrite,
	output wire [2:0]             s0_hsize,
	output wire [2:0]             s0_hburst,
	output wire [3:0]             s0_hprot,
	output wire [W_DATA-1:0]      s0_hwdata,
	output wire                   s0_hready,      // HREADY to slave
	input  wire                   s0_hready_resp, // HREADYOUT from slave
	input  wire                   s0_hresp,
	input  wire [W_DATA-1:0]      s0_hrdata,

	// Slave 1 @ 0x0800_0000
	output wire [W_ADDR-1:0]      s1_haddr,
	output wire [1:0]             s1_htrans,
	output wire                   s1_hwrite,
	output wire [2:0]             s1_hsize,
	output wire [2:0]             s1_hburst,
	output wire [3:0]             s1_hprot,
	output wire [W_DATA-1:0]      s1_hwdata,
	output wire                   s1_hready,
	input  wire                   s1_hready_resp,
	input  wire                   s1_hresp,
	input  wire [W_DATA-1:0]      s1_hrdata,

	// Slave 2 @ 0x2000_0000
	output wire [W_ADDR-1:0]      s2_haddr,
	output wire [1:0]             s2_htrans,
	output wire                   s2_hwrite,
	output wire [2:0]             s2_hsize,
	output wire [2:0]             s2_hburst,
	output wire [3:0]             s2_hprot,
	output wire [W_DATA-1:0]      s2_hwdata,
	output wire                   s2_hready,
	input  wire                   s2_hready_resp,
	input  wire                   s2_hresp,
	input  wire [W_DATA-1:0]      s2_hrdata,

	// ============================
	// APB3 slave ports (16x)
	// ============================
	output wire [16*W_PADDR-1:0]  apb_paddr,
	output wire [15:0]            apb_psel,
	output wire [15:0]            apb_penable,
	output wire [15:0]            apb_pwrite,
	output wire [16*W_DATA-1:0]   apb_pwdata,
	input  wire [15:0]            apb_pready,
	input  wire [16*W_DATA-1:0]   apb_prdata,
	input  wire [15:0]            apb_pslverr,

	// ============================
	// APB3 slave ports (16x) - APB1
	// ============================
	output wire [16*W_PADDR-1:0]  apb1_paddr,
	output wire [15:0]            apb1_psel,
	output wire [15:0]            apb1_penable,
	output wire [15:0]            apb1_pwrite,
	output wire [16*W_DATA-1:0]   apb1_pwdata,
	input  wire [15:0]            apb1_pready,
	input  wire [16*W_DATA-1:0]   apb1_prdata,
	input  wire [15:0]            apb1_pslverr
);

	localparam integer N_MASTERS = 3;
	localparam integer N_SLAVES  = APB1_ENABLE ? 5 : 4;

	// Base windows: S0=0x0000_0000, S1=0x0800_0000, S2=0x2000_0000
	// APB0 window: 0x4000_0000-0x4000_FFFF
	// APB1 window: 0x4001_0000-0x4001_FFFF (optional)
	localparam [5*W_ADDR-1:0] XBAR_ADDR_MAP_FULL = {
		32'h4001_0000, // S4: AHB->APB1 bridge
		32'h4000_0000, // S3: AHB->APB0 bridge
		32'h2000_0000, // S2
		32'h0800_0000, // S1
		32'h0000_0000  // S0
	};
	localparam [5*W_ADDR-1:0] XBAR_ADDR_MASK_FULL = {
		32'hFFFF_0000, // APB1: 64 KB
		32'hFFFF_0000, // APB0: 64 KB
		32'hFF00_0000,
		32'hFF00_0000,
		32'hFF00_0000
	};
	localparam [N_SLAVES*W_ADDR-1:0] XBAR_ADDR_MAP =
		XBAR_ADDR_MAP_FULL[N_SLAVES*W_ADDR-1:0];
	localparam [N_SLAVES*W_ADDR-1:0] XBAR_ADDR_MASK =
		XBAR_ADDR_MASK_FULL[N_SLAVES*W_ADDR-1:0];

	// APB 16 slaves, 4 KB each (0x0000..0xFFFF)
	localparam [16*W_PADDR-1:0] APB_ADDR_MAP = {
		16'hF000, 16'hE000, 16'hD000, 16'hC000,
		16'hB000, 16'hA000, 16'h9000, 16'h8000,
		16'h7000, 16'h6000, 16'h5000, 16'h4000,
		16'h3000, 16'h2000, 16'h1000, 16'h0000
	};
	localparam [16*W_PADDR-1:0] APB_ADDR_MASK = {16{16'hF000}};

	// ============================
	// Crossbar wiring
	// ============================
	wire [N_MASTERS-1:0]        x_src_hready;
	wire [N_MASTERS-1:0]        x_src_hresp;
	wire [N_MASTERS-1:0]        x_src_hexokay;
	wire [N_MASTERS*W_ADDR-1:0] x_src_haddr;
	wire [N_MASTERS-1:0]        x_src_hwrite;
	wire [N_MASTERS*2-1:0]      x_src_htrans;
	wire [N_MASTERS*3-1:0]      x_src_hsize;
	wire [N_MASTERS*3-1:0]      x_src_hburst;
	wire [N_MASTERS*4-1:0]      x_src_hprot;
	wire [N_MASTERS*8-1:0]      x_src_hmaster;
	wire [N_MASTERS-1:0]        x_src_hmastlock;
	wire [N_MASTERS-1:0]        x_src_hexcl;
	wire [N_MASTERS*W_DATA-1:0] x_src_hwdata;
	wire [N_MASTERS*W_DATA-1:0] x_src_hrdata;

	wire [N_SLAVES-1:0]         x_dst_hready;
	wire [N_SLAVES-1:0]         x_dst_hready_resp;
	wire [N_SLAVES-1:0]         x_dst_hresp;
	wire [N_SLAVES-1:0]         x_dst_hexokay;
	wire [N_SLAVES*W_ADDR-1:0]  x_dst_haddr;
	wire [N_SLAVES-1:0]         x_dst_hwrite;
	wire [N_SLAVES*2-1:0]       x_dst_htrans;
	wire [N_SLAVES*3-1:0]       x_dst_hsize;
	wire [N_SLAVES*3-1:0]       x_dst_hburst;
	wire [N_SLAVES*4-1:0]       x_dst_hprot;
	wire [N_SLAVES*8-1:0]       x_dst_hmaster;
	wire [N_SLAVES-1:0]         x_dst_hmastlock;
	wire [N_SLAVES-1:0]         x_dst_hexcl;
	wire [N_SLAVES*W_DATA-1:0]  x_dst_hwdata;
	wire [N_SLAVES*W_DATA-1:0]  x_dst_hrdata;

	// Pack masters for crossbar arbitration priority:
	// slot0 (LSB) has highest strict-priority in nc_ahbl_arbiter.
	// Give DMAC highest priority, then CPU dmem, then CPU imem.
	// slot0 = M2 (DMAC), slot1 = M1 (CPU dmem), slot2 = M0 (CPU imem)
	assign x_src_haddr   = {m0_haddr,   m1_haddr,   m2_haddr};
	assign x_src_hwrite  = {m0_hwrite,  m1_hwrite,  m2_hwrite};
	assign x_src_htrans  = {m0_htrans,  m1_htrans,  m2_htrans};
	assign x_src_hsize   = {m0_hsize,   m1_hsize,   m2_hsize};
	assign x_src_hburst  = {m0_hburst,  m1_hburst,  m2_hburst};
	assign x_src_hprot   = {m0_hprot,   m1_hprot,   m2_hprot};
	assign x_src_hwdata  = {m0_hwdata,  m1_hwdata,  m2_hwdata};

	// Tie off full-AHB extras for AHB-Lite masters
	assign x_src_hmaster   = {N_MASTERS{8'h00}};
	assign x_src_hmastlock = {N_MASTERS{1'b0}};
	assign x_src_hexcl     = {N_MASTERS{1'b0}};

	// Responses back to masters (DEADBEEF on error)
	// slot0 -> M2, slot1 -> M1, slot2 -> M0
	assign m2_hready = x_src_hready[0];
	assign m2_hresp  = x_src_hresp[0];
	assign m2_hrdata = x_src_hresp[0] ? 32'hDEAD_BEEF : x_src_hrdata[0*W_DATA +: W_DATA];

	assign m1_hready = x_src_hready[1];
	assign m1_hresp  = x_src_hresp[1];
	assign m1_hrdata = x_src_hresp[1] ? 32'hDEAD_BEEF : x_src_hrdata[1*W_DATA +: W_DATA];

	assign m0_hready = x_src_hready[2];
	assign m0_hresp  = x_src_hresp[2];
	assign m0_hrdata = x_src_hresp[2] ? 32'hDEAD_BEEF : x_src_hrdata[2*W_DATA +: W_DATA];

	// ============================
	// External AHB slaves (3x)
	// ============================
	assign s0_haddr   = x_dst_haddr [0*W_ADDR +: W_ADDR];
	assign s0_htrans  = x_dst_htrans[0*2 +: 2];
	assign s0_hwrite  = x_dst_hwrite[0];
	assign s0_hsize   = x_dst_hsize [0*3 +: 3];
	assign s0_hburst  = x_dst_hburst[0*3 +: 3];
	assign s0_hprot   = x_dst_hprot [0*4 +: 4];
	assign s0_hwdata  = x_dst_hwdata[0*W_DATA +: W_DATA];
	assign s0_hready  = x_dst_hready[0];
	assign x_dst_hready_resp[0] = s0_hready_resp;
	assign x_dst_hresp[0]       = s0_hresp;
	assign x_dst_hrdata[0*W_DATA +: W_DATA] = s0_hrdata;
	assign x_dst_hexokay[0] = 1'b1;

	assign s1_haddr   = x_dst_haddr [1*W_ADDR +: W_ADDR];
	assign s1_htrans  = x_dst_htrans[1*2 +: 2];
	assign s1_hwrite  = x_dst_hwrite[1];
	assign s1_hsize   = x_dst_hsize [1*3 +: 3];
	assign s1_hburst  = x_dst_hburst[1*3 +: 3];
	assign s1_hprot   = x_dst_hprot [1*4 +: 4];
	assign s1_hwdata  = x_dst_hwdata[1*W_DATA +: W_DATA];
	assign s1_hready  = x_dst_hready[1];
	assign x_dst_hready_resp[1] = s1_hready_resp;
	assign x_dst_hresp[1]       = s1_hresp;
	assign x_dst_hrdata[1*W_DATA +: W_DATA] = s1_hrdata;
	assign x_dst_hexokay[1] = 1'b1;

	assign s2_haddr   = x_dst_haddr [2*W_ADDR +: W_ADDR];
	assign s2_htrans  = x_dst_htrans[2*2 +: 2];
	assign s2_hwrite  = x_dst_hwrite[2];
	assign s2_hsize   = x_dst_hsize [2*3 +: 3];
	assign s2_hburst  = x_dst_hburst[2*3 +: 3];
	assign s2_hprot   = x_dst_hprot [2*4 +: 4];
	assign s2_hwdata  = x_dst_hwdata[2*W_DATA +: W_DATA];
	assign s2_hready  = x_dst_hready[2];
	assign x_dst_hready_resp[2] = s2_hready_resp;
	assign x_dst_hresp[2]       = s2_hresp;
	assign x_dst_hrdata[2*W_DATA +: W_DATA] = s2_hrdata;
	assign x_dst_hexokay[2] = 1'b1;

	// ============================
	// Internal AHB->APB bridges
	// ============================
	// APB0
	wire                   apb0_hready;
	wire                   apb0_hready_resp;
	wire                   apb0_hresp;
	wire [W_DATA-1:0]      apb0_hrdata;

	assign apb0_hready = x_dst_hready[3];
	assign x_dst_hready_resp[3] = apb0_hready_resp;
	assign x_dst_hresp[3]       = apb0_hresp;
	assign x_dst_hrdata[3*W_DATA +: W_DATA] = apb0_hrdata;
	assign x_dst_hexokay[3] = 1'b1;

	// APB0 bus between bridge and splitter
	wire [W_PADDR-1:0]    apb0m_paddr;
	wire                  apb0m_psel;
	wire                  apb0m_penable;
	wire                  apb0m_pwrite;
	wire [W_DATA-1:0]     apb0m_pwdata;
	wire                  apb0m_pready;
	wire [W_DATA-1:0]     apb0m_prdata;
	wire                  apb0m_pslverr;

	nc_ahbl_to_apb #(
		.W_HADDR(W_ADDR),
		.W_PADDR(W_PADDR),
		.W_DATA(W_DATA)
	) bridge0 (
		.clk             (clk),
		.rst_n           (rst_n),
		.ahbls_hready     (apb0_hready),
		.ahbls_hready_resp(apb0_hready_resp),
		.ahbls_hresp      (apb0_hresp),
		.ahbls_haddr      (x_dst_haddr [3*W_ADDR +: W_ADDR]),
		.ahbls_hwrite     (x_dst_hwrite[3]),
		.ahbls_htrans     (x_dst_htrans[3*2 +: 2]),
		.ahbls_hsize      (x_dst_hsize [3*3 +: 3]),
		.ahbls_hburst     (x_dst_hburst[3*3 +: 3]),
		.ahbls_hprot      (x_dst_hprot [3*4 +: 4]),
		.ahbls_hmastlock  (x_dst_hmastlock[3]),
		.ahbls_hwdata     (x_dst_hwdata[3*W_DATA +: W_DATA]),
		.ahbls_hrdata     (apb0_hrdata),
		.apbm_paddr       (apb0m_paddr),
		.apbm_psel        (apb0m_psel),
		.apbm_penable     (apb0m_penable),
		.apbm_pwrite      (apb0m_pwrite),
		.apbm_pwdata      (apb0m_pwdata),
		.apbm_pready      (apb0m_pready),
		.apbm_prdata      (apb0m_prdata),
		.apbm_pslverr     (apb0m_pslverr)
	);

	// APB0 splitter (16x)
	nc_apb_splitter #(
		.W_ADDR   (W_PADDR),
		.W_DATA   (W_DATA),
		.N_SLAVES (16),
		.ADDR_MAP (APB_ADDR_MAP),
		.ADDR_MASK(APB_ADDR_MASK)
	) apb0_fabric (
		.apbs_paddr   (apb0m_paddr),
		.apbs_psel    (apb0m_psel),
		.apbs_penable (apb0m_penable),
		.apbs_pwrite  (apb0m_pwrite),
		.apbs_pwdata  (apb0m_pwdata),
		.apbs_pready  (apb0m_pready),
		.apbs_prdata  (apb0m_prdata),
		.apbs_pslverr (apb0m_pslverr),
		.apbm_paddr   (apb_paddr),
		.apbm_psel    (apb_psel),
		.apbm_penable (apb_penable),
		.apbm_pwrite  (apb_pwrite),
		.apbm_pwdata  (apb_pwdata),
		.apbm_pready  (apb_pready),
		.apbm_prdata  (apb_prdata),
		.apbm_pslverr (apb_pslverr)
	);

	// APB1 (optional)
	generate
		if (APB1_ENABLE) begin : gen_apb1
			wire                   apb1_hready;
			wire                   apb1_hready_resp;
			wire                   apb1_hresp;
			wire [W_DATA-1:0]      apb1_hrdata;

			assign apb1_hready = x_dst_hready[4];
			assign x_dst_hready_resp[4] = apb1_hready_resp;
			assign x_dst_hresp[4]       = apb1_hresp;
			assign x_dst_hrdata[4*W_DATA +: W_DATA] = apb1_hrdata;
			assign x_dst_hexokay[4] = 1'b1;

			wire [W_PADDR-1:0]    apb1m_paddr;
			wire                  apb1m_psel;
			wire                  apb1m_penable;
			wire                  apb1m_pwrite;
			wire [W_DATA-1:0]     apb1m_pwdata;
			wire                  apb1m_pready;
			wire [W_DATA-1:0]     apb1m_prdata;
			wire                  apb1m_pslverr;

			nc_ahbl_to_apb #(
				.W_HADDR(W_ADDR),
				.W_PADDR(W_PADDR),
				.W_DATA(W_DATA)
			) bridge1 (
				.clk             (clk),
				.rst_n           (rst_n),
				.ahbls_hready     (apb1_hready),
				.ahbls_hready_resp(apb1_hready_resp),
				.ahbls_hresp      (apb1_hresp),
				.ahbls_haddr      (x_dst_haddr [4*W_ADDR +: W_ADDR]),
				.ahbls_hwrite     (x_dst_hwrite[4]),
				.ahbls_htrans     (x_dst_htrans[4*2 +: 2]),
				.ahbls_hsize      (x_dst_hsize [4*3 +: 3]),
				.ahbls_hburst     (x_dst_hburst[4*3 +: 3]),
				.ahbls_hprot      (x_dst_hprot [4*4 +: 4]),
				.ahbls_hmastlock  (x_dst_hmastlock[4]),
				.ahbls_hwdata     (x_dst_hwdata[4*W_DATA +: W_DATA]),
				.ahbls_hrdata     (apb1_hrdata),
				.apbm_paddr       (apb1m_paddr),
				.apbm_psel        (apb1m_psel),
				.apbm_penable     (apb1m_penable),
				.apbm_pwrite      (apb1m_pwrite),
				.apbm_pwdata      (apb1m_pwdata),
				.apbm_pready      (apb1m_pready),
				.apbm_prdata      (apb1m_prdata),
				.apbm_pslverr     (apb1m_pslverr)
			);

			nc_apb_splitter #(
				.W_ADDR   (W_PADDR),
				.W_DATA   (W_DATA),
				.N_SLAVES (16),
				.ADDR_MAP (APB_ADDR_MAP),
				.ADDR_MASK(APB_ADDR_MASK)
			) apb1_fabric (
				.apbs_paddr   (apb1m_paddr),
				.apbs_psel    (apb1m_psel),
				.apbs_penable (apb1m_penable),
				.apbs_pwrite  (apb1m_pwrite),
				.apbs_pwdata  (apb1m_pwdata),
				.apbs_pready  (apb1m_pready),
				.apbs_prdata  (apb1m_prdata),
				.apbs_pslverr (apb1m_pslverr),
				.apbm_paddr   (apb1_paddr),
				.apbm_psel    (apb1_psel),
				.apbm_penable (apb1_penable),
				.apbm_pwrite  (apb1_pwrite),
				.apbm_pwdata  (apb1_pwdata),
				.apbm_pready  (apb1_pready),
				.apbm_prdata  (apb1_prdata),
				.apbm_pslverr (apb1_pslverr)
			);
		end else begin : gen_apb1_tieoff
			assign apb1_paddr   = {16*W_PADDR{1'b0}};
			assign apb1_psel    = 16'h0000;
			assign apb1_penable = 16'h0000;
			assign apb1_pwrite  = 16'h0000;
			assign apb1_pwdata  = {16*W_DATA{1'b0}};
		end
	endgenerate

	// ============================
	// Crossbar instance
	// ============================
	nc_ahbl_crossbar #(
		.N_MASTERS (N_MASTERS),
		.N_SLAVES  (N_SLAVES),
		.W_ADDR    (W_ADDR),
		.W_DATA    (W_DATA),
		.ADDR_MAP  (XBAR_ADDR_MAP),
		.ADDR_MASK (XBAR_ADDR_MASK)
	) xbar (
		.clk             (clk),
		.rst_n           (rst_n),
		.src_hready_resp (x_src_hready),
		.src_hresp       (x_src_hresp),
		.src_hexokay     (x_src_hexokay),
		.src_haddr       (x_src_haddr),
		.src_hwrite      (x_src_hwrite),
		.src_htrans      (x_src_htrans),
		.src_hsize       (x_src_hsize),
		.src_hburst      (x_src_hburst),
		.src_hprot       (x_src_hprot),
		.src_hmaster     (x_src_hmaster),
		.src_hmastlock   (x_src_hmastlock),
		.src_hexcl       (x_src_hexcl),
		.src_hwdata      (x_src_hwdata),
		.src_hrdata      (x_src_hrdata),
		.dst_hready      (x_dst_hready),
		.dst_hready_resp (x_dst_hready_resp),
		.dst_hresp       (x_dst_hresp),
		.dst_hexokay     (x_dst_hexokay),
		.dst_haddr       (x_dst_haddr),
		.dst_hwrite      (x_dst_hwrite),
		.dst_htrans      (x_dst_htrans),
		.dst_hsize       (x_dst_hsize),
		.dst_hburst      (x_dst_hburst),
		.dst_hprot       (x_dst_hprot),
		.dst_hmaster     (x_dst_hmaster),
		.dst_hmastlock   (x_dst_hmastlock),
		.dst_hexcl       (x_dst_hexcl),
		.dst_hwdata      (x_dst_hwdata),
		.dst_hrdata      (x_dst_hrdata)
	);

endmodule

`default_nettype wire
