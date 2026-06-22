/*
 * Copyright (c) 2026 nativechips.ai
 * Author: Mohamed Shalan (shalan@nativechips.ai)
 * License: Apache-2.0
 */

// NOTE: This file contains modules originally written by Luke Wren.
// -----------------------------------------------------------------------------

`default_nettype none

module nc_onehot_priority #(
	parameter W_INPUT = 8,
	parameter HIGHEST_WINS = 0
) (
	input wire [W_INPUT-1:0] in,
	output reg [W_INPUT-1:0] out
);

integer i;
reg deny;

always @ (*) begin
	deny = 1'b0;
	if (HIGHEST_WINS) begin
		for (i = W_INPUT - 1; i >= 0; i = i - 1) begin
			out[i] = in[i] && !deny;
			deny = deny || in[i];
		end
	end else begin
		for (i = 0; i < W_INPUT; i = i + 1) begin
			out[i] = in[i] && !deny;
			deny = deny || in[i];
		end
	end
end

endmodule

// Author: Luke Wren

// Multiplex based on a bitmap selector, rather than an index selector.
// Generates a fast and->or mux structure rather than a tree of dmuxes.
// The selector must be one-hot, else the result is meaningless.

// -----------------------------------------------------------------------------
// Module: nc_onehot_mux
// Description: One-hot mux for wide buses.
// -----------------------------------------------------------------------------
module nc_onehot_mux #(
	parameter N_INPUTS = 2,
	parameter W_INPUT = 32
) (
	input wire  [N_INPUTS*W_INPUT-1:0] in,
	input wire  [N_INPUTS-1:0]         sel,
	output wire [W_INPUT-1:0]          out
);

integer i;

reg [W_INPUT-1:0] mux_accum;

always @ (*) begin
	mux_accum = {W_INPUT{1'b0}};
	for (i = 0; i < N_INPUTS; i = i + 1) begin
		mux_accum = mux_accum | (in[i * W_INPUT +: W_INPUT] & {W_INPUT{sel[i]}});
	end
end

assign out = mux_accum;

endmodule

// Author: Luke Wren
/*
 * Strict-priority N:1 AHBL arbiter
 *
 * Lower port numbers are higher priority.
 * Use concat lists to wire masters in:
 *   .N_PORTS(2)
 *   ...
 *   .src_haddr({mast1_haddr, mast0_haddr})
 *   ...
 * Recommend that wiring up either be scripted, or done by unpaid intern.
 */

// TODO: no burst support!

`default_nettype none

