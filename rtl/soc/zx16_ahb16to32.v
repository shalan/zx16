`default_nettype none
//============================================================================
// zx16_ahb16to32 -- width/address adapter: one 16-bit ZX16 AHB-Lite master
// to one 32-bit AMBA fabric master port (nc_mcu_fabric mX_*).
//
// Address map ("small high window"):
//   ZX16 0x0000-0xBFFF  -> 0x0000_0000 + addr           (fabric S0 = on-chip RAM)
//   ZX16 0xC000-0xFFFF  -> 0x4000_0000 | addr[13:0]     (APB peripheral window:
//                          UART @0xC000->0x4000_0000, timer @0xD000->0x4000_1000)
//
// Data: a 16-bit write is placed on the 32-bit halfword lane selected by addr[1]
// (registered into the data phase), with the other half zeroed -- so a 16-bit store
// to a 32-bit APB register writes only its low half (replicating both halves would
// corrupt 32-bit registers such as the timer's ARR). A read selects the halfword by
// the same registered addr[1]. The 32-bit slave's HSIZE/HADDR byte enables pick the
// bytes that actually update in RAM.
//============================================================================
module zx16_ahb16to32 (
    input  wire        HCLK,
    input  wire        HRESETn,
    // 16-bit master side (ZX16 core master)
    input  wire [15:0] m_haddr,
    input  wire [1:0]  m_htrans,
    input  wire        m_hwrite,
    input  wire [2:0]  m_hsize,
    input  wire [2:0]  m_hburst,
    input  wire [3:0]  m_hprot,
    input  wire [15:0] m_hwdata,
    output wire [15:0] m_hrdata,
    output wire        m_hready,
    output wire        m_hresp,
    // 32-bit fabric side (nc_mcu_fabric master port)
    output wire [31:0] f_haddr,
    output wire [1:0]  f_htrans,
    output wire        f_hwrite,
    output wire [2:0]  f_hsize,
    output wire [2:0]  f_hburst,
    output wire [3:0]  f_hprot,
    output wire [31:0] f_hwdata,
    input  wire [31:0] f_hrdata,
    input  wire        f_hready,
    input  wire        f_hresp
);
    wire is_periph = (m_haddr[15:14] == 2'b11);            // 0xC000-0xFFFF
    assign f_haddr  = is_periph ? (32'h4000_0000 | {18'b0, m_haddr[13:0]})
                                : {16'h0000, m_haddr};
    assign f_htrans = m_htrans;
    assign f_hwrite = m_hwrite;
    assign f_hsize  = m_hsize;
    assign f_hburst = m_hburst;
    assign f_hprot  = m_hprot;

    assign m_hready = f_hready;
    assign m_hresp  = f_hresp;

    // Track addr[1] of the access whose data is on f_hrdata this cycle: the address
    // phase advances whenever HREADY is high, so capture addr[1] on every ready cycle.
    reg addr1_q;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)      addr1_q <= 1'b0;
        else if (f_hready) addr1_q <= m_haddr[1];
    end
    assign f_hwdata = addr1_q ? {m_hwdata, 16'h0000} : {16'h0000, m_hwdata};
    assign m_hrdata = addr1_q ? f_hrdata[31:16] : f_hrdata[15:0];
endmodule
`default_nettype wire
