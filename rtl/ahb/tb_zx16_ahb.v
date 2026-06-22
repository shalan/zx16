// tb_zx16_ahb.v -- SoC testbench: the AHB-Lite core + two AHB-Lite SRAM slaves
// (instruction bus + data bus). Loads the same $readmemh image into both, emulates
// the ECALL print/halt services, and supports wait-state injection via +ws=<n>.
// Output is machine-parseable for rtl/ahb/verify_ahb.py.
module tb_zx16_ahb;
    reg  HCLK = 1'b0;
    reg  HRESETn = 1'b0;
    reg  [3:0] WAITS;

    wire [15:0] I_HADDR, I_HWDATA, I_HRDATA;
    wire [1:0]  I_HTRANS;  wire I_HWRITE;  wire [2:0] I_HSIZE, I_HBURST;
    wire [3:0]  I_HPROT;   wire I_HREADY, I_HRESP;

    wire [15:0] D_HADDR, D_HWDATA, D_HRDATA;
    wire [1:0]  D_HTRANS;  wire D_HWRITE;  wire [2:0] D_HSIZE, D_HBURST;
    wire [3:0]  D_HPROT;   wire D_HREADY, D_HRESP;

    wire halt, ecall_valid;  wire [9:0] ecall_svc;  wire [15:0] dbg_a0;

    zx16_core_ahb cpu(
        .HCLK(HCLK), .HRESETn(HRESETn),
        .irq_req(1'b0), .irq_num(4'd0),       // no interrupts in the standalone core TB
        .I_HADDR(I_HADDR), .I_HTRANS(I_HTRANS), .I_HWRITE(I_HWRITE), .I_HSIZE(I_HSIZE),
        .I_HBURST(I_HBURST), .I_HPROT(I_HPROT), .I_HWDATA(I_HWDATA),
        .I_HRDATA(I_HRDATA), .I_HREADY(I_HREADY), .I_HRESP(I_HRESP),
        .D_HADDR(D_HADDR), .D_HTRANS(D_HTRANS), .D_HWRITE(D_HWRITE), .D_HSIZE(D_HSIZE),
        .D_HBURST(D_HBURST), .D_HPROT(D_HPROT), .D_HWDATA(D_HWDATA),
        .D_HRDATA(D_HRDATA), .D_HREADY(D_HREADY), .D_HRESP(D_HRESP),
        .ecall_valid(ecall_valid), .ecall_svc(ecall_svc), .dbg_a0(dbg_a0), .halted(halt));

    ahb_sram #(.MMIO(0)) imem(
        .HCLK(HCLK), .HRESETn(HRESETn), .WAITS(WAITS),
        .HADDR(I_HADDR), .HTRANS(I_HTRANS), .HWRITE(I_HWRITE), .HSIZE(I_HSIZE),
        .HWDATA(I_HWDATA), .HRDATA(I_HRDATA), .HREADYOUT(I_HREADY), .HRESP(I_HRESP));

    ahb_sram #(.MMIO(1)) dmem(
        .HCLK(HCLK), .HRESETn(HRESETn), .WAITS(WAITS),
        .HADDR(D_HADDR), .HTRANS(D_HTRANS), .HWRITE(D_HWRITE), .HSIZE(D_HSIZE),
        .HWDATA(D_HWDATA), .HRDATA(D_HRDATA), .HREADYOUT(D_HREADY), .HRESP(D_HRESP));

    always #5 HCLK = ~HCLK;

    reg [1023:0] memfile;
    integer cyc, wsval;
    initial begin
        if (!$value$plusargs("mem=%s", memfile)) begin $display("ERROR: no +mem"); $finish; end
        WAITS = $value$plusargs("ws=%d", wsval) ? wsval[3:0] : 4'd0;
        $readmemh(memfile, imem.mem);
        $readmemh(memfile, dmem.mem);
        @(posedge HCLK); @(negedge HCLK); HRESETn = 1'b1;
        for (cyc = 0; cyc < 60000000; cyc = cyc + 1) begin
            @(negedge HCLK);
            if (ecall_valid) begin
                if      (ecall_svc == 10'h000) $display("OUT INT %0d", $signed(dbg_a0));
                else if (ecall_svc == 10'h001) $display("OUT CHR %0d", dbg_a0[7:0]);
                else if (ecall_svc == 10'h3FF) begin
                    $display("OUT HALT"); $display("CYCLES %0d", cyc); $finish;
                end
            end
        end
        $display("OUT TIMEOUT"); $finish;
    end
endmodule
