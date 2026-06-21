`default_nettype none
//============================================================================
// zx16_ahb32_sram -- behavioral 32-bit AHB-Lite SRAM slave, zero wait states,
// byte-write enables from HSIZE/HADDR. Loadable via $readmemh(+memh=<file>).
// Selection is by HTRANS (the fabric crossbar sends IDLE to unselected slaves),
// so no HSEL is needed. Used as the ZX16 SoC on-chip RAM at fabric S0.
//============================================================================
module zx16_ahb32_sram #(
    parameter integer AW = 16                 // byte-address width (64 KB)
) (
    input  wire        HCLK,
    input  wire        HRESETn,
    input  wire [31:0] HADDR,
    input  wire [1:0]  HTRANS,
    input  wire        HWRITE,
    input  wire [2:0]  HSIZE,
    input  wire [2:0]  HBURST,
    input  wire [3:0]  HPROT,
    input  wire [31:0] HWDATA,
    input  wire        HREADY,                // HREADY in (from fabric)
    output wire        HREADYOUT,
    output wire        HRESP,
    output wire [31:0] HRDATA
);
    localparam integer WORDS = (1 << (AW-2));
    reg [31:0] mem [0:WORDS-1];

    // Address-phase capture (accept when bus ready and transfer is NONSEQ/SEQ).
    reg            a_valid, a_write;
    reg [AW-3:0]   a_word;
    reg [1:0]      a_byte;
    reg [2:0]      a_size;
    wire           accept = HREADY & HTRANS[1];
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin a_valid <= 1'b0; a_write <= 1'b0; end
        else begin
            a_valid <= accept;
            a_write <= accept & HWRITE;
            a_word  <= HADDR[AW-1:2];
            a_byte  <= HADDR[1:0];
            a_size  <= HSIZE;
        end
    end

    // Byte write-enables for the data phase, from the captured size/offset.
    reg [3:0] wen;
    always @(*) begin
        wen = 4'b0000;
        if (a_valid & a_write) begin
            case (a_size)
                3'b000:  wen = 4'b0001 << a_byte;                // byte
                3'b001:  wen = a_byte[1] ? 4'b1100 : 4'b0011;    // halfword
                default: wen = 4'b1111;                          // word
            endcase
        end
    end
    always @(posedge HCLK) begin
        if (wen[0]) mem[a_word][7:0]   <= HWDATA[7:0];
        if (wen[1]) mem[a_word][15:8]  <= HWDATA[15:8];
        if (wen[2]) mem[a_word][23:16] <= HWDATA[23:16];
        if (wen[3]) mem[a_word][31:24] <= HWDATA[31:24];
    end

    assign HRDATA    = mem[a_word];
    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0;

    integer i;
    reg [1023:0] memh;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0;
        if ($value$plusargs("memh=%s", memh)) $readmemh(memh, mem);
    end
endmodule
`default_nettype wire
