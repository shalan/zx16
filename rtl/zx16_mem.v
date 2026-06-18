// zx16_mem.v -- unified 64KB memory, word-organized (matches the assembler's
// `-f mem` image: 32768 little-endian 16-bit words, word index = byte_addr/2).
// Asynchronous (combinational) reads on two ports (fetch + data) make the core
// truly single-cycle; writes are synchronous. Word accesses must be even-aligned
// (the ISA requires it); byte accesses select the high/low byte of a word.
// NOTE: async-read RAM is a simulation/teaching model; FPGA BRAM would differ.
module zx16_mem(
    input             clk,
    input      [15:0] iaddr,    // instruction fetch (byte addr, even)
    output     [15:0] idata,
    input      [15:0] daddr,    // data access (byte addr)
    output     [15:0] drdata,   // word read
    output     [7:0]  drbyte,   // addressed byte
    input             mem_we,
    input             mem_word, // 1 = word store (SW), 0 = byte store (SB)
    input      [15:0] dwdata
);
    reg [15:0] mem [0:32767];
    assign idata  = mem[iaddr[15:1]];
    assign drdata = mem[daddr[15:1]];
    assign drbyte = daddr[0] ? mem[daddr[15:1]][15:8] : mem[daddr[15:1]][7:0];
    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_word)      mem[daddr[15:1]]       <= dwdata;
            else if (daddr[0]) mem[daddr[15:1]][15:8] <= dwdata[7:0];
            else               mem[daddr[15:1]][7:0]  <= dwdata[7:0];
        end
    end
endmodule
