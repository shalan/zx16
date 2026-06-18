// tb_zx16.v -- testbench: load a $readmemh image (+mem=<file>), run the core,
// emulate ECALL services (print int / char, halt), and stop. Samples on negedge
// so the combinational ecall_valid/dbg_a0 reflect the instruction executing this
// cycle (before the rising edge advances PC). Output lines are machine-parseable
// for the differential harness (rtl/verify.py):
//   "OUT INT <signed-decimal>"   "OUT CHR <0..255>"   "OUT HALT"
module tb_zx16;
    reg clk = 1'b0;
    reg rst = 1'b1;
    wire        halt, ecall_valid;
    wire [9:0]  ecall_svc;
    wire [15:0] dbg_a0;

    zx16_top dut(.clk(clk), .rst(rst), .halt(halt),
                 .ecall_valid(ecall_valid), .ecall_svc(ecall_svc), .dbg_a0(dbg_a0));

    always #5 clk = ~clk;

    reg [1023:0] memfile;
    integer cyc;
    initial begin
        if (!$value$plusargs("mem=%s", memfile)) begin
            $display("ERROR: no +mem=<file>"); $finish;
        end
        $readmemh(memfile, dut.mem.mem);
        @(posedge clk);          // apply reset
        @(negedge clk); rst = 1'b0;
        // generous cap: the software __mul/__div are O(operand), so programs with
        // negative/large multiplicands (e.g. the FFT's negative twiddles) can run
        // into the millions of instructions. Halts early via ECALL 0x3FF.
        for (cyc = 0; cyc < 20000000; cyc = cyc + 1) begin
            @(negedge clk);
            if (ecall_valid) begin
                if      (ecall_svc == 10'h000) $display("OUT INT %0d", $signed(dbg_a0));
                else if (ecall_svc == 10'h001) $display("OUT CHR %0d", dbg_a0[7:0]);
                else if (ecall_svc == 10'h3FF) begin
                    $display("OUT HALT"); $finish;
                end
            end
        end
        $display("OUT TIMEOUT"); $finish;
    end
endmodule
