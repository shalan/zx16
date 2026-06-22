`timescale 1ns/1ps
`default_nettype none
//============================================================================
// tb_zx16_soc -- runs a ZX16 SoC image and decodes the real nc_uart TX line.
// The on-chip RAM loads the program via +memh=<file> (see zx16_ahb32_sram).
// Captured UART bytes are printed as "UART <decimal>"; halt prints "HALT".
//============================================================================
module tb_zx16_soc;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;                          // 100 MHz

    wire uart_tx;  reg uart_rx = 1'b1;             // RX idle high
    wire uart_irq, tmr_irq, ecall_valid, halted;
    wire [9:0]  ecall_svc;  wire [15:0] dbg_a0;

    zx16_soc dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .uart_irq(uart_irq), .tmr_irq(tmr_irq),
        .ecall_valid(ecall_valid), .ecall_svc(ecall_svc), .dbg_a0(dbg_a0), .halted(halted)
    );

    initial begin repeat (8) @(posedge clk); rst_n <= 1'b1; end

    localparam integer CPB = 16;        // UART clocks per bit (BRR.DIV=0)

    // ---- optional UART RX injection: bit-bang bytes from +rxfile (decimal/line) ----
    task uart_send(input [7:0] b);
        integer k;
        begin
            uart_rx = 1'b0;                                         // start bit
            repeat (CPB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin                    // 8 data, LSB first
                uart_rx = b[k]; repeat (CPB) @(posedge clk);
            end
            uart_rx = 1'b1;                                         // stop bit + gap
            repeat (16 * CPB) @(posedge clk);   // pace so firmware drains RX between bytes
        end
    endtask
    integer rf, code, val;
    reg [1023:0] rxfile;
    initial begin
        @(posedge rst_n); repeat (5000) @(posedge clk);            // let firmware boot
        if ($value$plusargs("rxfile=%s", rxfile)) begin
            rf = $fopen(rxfile, "r");
            code = $fscanf(rf, "%d", val);
            while (code == 1) begin uart_send(val[7:0]); code = $fscanf(rf, "%d", val); end
            $fclose(rf);
        end
    end

    // ---- inline UART RX monitor: idle-high 8N1, 16 clocks/bit (BRR.DIV=0) ----
    reg [7:0] rxb;  integer bi;
    initial begin
        @(posedge rst_n); repeat (4) @(posedge clk);
        forever begin
            @(negedge uart_tx);                    // start-bit falling edge
            repeat (CPB + CPB/2) @(posedge clk);   // -> centre of data bit 0
            for (bi = 0; bi < 8; bi = bi + 1) begin
                rxb[bi] = uart_tx;                 // LSB first
                repeat (CPB) @(posedge clk);
            end
            $display("UART %0d", rxb);
            repeat (CPB) @(posedge clk);           // ride through the stop bit
        end
    end

    // ---- stop on halt (ECALL 0x3FF) or timeout ----
    // After halt, keep clocking ~4000 cycles so the UART can shift out any byte still
    // in its FIFO/shift register (else the last char is lost), then finish.
    integer cyc = 0;  integer drain = -1;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (rst_n && halted && drain < 0) drain <= 0;
        if (drain >= 0) drain <= drain + 1;
        if (drain > 4000)  begin $display("HALT"); $finish; end
        if (cyc > 150000)  begin $display("TIMEOUT"); $finish; end   // legit runs << this
    end
endmodule
`default_nettype wire