// -----------------------------------------------------------------------------
// Module: nc_ahbl_arbiter
// Description: AHB-Lite arbiter (N masters to 1 slave).
// -----------------------------------------------------------------------------
module nc_ahbl_arbiter #(
	parameter N_PORTS          = 2,
	parameter W_ADDR           = 32,
	parameter W_DATA           = 32,
	parameter CONN_MASK        = {N_PORTS{1'b1}},
	parameter FAIR_ARBITRATION = 0
) (
	// Global signals
	input wire                       clk,
	input wire                       rst_n,

	// From masters; function as slave ports
	input  wire [N_PORTS-1:0]        src_hready,
	output wire [N_PORTS-1:0]        src_hready_resp,
	output wire [N_PORTS-1:0]        src_hresp,
	output wire [N_PORTS-1:0]        src_hexokay,
	input  wire [N_PORTS*W_ADDR-1:0] src_haddr,
	input  wire [N_PORTS-1:0]        src_hwrite,
	input  wire [N_PORTS*2-1:0]      src_htrans,
	input  wire [N_PORTS*3-1:0]      src_hsize,
	input  wire [N_PORTS*3-1:0]      src_hburst,
	input  wire [N_PORTS*4-1:0]      src_hprot,
	input  wire [N_PORTS*8-1:0]      src_hmaster,
	input  wire [N_PORTS-1:0]        src_hmastlock,
	input  wire [N_PORTS-1:0]        src_hexcl,
	input  wire [N_PORTS*W_DATA-1:0] src_hwdata,
	output wire [N_PORTS*W_DATA-1:0] src_hrdata,

	// To slave; functions as master port
	output wire                      dst_hready,
	input  wire                      dst_hready_resp,
	input  wire                      dst_hresp,
	input  wire                      dst_hexokay,
	output wire [W_ADDR-1:0]         dst_haddr,
	output wire                      dst_hwrite,
	output wire [1:0]                dst_htrans,
	output wire [2:0]                dst_hsize,
	output wire [2:0]                dst_hburst,
	output wire [3:0]                dst_hprot,
	output wire [7:0]                dst_hmaster,
	output wire                      dst_hmastlock,
	output wire                      dst_hexcl,
	output wire [W_DATA-1:0]         dst_hwdata,
	input  wire [W_DATA-1:0]         dst_hrdata
);

integer i;

// "actual" is a mux between the buffered signal, if valid, else the live signal on the port

reg [N_PORTS-1:0]        buf_valid;
reg [W_ADDR-1:0]         buf_haddr      [0:N_PORTS-1];
reg                      buf_hwrite     [0:N_PORTS-1];
reg [1:0]                buf_htrans     [0:N_PORTS-1];
reg [2:0]                buf_hsize      [0:N_PORTS-1];
reg [2:0]                buf_hburst     [0:N_PORTS-1];
reg [3:0]                buf_hprot      [0:N_PORTS-1];
reg [7:0]                buf_hmaster    [0:N_PORTS-1];
reg                      buf_hmastlock  [0:N_PORTS-1];
reg                      buf_hexcl      [0:N_PORTS-1];

reg [N_PORTS*W_ADDR-1:0] actual_haddr;
reg [N_PORTS-1:0]        actual_hwrite;
reg [N_PORTS*2-1:0]      actual_htrans;
reg [N_PORTS*3-1:0]      actual_hsize;
reg [N_PORTS*3-1:0]      actual_hburst;
reg [N_PORTS*4-1:0]      actual_hprot;
reg [N_PORTS*8-1:0]      actual_hmaster;
reg [N_PORTS-1:0]        actual_hmastlock;
reg [N_PORTS-1:0]        actual_hexcl;


always @ (*) begin
	for (i = 0; i < N_PORTS; i = i + 1) begin
		if (buf_valid[i]) begin
			actual_haddr     [i * W_ADDR +: W_ADDR] = buf_haddr     [i];
			actual_hwrite    [i]                    = buf_hwrite    [i];
			actual_htrans    [i * 2 +: 2]           = buf_htrans    [i];
			actual_hsize     [i * 3 +: 3]           = buf_hsize     [i];
			actual_hburst    [i * 3 +: 3]           = buf_hburst    [i];
			actual_hprot     [i * 4 +: 4]           = buf_hprot     [i];
			actual_hmaster   [i * 8 +: 8]           = buf_hmaster   [i];
			actual_hmastlock [i]                    = buf_hmastlock [i];
			actual_hexcl     [i]                    = buf_hexcl     [i];
		end else begin
			actual_haddr     [i * W_ADDR +: W_ADDR] = src_haddr     [i * W_ADDR +: W_ADDR];
			actual_hwrite    [i]                    = src_hwrite    [i];
			actual_htrans    [i * 2 +: 2]           = src_htrans    [i * 2 +: 2];
			actual_hsize     [i * 3 +: 3]           = src_hsize     [i * 3 +: 3];
			actual_hburst    [i * 3 +: 3]           = src_hburst    [i * 3 +: 3];
			actual_hprot     [i * 4 +: 4]           = src_hprot     [i * 4 +: 4];
			actual_hmaster   [i * 8 +: 8]           = src_hmaster   [i * 8 +: 8];
			actual_hmastlock [i]                    = src_hmastlock [i];
			actual_hexcl     [i]                    = src_hexcl     [i];
		end
	end
end

// Address-phase arbitration

reg  [N_PORTS-1:0] mast_req_a;
wire [N_PORTS-1:0] mast_gnt_a;

always @ (*) begin
	for (i = 0; i < N_PORTS; i = i + 1) begin
		// HTRANS == 2'b10, 2'b11 when active
		mast_req_a[i] = actual_htrans[i * 2 + 1] && CONN_MASK[i];
	end
end

generate
if (FAIR_ARBITRATION) begin: fair_priority

	// Give a golden ticket to each request slot for one transfer at a time.
	// If the golden request is present, it's boosted over all others. This
	// has only one useful property: all requests are eventually served.
	reg [N_PORTS-1:0] golden_ticket;
	always @ (posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			golden_ticket <= {{N_PORTS-1{1'b0}}, 1'b1};
		end else if (dst_hready_resp) begin
			golden_ticket <= {golden_ticket[N_PORTS-2:0], golden_ticket[N_PORTS-1]};
		end
	end

	wire [2*N_PORTS-1:0] req_full = {mast_req_a, mast_req_a & golden_ticket};
	wire [2*N_PORTS-1:0] gnt_full;

	nc_onehot_priority #(
		.W_INPUT(2 * N_PORTS)
	) arb_priority (
		.in  (req_full),
		.out (gnt_full)
	);

	assign mast_gnt_a = gnt_full[0 +: N_PORTS] | gnt_full[N_PORTS +: N_PORTS];

end else begin: strict_priority

	nc_onehot_priority #(
		.W_INPUT(N_PORTS)
	) arb_priority (
		.in  (mast_req_a),
		.out (mast_gnt_a)
	);

end
endgenerate

// AHB State Machine

reg [N_PORTS-1:0] mast_gnt_d;
assign dst_hready = mast_gnt_d ? |(src_hready & mast_gnt_d) : 1'b1;

wire [N_PORTS-1:0] mast_aphase_ends = mast_req_a & src_hready;
wire [N_PORTS-1:0] buf_wen = mast_aphase_ends & ~(mast_gnt_a & {N_PORTS{dst_hready}});

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mast_gnt_d <= {N_PORTS{1'b0}};
		for (i = 0; i < N_PORTS; i = i + 1) begin
			buf_valid[i]     <= 1'b0;
			buf_htrans[i]    <= 2'h0;
			buf_haddr[i]     <= {W_ADDR{1'b0}};
			buf_hwrite[i]    <= 1'b0;
			buf_hsize[i]     <= 3'h0;
			buf_hburst[i]    <= 3'h0;
			buf_hprot[i]     <= 4'h0;
			buf_hmaster[i]   <= 8'h0;
			buf_hmastlock[i] <= 1'b0;
			buf_hexcl[i]     <= 1'b0;
		end
	end else begin
		if (dst_hready) begin
			mast_gnt_d <= mast_gnt_a;
			buf_valid <= buf_valid & ~mast_gnt_a;
		end
		for (i = 0; i < N_PORTS; i = i + 1) begin
			if (buf_wen[i]) begin
				buf_valid    [i] <= 1'b1;
				buf_htrans   [i] <= src_htrans   [i * 2 +: 2];
				buf_haddr    [i] <= src_haddr    [i * W_ADDR +: W_ADDR];
				buf_hwrite   [i] <= src_hwrite   [i];
				buf_hsize    [i] <= src_hsize    [i * 3 +: 3];
				buf_hburst   [i] <= src_hburst   [i * 3 +: 3];
				buf_hprot    [i] <= src_hprot    [i * 4 +: 4];
				buf_hmaster  [i] <= src_hmaster  [i * 8 +: 8];
				buf_hmastlock[i] <= src_hmastlock[i];
				buf_hexcl    [i] <= src_hexcl    [i];
			end
		end
	end
end

// Data-phase signal passthrough

// Master being in dphase with arbiter is separate (looser) condition than arbiter
// being in (that master's) dphase with slave (which is indicated by mast_gnt_d)
wire [N_PORTS-1:0] mast_in_dphase = buf_valid | mast_gnt_d;

// There are two reasons to report ready:
// - the master is currently not in data phase with the arbiter (IDLE)
// - the master is in data phase with both arbiter and slave, and slave is ready
assign src_hready_resp = ~mast_in_dphase | (mast_gnt_d & {N_PORTS{dst_hready_resp}});
assign src_hresp = mast_gnt_d & {N_PORTS{dst_hresp}};
assign src_hexokay = mast_gnt_d & {N_PORTS{dst_hexokay}};
assign src_hrdata = {N_PORTS{dst_hrdata}};

nc_onehot_mux #(
	.W_INPUT(W_DATA),
	.N_INPUTS(N_PORTS)
) hwdata_mux (
	.in(src_hwdata),
	.sel(mast_gnt_d),
	.out(dst_hwdata)
);

// Pass through address-phase signals based on grant

nc_onehot_mux #(
	.W_INPUT(W_ADDR),
	.N_INPUTS(N_PORTS)
) mux_haddr (
	.in(actual_haddr),
	.sel(mast_gnt_a),
	.out(dst_haddr)
);

nc_onehot_mux #(
	.W_INPUT(1),
	.N_INPUTS(N_PORTS)
) mux_hwrite (
	.in(actual_hwrite),
	.sel(mast_gnt_a),
	.out(dst_hwrite)
);

nc_onehot_mux #(
	.W_INPUT(2),
	.N_INPUTS(N_PORTS)
) mux_hwtrans (
	.in(actual_htrans),
	.sel(mast_gnt_a),
	.out(dst_htrans)
);

nc_onehot_mux #(
	.W_INPUT(3),
	.N_INPUTS(N_PORTS)
) mux_hsize (
	.in(actual_hsize),
	.sel(mast_gnt_a),
	.out(dst_hsize)
);

nc_onehot_mux #(
	.W_INPUT(3),
	.N_INPUTS(N_PORTS)
) mux_hburst (
	.in(actual_hburst),
	.sel(mast_gnt_a),
	.out(dst_hburst)
);

