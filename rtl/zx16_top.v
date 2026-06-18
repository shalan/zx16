// zx16_top.v -- core + unified memory + a minimal MMIO device model.
// The device mirrors the Python sim's scripted MMIO for 02_poll_status:
//   0xF020 STATUS: returns 0 for the first two reads, then bit0=1 (READY)
//   0xF021 DATA  : returns 99
// All other addresses (incl. other MMIO like 0xF010/0xF030) are plain RAM, so
// read-modify-write peripherals (GPIO, timer reg-map) behave as the sim expects.
module zx16_top #(
    parameter RESET_PC = 16'h0020
)(
    input         clk,
    input         rst,
    output        halt,
    output        ecall_valid,
    output [9:0]  ecall_svc,
    output [15:0] dbg_a0
);
    wire [15:0] iaddr, idata, daddr, drdata_mem, dwdata;
    wire [7:0]  drbyte_mem;
    wire        dwe, dword, dre;

    // ---- scripted STATUS/DATA device for 02_poll_status ----
    reg  [3:0]  status_reads;
    wire        sel_status = (daddr == 16'hF020);
    wire        sel_data   = (daddr == 16'hF021);
    wire [15:0] status_val = (status_reads >= 4'd2) ? 16'd1 : 16'd0;
    wire [15:0] drdata = sel_status ? status_val :
                         sel_data   ? 16'd99      : drdata_mem;
    wire [7:0]  drbyte = sel_status ? status_val[7:0] :
                         sel_data   ? 8'd99          : drbyte_mem;
    always @(posedge clk) begin
        if (rst)                     status_reads <= 4'd0;
        else if (dre && sel_status)  status_reads <= status_reads + 4'd1;
    end

    zx16_core #(.RESET_PC(RESET_PC)) core(
        .clk(clk), .rst(rst),
        .iaddr(iaddr), .idata(idata),
        .daddr(daddr), .drdata(drdata), .drbyte(drbyte),
        .dwe(dwe), .dword(dword), .dwdata(dwdata), .dre(dre),
        .ecall_valid(ecall_valid), .ecall_svc(ecall_svc),
        .dbg_a0(dbg_a0), .halted(halt)
    );

    zx16_mem mem(
        .clk(clk),
        .iaddr(iaddr), .idata(idata),
        .daddr(daddr), .drdata(drdata_mem), .drbyte(drbyte_mem),
        .mem_we(dwe), .mem_word(dword), .dwdata(dwdata)
    );
endmodule
