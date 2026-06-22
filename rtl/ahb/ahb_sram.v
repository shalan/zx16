// ahb_sram.v -- AHB-Lite slave: word-organized 64KB SRAM ($readmemh-loadable),
// with a runtime-selectable number of wait states (WAITS) to stress the master's
// HREADY handling. When MMIO=1 it also models the scripted peripheral used by
// 02_poll_status: reads of 0xF020 return 0,0,1,... (READY on the 3rd read), 0xF021
// returns 99 (writes to those addresses are ignored). Verilog-2001.
module ahb_sram #(
    parameter MMIO = 0
)(
    input             HCLK,
    input             HRESETn,
    input      [3:0]  WAITS,        // wait states inserted per transfer (0 = zero-wait)
    input      [15:0] HADDR,
    input      [1:0]  HTRANS,
    input             HWRITE,
    input      [2:0]  HSIZE,
    input      [15:0] HWDATA,
    output reg [15:0] HRDATA,
    output            HREADYOUT,
    output            HRESP
);
    reg [15:0] mem [0:32767];
    // address-phase capture (held through the data phase)
    reg        a_valid, a_write;
    reg [15:0] a_addr;
    reg [2:0]  a_size;
    reg [3:0]  wcnt;
    reg [3:0]  status_reads;

    wire ready  = (wcnt == 4'd0);
    wire accept = ready && HTRANS[1];   // NONSEQ/SEQ accepted this cycle
    assign HREADYOUT = ready;
    assign HRESP     = 1'b0;            // always OKAY

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            a_valid<=1'b0; a_write<=1'b0; a_addr<=16'd0; a_size<=3'd0;
            wcnt<=4'd0; status_reads<=4'd0;
        end else begin
            // wait-state countdown for the data phase
            if (accept && WAITS!=4'd0) wcnt <= WAITS;
            else if (wcnt!=4'd0)       wcnt <= wcnt - 4'd1;
            // capture a new address phase only when ready
            if (ready) begin
                a_valid <= HTRANS[1];
                a_write <= HWRITE;
                a_addr  <= HADDR;
                a_size  <= HSIZE;
            end
            // commit a write at data-phase completion (uses the captured address)
            if (ready && a_valid && a_write) begin
                if (MMIO && (a_addr==16'hF020 || a_addr==16'hF021)) begin
                    // device register write: ignore
                end else if (a_size==3'b001) begin
                    mem[a_addr[15:1]] <= HWDATA;
                end else if (a_addr[0]) begin
                    mem[a_addr[15:1]][15:8] <= HWDATA[15:8];
                end else begin
                    mem[a_addr[15:1]][7:0]  <= HWDATA[7:0];
                end
            end
            // scripted STATUS: count completed reads of 0xF020
            if (MMIO && ready && a_valid && !a_write && a_addr==16'hF020)
                status_reads <= status_reads + 4'd1;
        end
    end

    // read data (data phase, combinational from the captured address). MMIO device
    // bytes are placed on the byte lane selected by a_addr[0], per AHB byte lanes.
    wire [7:0] status_b = (status_reads>=4'd2) ? 8'd1 : 8'd0;
    always @(*) begin
        if      (MMIO && a_addr==16'hF020) HRDATA = a_addr[0] ? {status_b,8'b0} : {8'b0,status_b};
        else if (MMIO && a_addr==16'hF021) HRDATA = a_addr[0] ? {8'd99,8'b0}    : {8'b0,8'd99};
        else                               HRDATA = mem[a_addr[15:1]];
    end
endmodule