nc_onehot_mux #(
	.W_INPUT(4),
	.N_INPUTS(N_PORTS)
) mux_hprot (
	.in(actual_hprot),
	.sel(mast_gnt_a),
	.out(dst_hprot)
);

nc_onehot_mux #(
	.W_INPUT(8),
	.N_INPUTS(N_PORTS)
) mux_hmaster (
	.in(actual_hmaster),
	.sel(mast_gnt_a),
	.out(dst_hmaster)
);

nc_onehot_mux #(
	.W_INPUT(1),
	.N_INPUTS(N_PORTS)
) mux_hmastlock (
	.in(actual_hmastlock),
	.sel(mast_gnt_a),
	.out(dst_hmastlock)
);

nc_onehot_mux #(
	.W_INPUT(1),
	.N_INPUTS(N_PORTS)
) mux_hexcl (
	.in(actual_hexcl),
	.sel(mast_gnt_a),
	.out(dst_hexcl)
);

endmodule

// Author: Luke Wren
 /*
  * AHB-lite 1:N splitter
  * If this splitter is at the top of the busfabric (i.e. its master is a true master),
  * tie src_hready_resp across to src_hready.
  *
  * It is up to the system implementer to *ensure that the address mapped ranges
  *  are mutually exclusive*.
  */

// TODO: burst support

`default_nettype none

// -----------------------------------------------------------------------------
// Module: nc_ahbl_splitter
// Description: AHB-Lite address decoder/splitter (1 master to N slaves).
// -----------------------------------------------------------------------------
module nc_ahbl_splitter #(
	parameter N_PORTS = 2,
	parameter W_ADDR = 32,
	parameter W_DATA = 32,
	parameter ADDR_MAP  = 64'h20000000_00000000,
	parameter ADDR_MASK = 64'hf0000000_f0000000,
	parameter CONN_MASK = {N_PORTS{1'b1}}
) (
	// Global signals
	input wire                       clk,
	input wire                       rst_n,

	// From master; functions as slave port
	input  wire                      src_hready,
	output wire                      src_hready_resp,
	output wire                      src_hresp,
	output wire                      src_hexokay,
	input  wire [W_ADDR-1:0]         src_haddr,
	input  wire                      src_hwrite,
	input  wire [1:0]                src_htrans,
	input  wire [2:0]                src_hsize,
	input  wire [2:0]                src_hburst,
	input  wire [3:0]                src_hprot,
	input  wire [7:0]                src_hmaster,
	input  wire                      src_hmastlock,
	input  wire                      src_hexcl,
	input  wire [W_DATA-1:0]         src_hwdata,
	output wire [W_DATA-1:0]         src_hrdata,

	// To slaves; function as master ports
	output wire [N_PORTS-1:0]        dst_hready,
	input  wire [N_PORTS-1:0]        dst_hready_resp,
	input  wire [N_PORTS-1:0]        dst_hresp,
	input  wire [N_PORTS-1:0]        dst_hexokay,
	output wire [N_PORTS*W_ADDR-1:0] dst_haddr,
	output wire [N_PORTS-1:0]        dst_hwrite,
	output reg  [N_PORTS*2-1:0]      dst_htrans,
	output wire [N_PORTS*3-1:0]      dst_hsize,
	output wire [N_PORTS*3-1:0]      dst_hburst,
	output wire [N_PORTS*4-1:0]      dst_hprot,
	output wire [N_PORTS*8-1:0]      dst_hmaster,
	output wire [N_PORTS-1:0]        dst_hmastlock,
	output wire [N_PORTS-1:0]        dst_hexcl,
	output wire [N_PORTS*W_DATA-1:0] dst_hwdata,
	input  wire [N_PORTS*W_DATA-1:0] dst_hrdata
);

localparam HTRANS_IDLE = 2'b00;

integer i;

// Address decode

reg [N_PORTS-1:0] slave_sel_a_nomask;
reg [N_PORTS-1:0] slave_sel_a;
reg decode_err_a;

always @ (*) begin
	if (src_htrans == HTRANS_IDLE) begin
		slave_sel_a_nomask = {N_PORTS{1'b0}};
		slave_sel_a = {N_PORTS{1'b0}};
		decode_err_a = 1'b0;
	end else begin
		for (i = 0; i < N_PORTS; i = i + 1) begin
			slave_sel_a_nomask[i] = !((src_haddr ^ ADDR_MAP[i * W_ADDR +: W_ADDR])
				& ADDR_MASK[i * W_ADDR +: W_ADDR]);
		end
		slave_sel_a = slave_sel_a_nomask & CONN_MASK;
		decode_err_a = !slave_sel_a_nomask;
	end
end

// Address-phase passthrough
// Be lazy and don't blank out signals to non-selected slaves,
// except for HTRANS, which must be gated off to stop spurious transfer.
// Costs transitions, but saves gates.

assign dst_haddr     = {N_PORTS{src_haddr}};
assign dst_hwrite    = {N_PORTS{src_hwrite}};
assign dst_hsize     = {N_PORTS{src_hsize}};
assign dst_hburst    = {N_PORTS{src_hburst}};
assign dst_hprot     = {N_PORTS{src_hprot}};
assign dst_hmaster   = {N_PORTS{src_hmaster}};
assign dst_hmastlock = {N_PORTS{src_hmastlock}};
assign dst_hexcl     = {N_PORTS{src_hexcl}};

always @ (*) begin
	for (i = 0; i < N_PORTS; i = i + 1) begin
		dst_htrans[i * 2 +: 2] = slave_sel_a[i] ? src_htrans : HTRANS_IDLE;
	end 
end

// AHB state machine

reg [N_PORTS-1:0] slave_sel_d;
reg decode_err_d;
reg err_ph1;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		slave_sel_d <= {N_PORTS{1'b0}};
		decode_err_d <= 1'b0;
		err_ph1 <= 1'b0;
	end else begin
		if (src_hready) begin
			slave_sel_d <= slave_sel_a;
			decode_err_d <= decode_err_a;
		end
		if (decode_err_d) begin
			err_ph1 <= !err_ph1;
		end else begin
			err_ph1 <= 1'b0;
		end
	end
end

// Data-phase passthrough

assign dst_hwdata = {N_PORTS{src_hwdata}};
assign dst_hready = {N_PORTS{src_hready}};

nc_onehot_mux #(
	.N_INPUTS(N_PORTS),
	.W_INPUT(W_DATA)
) hrdata_mux (
	.in(dst_hrdata),
	.sel(slave_sel_d),
	.out(src_hrdata)
);

// We want to avoid any combinatorial paths from htrans->hready
// both for timing closure reasons, and to avoid loops with poorly
// behaved masters.
// One rule to avoid this is to *only use data-phase state for muxing*

assign src_hready_resp = (!slave_sel_d && (err_ph1 || !decode_err_d)) ||
	|(slave_sel_d & dst_hready_resp);

assign src_hresp = decode_err_d || |(slave_sel_d & dst_hresp);

assign src_hexokay = |(slave_sel_d & dst_hexokay);

endmodule

// Author: Luke Wren

// Wrapper module to instantiate an M x N crossbar of nc_ahbl_splitter and
// nc_ahbl_arbiter modules

`default_nettype none

// -----------------------------------------------------------------------------
// Module: nc_ahbl_crossbar
// Description: AHB-Lite crossbar (M masters to N slaves).
// -----------------------------------------------------------------------------
module nc_ahbl_crossbar #(
	parameter N_MASTERS = 2,
	parameter N_SLAVES = 3,
	parameter W_ADDR = 32,
	parameter W_DATA = 32,

	parameter ADDR_MAP  = 96'h40000000_20080000_20000000,
	parameter ADDR_MASK = 96'he0000000_e0080000_e0080000,

	// These are redundant, but I couldn't find a convincingly-constant way to
	// slice the matrix in both directions for both splitters and arbiters.
	// Setting CONN_MATRIX only is sufficient to remove connectivity, but
	// setting CONN_MATRIX_TRANSPOSE too will get you the full LUT savings of
	// parameter-based tie-offs.
	parameter CONN_MATRIX = {N_MASTERS{
		{N_SLAVES{1'b1}}
	}},
	parameter CONN_MATRIX_TRANSPOSE = {N_SLAVES{
		{N_MASTERS{1'b1}}
	}}
) (
	// Global signals
	input wire                         clk,
	input wire                         rst_n,

	// From masters; function as slave ports
	output wire [N_MASTERS-1:0]        src_hready_resp,
	output wire [N_MASTERS-1:0]        src_hresp,
	output wire [N_MASTERS-1:0]        src_hexokay,
	input  wire [N_MASTERS*W_ADDR-1:0] src_haddr,
	input  wire [N_MASTERS-1:0]        src_hwrite,
	input  wire [N_MASTERS*2-1:0]      src_htrans,
	input  wire [N_MASTERS*3-1:0]      src_hsize,
	input  wire [N_MASTERS*3-1:0]      src_hburst,
	input  wire [N_MASTERS*4-1:0]      src_hprot,
	input  wire [N_MASTERS*8-1:0]      src_hmaster,
	input  wire [N_MASTERS-1:0]        src_hmastlock,
	input  wire [N_MASTERS-1:0]        src_hexcl,
	input  wire [N_MASTERS*W_DATA-1:0] src_hwdata,
	output wire [N_MASTERS*W_DATA-1:0] src_hrdata,

	// To slaves; function as master ports
	output wire [N_SLAVES-1:0]         dst_hready,
	input  wire [N_SLAVES-1:0]         dst_hready_resp,
	input  wire [N_SLAVES-1:0]         dst_hresp,
	input  wire [N_SLAVES-1:0]         dst_hexokay,
	output wire [N_SLAVES*W_ADDR-1:0]  dst_haddr,
	output wire [N_SLAVES-1:0]         dst_hwrite,
	output wire [N_SLAVES*2-1:0]       dst_htrans,
	output wire [N_SLAVES*3-1:0]       dst_hsize,
	output wire [N_SLAVES*3-1:0]       dst_hburst,
	output wire [N_SLAVES*4-1:0]       dst_hprot,
	output wire [N_SLAVES*8-1:0]       dst_hmaster,
	output wire [N_SLAVES-1:0]         dst_hmastlock,
	output wire [N_SLAVES-1:0]         dst_hexcl,
	output wire [N_SLAVES*W_DATA-1:0]  dst_hwdata,
	input  wire [N_SLAVES*W_DATA-1:0]  dst_hrdata
);


// ================================================
// Instance interconnect for splitters <-> arbiters
// ================================================

wire              xbar_hready      [0:N_MASTERS-1][0:N_SLAVES-1];
wire              xbar_hready_resp [0:N_MASTERS-1][0:N_SLAVES-1];
wire              xbar_hresp       [0:N_MASTERS-1][0:N_SLAVES-1];
wire              xbar_hexokay     [0:N_MASTERS-1][0:N_SLAVES-1];
wire [W_ADDR-1:0] xbar_haddr       [0:N_MASTERS-1][0:N_SLAVES-1];
wire              xbar_hwrite      [0:N_MASTERS-1][0:N_SLAVES-1];
wire [1:0]        xbar_htrans      [0:N_MASTERS-1][0:N_SLAVES-1];
wire [2:0]        xbar_hsize       [0:N_MASTERS-1][0:N_SLAVES-1];
wire [2:0]        xbar_hburst      [0:N_MASTERS-1][0:N_SLAVES-1];
wire [3:0]        xbar_hprot       [0:N_MASTERS-1][0:N_SLAVES-1];
wire [7:0]        xbar_hmaster     [0:N_MASTERS-1][0:N_SLAVES-1];
wire              xbar_hmastlock   [0:N_MASTERS-1][0:N_SLAVES-1];
wire              xbar_hexcl       [0:N_MASTERS-1][0:N_SLAVES-1];
wire [W_DATA-1:0] xbar_hwdata      [0:N_MASTERS-1][0:N_SLAVES-1];
wire [W_DATA-1:0] xbar_hrdata      [0:N_MASTERS-1][0:N_SLAVES-1];

genvar i, j;

// =======================
// Splitter instantiations
// =======================

generate
for (i = 0; i < N_MASTERS; i = i + 1) begin: split_instantiate
	// If I ever meet the person who decided Verilog can't have arrays as module parameters,
	// I'm gonna make a speed bump out of them
	wire [N_SLAVES-1:0]         split_hready;
	wire [N_SLAVES-1:0]         split_hready_resp;
	wire [N_SLAVES-1:0]         split_hresp;
	wire [N_SLAVES-1:0]         split_hexokay;
	wire [N_SLAVES*W_ADDR-1:0]  split_haddr;
	wire [N_SLAVES-1:0]         split_hwrite;
	wire [N_SLAVES*2-1:0]       split_htrans;
	wire [N_SLAVES*3-1:0]       split_hsize;
	wire [N_SLAVES*3-1:0]       split_hburst;
	wire [N_SLAVES*4-1:0]       split_hprot;
	wire [N_SLAVES*8-1:0]       split_hmaster;
	wire [N_SLAVES-1:0]         split_hmastlock;
	wire [N_SLAVES-1:0]         split_hexcl;
	wire [N_SLAVES*W_DATA-1:0]  split_hwdata;
	wire [N_SLAVES*W_DATA-1:0]  split_hrdata;

	for (j = 0; j < N_SLAVES; j = j + 1) begin: split_connect
		if (CONN_MATRIX[i * N_SLAVES + j] && CONN_MATRIX_TRANSPOSE[j * N_MASTERS + i]) begin
			assign xbar_hready[i][j]                  = split_hready[j];
			assign xbar_haddr[i][j]                   = split_haddr[W_ADDR * j +: W_ADDR];
			assign xbar_hwrite[i][j]                  = split_hwrite[j];
			assign xbar_htrans[i][j]                  = split_htrans[2 * j +: 2];
			assign xbar_hsize[i][j]                   = split_hsize[3 * j +: 3];
			assign xbar_hburst[i][j]                  = split_hburst[3 * j +: 3];
			assign xbar_hprot[i][j]                   = split_hprot[4 * j +: 4];
			assign xbar_hmaster[i][j]                 = split_hmaster[8 * j +: 8];
			assign xbar_hmastlock[i][j]               = split_hmastlock[j];
			assign xbar_hexcl[i][j]                   = split_hexcl[j];
			assign xbar_hwdata[i][j]                  = split_hwdata[W_DATA * j +: W_DATA];

			assign split_hready_resp[j]               = xbar_hready_resp[i][j];
			assign split_hresp[j]                     = xbar_hresp[i][j];
			assign split_hexokay[j]                   = xbar_hexokay[i][j];
			assign split_hrdata[W_DATA * j +: W_DATA] = xbar_hrdata[i][j];
		end else begin
			// Disconnected
			assign xbar_hready[i][j]                  = 1'b1;
			assign xbar_haddr[i][j]                   = {W_ADDR{1'b0}};
			assign xbar_hwrite[i][j]                  = 1'b0;
			assign xbar_htrans[i][j]                  = 2'h0;
			assign xbar_hsize[i][j]                   = 3'h0;
			assign xbar_hburst[i][j]                  = 3'h0;
			assign xbar_hprot[i][j]                   = 4'h0;
			assign xbar_hmaster[i][j]                 = 8'h0;
			assign xbar_hmastlock[i][j]               = 1'b0;
			assign xbar_hexcl[i][j]                   = 1'b0;
			assign xbar_hwdata[i][j]                  = {W_DATA{1'b0}};

			assign split_hready_resp[j]               = 1'b1;
			assign split_hresp[j]                     = 1'b1;
			assign split_hexokay[j]                   = 1'b0;
			assign split_hrdata[W_DATA * j +: W_DATA] = {W_DATA{1'b0}};
		end
	end

	nc_ahbl_splitter #(
		.N_PORTS(N_SLAVES),
		.W_ADDR(W_ADDR),
		.W_DATA(W_DATA),
		.ADDR_MAP  (ADDR_MAP),
		.ADDR_MASK (ADDR_MASK),
		.CONN_MASK (CONN_MATRIX[i * N_SLAVES +: N_SLAVES])
	) split (
		.clk             (clk),
		.rst_n           (rst_n),
		.src_hready      (src_hready_resp[i]),	// HREADY_RESP tied -> HREADY at master level
		.src_hready_resp (src_hready_resp[i]),
		.src_hresp       (src_hresp[i]),
		.src_hexokay     (src_hexokay[i]),
		.src_haddr       (src_haddr[W_ADDR * i +: W_ADDR]),
		.src_hwrite      (src_hwrite[i]),
		.src_htrans      (src_htrans[2 * i +: 2]),
		.src_hsize       (src_hsize[3 * i +: 3]),
		.src_hburst      (src_hburst[3 * i +: 3]),
		.src_hprot       (src_hprot[4 * i +: 4]),
		.src_hmaster     (src_hmaster[8 * i +: 8]),
		.src_hmastlock   (src_hmastlock[i]),
		.src_hexcl       (src_hexcl[i]),
		.src_hwdata      (src_hwdata[W_DATA * i +: W_DATA]),
		.src_hrdata      (src_hrdata[W_DATA * i +: W_DATA]),
		.dst_hready      (split_hready),
		.dst_hready_resp (split_hready_resp),
		.dst_hresp       (split_hresp),
		.dst_hexokay     (split_hexokay),
		.dst_haddr       (split_haddr),
		.dst_hwrite      (split_hwrite),
		.dst_htrans      (split_htrans),
		.dst_hsize       (split_hsize),
		.dst_hburst      (split_hburst),
		.dst_hprot       (split_hprot),
		.dst_hmaster     (split_hmaster),
		.dst_hmastlock   (split_hmastlock),
		.dst_hexcl       (split_hexcl),
		.dst_hwdata      (split_hwdata),
		.dst_hrdata      (split_hrdata)
	);
end
endgenerate

// ======================
// Arbiter instantiations
// ======================

generate
for (j = 0; j < N_SLAVES; j = j + 1) begin: arb_instantiate
	wire [N_MASTERS-1:0]         arb_hready;
	wire [N_MASTERS-1:0]         arb_hready_resp;
	wire [N_MASTERS-1:0]         arb_hresp;
	wire [N_MASTERS-1:0]         arb_hexokay;
	wire [N_MASTERS*W_ADDR-1:0]  arb_haddr;
	wire [N_MASTERS-1:0]         arb_hwrite;
	wire [N_MASTERS*2-1:0]       arb_htrans;
	wire [N_MASTERS*3-1:0]       arb_hsize;
	wire [N_MASTERS*3-1:0]       arb_hburst;
	wire [N_MASTERS*4-1:0]       arb_hprot;
	wire [N_MASTERS*8-1:0]       arb_hmaster;
	wire [N_MASTERS-1:0]         arb_hmastlock;
	wire [N_MASTERS-1:0]         arb_hexcl;
	wire [N_MASTERS*W_DATA-1:0]  arb_hwdata;
	wire [N_MASTERS*W_DATA-1:0]  arb_hrdata;

	for (i = 0; i < N_MASTERS; i = i + 1) begin: arb_connect
		assign arb_hready[i]                    = xbar_hready[i][j];
		assign arb_haddr[W_ADDR * i +: W_ADDR]  = xbar_haddr[i][j];
		assign arb_hwrite[i]                    = xbar_hwrite[i][j];
		assign arb_htrans[2 * i +: 2]           = xbar_htrans[i][j];
		assign arb_hsize[3 * i +: 3]            = xbar_hsize[i][j];
		assign arb_hburst[3 * i +: 3]           = xbar_hburst[i][j];
		assign arb_hprot[4 * i +: 4]            = xbar_hprot[i][j];
		assign arb_hmaster[8 * i +: 8]          = xbar_hmaster[i][j];
		assign arb_hmastlock[i]                 = xbar_hmastlock[i][j];
		assign arb_hexcl[i]                     = xbar_hexcl[i][j];
		assign arb_hwdata[W_DATA * i +: W_DATA] = xbar_hwdata[i][j];
		assign xbar_hready_resp[i][j]           = arb_hready_resp[i];
		assign xbar_hresp[i][j]                 = arb_hresp[i];
		assign xbar_hexokay[i][j]               = arb_hexokay[i];
		assign xbar_hrdata[i][j]                = arb_hrdata[W_DATA * i +: W_DATA];
	end

	nc_ahbl_arbiter #(
		.N_PORTS   (N_MASTERS),
		.W_ADDR    (W_ADDR),
		.W_DATA    (W_DATA),
		.CONN_MASK (CONN_MATRIX_TRANSPOSE[j * N_MASTERS +: N_MASTERS])
	) arb (
		.clk             (clk),
		.rst_n           (rst_n),
		.src_hready      (arb_hready),
		.src_hready_resp (arb_hready_resp),
		.src_hresp       (arb_hresp),
		.src_hexokay     (arb_hexokay),
		.src_haddr       (arb_haddr),
		.src_hwrite      (arb_hwrite),
		.src_htrans      (arb_htrans),
		.src_hsize       (arb_hsize),
		.src_hburst      (arb_hburst),
		.src_hprot       (arb_hprot),
		.src_hmaster     (arb_hmaster),
		.src_hmastlock   (arb_hmastlock),
		.src_hexcl       (arb_hexcl),
		.src_hwdata      (arb_hwdata),
		.src_hrdata      (arb_hrdata),
		.dst_hready      (dst_hready[j]),
		.dst_hready_resp (dst_hready_resp[j]),
		.dst_hresp       (dst_hresp[j]),
		.dst_hexokay     (dst_hexokay[j]),
		.dst_haddr       (dst_haddr[W_ADDR * j +: W_ADDR]),
		.dst_hwrite      (dst_hwrite[j]),
		.dst_htrans      (dst_htrans[2 * j +: 2]),
		.dst_hsize       (dst_hsize[3 * j +: 3]),
		.dst_hburst      (dst_hburst[3 * j +: 3]),
		.dst_hprot       (dst_hprot[4 * j +: 4]),
		.dst_hmaster     (dst_hmaster[8 * j +: 8]),
		.dst_hmastlock   (dst_hmastlock[j]),
		.dst_hexcl       (dst_hexcl[j]),
		.dst_hwdata      (dst_hwdata[W_DATA * j +: W_DATA]),
		.dst_hrdata      (dst_hrdata[W_DATA * j +: W_DATA])
	);
end
endgenerate

endmodule

// -----------------------------------------------------------------------------
// Module: nc_ahbl_to_apb
// Description: AHB-Lite to APB3 bridge.
// -----------------------------------------------------------------------------
module nc_ahbl_to_apb #(
	parameter W_HADDR = 32,
	parameter W_PADDR = 16,
	parameter W_DATA = 32
) (
	input wire clk,
	input wire rst_n,

	input  wire               ahbls_hready,
	output wire               ahbls_hready_resp,
	output wire               ahbls_hresp,
	input  wire [W_HADDR-1:0] ahbls_haddr,
	input  wire               ahbls_hwrite,
	input  wire [1:0]         ahbls_htrans,
	input  wire [2:0]         ahbls_hsize,
	input  wire [2:0]         ahbls_hburst,
	input  wire [3:0]         ahbls_hprot,
	input  wire               ahbls_hmastlock,
	input  wire [W_DATA-1:0]  ahbls_hwdata,
	output reg  [W_DATA-1:0]  ahbls_hrdata,

	output reg  [W_PADDR-1:0] apbm_paddr,
	output reg                apbm_psel,
	output reg                apbm_penable,
	output reg                apbm_pwrite,
	output reg  [W_DATA-1:0]  apbm_pwdata,
	input wire                apbm_pready,
	input wire  [W_DATA-1:0]  apbm_prdata,
	input wire                apbm_pslverr 
);

// Transfer state machine

localparam W_APB_STATE = 4;
localparam S_IDLE  = 4'd0; // Idle upstream dataphase
localparam S_RD0   = 4'd1; // Downstream setup phase (cannot stall)
localparam S_RD1   = 4'd2; // Downstream access phase (may stall or error)
localparam S_RD2   = 4'd3; // Return data, capture next address phase
localparam S_WR0   = 4'd4; // Sample hwdata
localparam S_WR1   = 4'd5; // Downstream setup phase (cannot stall)
localparam S_WR2   = 4'd6; // Downstream access phase (may stall or error)
localparam S_WR3   = 4'd7; // Report success, capture next address phase
localparam S_ERR0  = 4'd8; // AHBL error response, first cycle
localparam S_ERR1  = 4'd9; // AHBL error response, and accept new address phase if not deasserted.

reg [W_APB_STATE-1:0] apb_state;

wire [W_APB_STATE-1:0] aphase_to_dphase =
	ahbls_htrans[1] &&  ahbls_hwrite ? S_WR0 :
	ahbls_htrans[1] && !ahbls_hwrite ? S_RD0 : S_IDLE;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		apb_state <= S_IDLE;
	end else case (apb_state)
		S_IDLE: if (ahbls_hready) apb_state <= aphase_to_dphase;
		S_WR0:                    apb_state <= S_WR1;
		S_WR1:                    apb_state <= S_WR2;
		S_WR2:  if (apbm_pready)  apb_state <= apbm_pslverr ? S_ERR0 : S_WR3;
		S_WR3:                    apb_state <= aphase_to_dphase;
		S_RD0:                    apb_state <= S_RD1;
		S_RD1:  if (apbm_pready)  apb_state <= apbm_pslverr ? S_ERR0 : S_RD2;
		S_RD2:                    apb_state <= aphase_to_dphase;
		S_ERR0:                   apb_state <= S_ERR1;
		S_ERR1:                   apb_state <= aphase_to_dphase;
	endcase
end

// Downstream request

always @ (*) begin
	case (apb_state)
		S_RD0:   {apbm_psel, apbm_penable, apbm_pwrite} = 3'b100;
		S_RD1:   {apbm_psel, apbm_penable, apbm_pwrite} = 3'b110;
		S_WR1:   {apbm_psel, apbm_penable, apbm_pwrite} = 3'b101;
		S_WR2:   {apbm_psel, apbm_penable, apbm_pwrite} = 3'b111;
		default: {apbm_psel, apbm_penable, apbm_pwrite} = 3'b000;
	endcase
end

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		apbm_paddr <= {W_PADDR{1'b0}};
		apbm_pwdata <= {W_DATA{1'b0}};
	end else begin
		if (ahbls_htrans[1] && ahbls_hready)
			apbm_paddr <= ahbls_haddr[W_PADDR-1:0];
		if (apb_state == S_WR0)
			apbm_pwdata <= ahbls_hwdata;
	end
end

// Upstream response

assign ahbls_hready_resp =
	apb_state == S_IDLE ||
	apb_state == S_RD2  ||
	apb_state == S_WR3  ||
	apb_state == S_ERR1;

assign ahbls_hresp =
	apb_state == S_ERR0 ||
	apb_state == S_ERR1;

always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		ahbls_hrdata <= {W_DATA{1'b0}};
	else if (apb_state == S_RD1 && apbm_pready)
		ahbls_hrdata <= apbm_prdata;

endmodule

// -----------------------------------------------------------------------------
// Module: nc_apb_splitter
// Description: APB address decoder/splitter (1 master to N slaves).
// -----------------------------------------------------------------------------
module nc_apb_splitter #(
	parameter W_ADDR = 16,
	parameter W_DATA = 32,
	parameter N_SLAVES = 2,
	parameter ADDR_MAP =  32'h0000_4000,
	parameter ADDR_MASK = 32'hc000_c000
) (
	input wire  [W_ADDR-1:0]          apbs_paddr,
	input wire                        apbs_psel,
	input wire                        apbs_penable,
	input wire                        apbs_pwrite,
	input wire  [W_DATA-1:0]          apbs_pwdata,
	output wire                       apbs_pready,
	output wire [W_DATA-1:0]          apbs_prdata,
	output wire                       apbs_pslverr,

	output wire [N_SLAVES*W_ADDR-1:0] apbm_paddr,
	output wire [N_SLAVES-1:0]        apbm_psel,
	output wire [N_SLAVES-1:0]        apbm_penable,
	output wire [N_SLAVES-1:0]        apbm_pwrite,
	output wire [N_SLAVES*W_DATA-1:0] apbm_pwdata,
	input wire  [N_SLAVES-1:0]        apbm_pready,
	input wire  [N_SLAVES*W_DATA-1:0] apbm_prdata,
	input wire  [N_SLAVES-1:0]        apbm_pslverr 
);

integer i;

reg [N_SLAVES-1:0] slave_mask;

always @ (*) begin
	for (i = 0; i < N_SLAVES; i = i + 1) begin
		slave_mask[i] = (apbs_paddr & ADDR_MASK[i * W_ADDR +: W_ADDR])
			== ADDR_MAP[i * W_ADDR +: W_ADDR];
	end
end

assign apbs_pready = !slave_mask || slave_mask & apbm_pready;
assign apbs_pslverr = !slave_mask || slave_mask & apbm_pslverr;

assign apbm_paddr = {N_SLAVES{apbs_paddr}};
assign apbm_psel = slave_mask & {N_SLAVES{apbs_psel}};
assign apbm_penable = slave_mask & {N_SLAVES{apbs_penable}};
assign apbm_pwrite = slave_mask & {N_SLAVES{apbs_pwrite}};
assign apbm_pwdata = {N_SLAVES{apbs_pwdata}};

nc_onehot_mux #(
	.N_INPUTS(N_SLAVES),
	.W_INPUT(W_DATA)
) prdata_mux (
	.in(apbm_prdata),
	.sel(slave_mask),
	.out(apbs_prdata)
);

endmodule

`default_nettype wire
