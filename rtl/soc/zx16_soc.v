`default_nettype none
//============================================================================
// zx16_soc -- ZX16 (16-bit) MCU SoC on 32-bit NativeChips AMBA fabric.
//
//   ZX16 core (I+D AHB masters, 16-bit)
//        |  zx16_ahb16to32 x2 (address window + 16<->32 data)
//   nc_mcu_fabric (W_ADDR=32, W_DATA=32, W_PADDR=16, APB1 off)
//        |- S0 @0x0000_0000 -> zx16_ahb32_sram (on-chip RAM, 48 KB used)
//        |- S1/S2           -> unused (tied off)
//        `- AHB->APB0 @0x4000_0000 -> 16-slot APB3 splitter
//               slot 0 @0x4000_0000 -> nc_uart   (ZX16 sees 0xC000)
//               slot 1 @0x4000_1000 -> nc_tmr    (ZX16 sees 0xD000)
//               slots 2..15         -> unused (PREADY tied high)
//============================================================================
module zx16_soc #(
    parameter [15:0] RESET_PC = 16'h0020,
    parameter integer RAM_AW  = 16            // 64 KB SRAM (0x0000-0xBFFF used)
) (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire uart_irq,
    output wire tmr_irq,
    // debug / stop
    output wire        ecall_valid,
    output wire [9:0]  ecall_svc,
    output wire [15:0] dbg_a0,
    output wire        halted
);
    // ---- ZX16 core masters (16-bit) ----
    wire [15:0] iI_haddr, iI_hwdata, iI_hrdata;
    wire [1:0]  iI_htrans;  wire iI_hwrite;  wire [2:0] iI_hsize, iI_hburst;
    wire [3:0]  iI_hprot;   wire iI_hready, iI_hresp;
    wire [15:0] iD_haddr, iD_hwdata, iD_hrdata;
    wire [1:0]  iD_htrans;  wire iD_hwrite;  wire [2:0] iD_hsize, iD_hburst;
    wire [3:0]  iD_hprot;   wire iD_hready, iD_hresp;

    // ---- interrupt controller: fold peripheral IRQs into the core's vectored input.
    // timer -> vector 2 (0x4), UART -> vector 3 (0x6); timer has priority. The core
    // takes one only when firmware has set IE (ECALL/EI); handlers clear the source.
    wire        soc_irq_req = tmr_irq | uart_irq;
    wire [3:0]  soc_irq_num = tmr_irq ? 4'd2 : 4'd3;

    zx16_core_ahb #(.RESET_PC(RESET_PC)) cpu (
        .HCLK(clk), .HRESETn(rst_n),
        .irq_req(soc_irq_req), .irq_num(soc_irq_num),
        .I_HADDR(iI_haddr), .I_HTRANS(iI_htrans), .I_HWRITE(iI_hwrite),
        .I_HSIZE(iI_hsize), .I_HBURST(iI_hburst), .I_HPROT(iI_hprot),
        .I_HWDATA(iI_hwdata), .I_HRDATA(iI_hrdata), .I_HREADY(iI_hready), .I_HRESP(iI_hresp),
        .D_HADDR(iD_haddr), .D_HTRANS(iD_htrans), .D_HWRITE(iD_hwrite),
        .D_HSIZE(iD_hsize), .D_HBURST(iD_hburst), .D_HPROT(iD_hprot),
        .D_HWDATA(iD_hwdata), .D_HRDATA(iD_hrdata), .D_HREADY(iD_hready), .D_HRESP(iD_hresp),
        .ecall_valid(ecall_valid), .ecall_svc(ecall_svc), .dbg_a0(dbg_a0), .halted(halted)
    );

    // ---- 32-bit fabric master ports ----
    wire [31:0] m0_haddr, m0_hwdata, m0_hrdata;
    wire [1:0]  m0_htrans; wire m0_hwrite; wire [2:0] m0_hsize, m0_hburst; wire [3:0] m0_hprot;
    wire        m0_hready, m0_hresp;
    wire [31:0] m1_haddr, m1_hwdata, m1_hrdata;
    wire [1:0]  m1_htrans; wire m1_hwrite; wire [2:0] m1_hsize, m1_hburst; wire [3:0] m1_hprot;
    wire        m1_hready, m1_hresp;

    zx16_ahb16to32 adp_i (
        .HCLK(clk), .HRESETn(rst_n),
        .m_haddr(iI_haddr), .m_htrans(iI_htrans), .m_hwrite(iI_hwrite), .m_hsize(iI_hsize),
        .m_hburst(iI_hburst), .m_hprot(iI_hprot), .m_hwdata(iI_hwdata),
        .m_hrdata(iI_hrdata), .m_hready(iI_hready), .m_hresp(iI_hresp),
        .f_haddr(m0_haddr), .f_htrans(m0_htrans), .f_hwrite(m0_hwrite), .f_hsize(m0_hsize),
        .f_hburst(m0_hburst), .f_hprot(m0_hprot), .f_hwdata(m0_hwdata),
        .f_hrdata(m0_hrdata), .f_hready(m0_hready), .f_hresp(m0_hresp)
    );
    zx16_ahb16to32 adp_d (
        .HCLK(clk), .HRESETn(rst_n),
        .m_haddr(iD_haddr), .m_htrans(iD_htrans), .m_hwrite(iD_hwrite), .m_hsize(iD_hsize),
        .m_hburst(iD_hburst), .m_hprot(iD_hprot), .m_hwdata(iD_hwdata),
        .m_hrdata(iD_hrdata), .m_hready(iD_hready), .m_hresp(iD_hresp),
        .f_haddr(m1_haddr), .f_htrans(m1_htrans), .f_hwrite(m1_hwrite), .f_hsize(m1_hsize),
        .f_hburst(m1_hburst), .f_hprot(m1_hprot), .f_hwdata(m1_hwdata),
        .f_hrdata(m1_hrdata), .f_hready(m1_hready), .f_hresp(m1_hresp)
    );

    // ---- fabric AHB slave port 0 -> SRAM ; s1/s2 unused ----
    wire [31:0] s0_haddr, s0_hwdata, s0_hrdata;
    wire [1:0]  s0_htrans; wire s0_hwrite; wire [2:0] s0_hsize, s0_hburst; wire [3:0] s0_hprot;
    wire        s0_hready, s0_hready_resp, s0_hresp;

    // ---- APB packed buses ----
    wire [16*16-1:0] apb_paddr;
    wire [15:0]      apb_psel, apb_penable, apb_pwrite, apb_pready, apb_pslverr;
    wire [16*32-1:0] apb_pwdata, apb_prdata;

    // ---- per-slot APB peripheral wires ----
    wire        uart_pready, uart_pslverr;  wire [31:0] uart_prdata;
    wire        tmr_pready,  tmr_pslverr;   wire [31:0] tmr_prdata;

    // slot 0 = UART, slot 1 = timer; slots 2..15 tied ready/zero
    assign apb_pready  = {14'h3FFF, tmr_pready,  uart_pready};
    assign apb_pslverr = {14'h0,    tmr_pslverr, uart_pslverr};
    assign apb_prdata  = {{14{32'h0}}, tmr_prdata, uart_prdata};

    nc_mcu_fabric #(.W_ADDR(32), .W_DATA(32), .W_PADDR(16), .APB1_ENABLE(0)) fabric (
        .clk(clk), .rst_n(rst_n),
        // M0 = imem
        .m0_haddr(m0_haddr), .m0_htrans(m0_htrans), .m0_hwrite(m0_hwrite), .m0_hsize(m0_hsize),
        .m0_hburst(m0_hburst), .m0_hprot(m0_hprot), .m0_hwdata(m0_hwdata),
        .m0_hrdata(m0_hrdata), .m0_hready(m0_hready), .m0_hresp(m0_hresp),
        // M1 = dmem
        .m1_haddr(m1_haddr), .m1_htrans(m1_htrans), .m1_hwrite(m1_hwrite), .m1_hsize(m1_hsize),
        .m1_hburst(m1_hburst), .m1_hprot(m1_hprot), .m1_hwdata(m1_hwdata),
        .m1_hrdata(m1_hrdata), .m1_hready(m1_hready), .m1_hresp(m1_hresp),
        // M2 = DMAC (unused, IDLE)
        .m2_haddr(32'h0), .m2_htrans(2'b00), .m2_hwrite(1'b0), .m2_hsize(3'b0),
        .m2_hburst(3'b0), .m2_hprot(4'b0), .m2_hwdata(32'h0),
        .m2_hrdata(), .m2_hready(), .m2_hresp(),
        // S0 = RAM
        .s0_haddr(s0_haddr), .s0_htrans(s0_htrans), .s0_hwrite(s0_hwrite), .s0_hsize(s0_hsize),
        .s0_hburst(s0_hburst), .s0_hprot(s0_hprot), .s0_hwdata(s0_hwdata),
        .s0_hready(s0_hready), .s0_hready_resp(s0_hready_resp), .s0_hresp(s0_hresp),
        .s0_hrdata(s0_hrdata),
        // S1, S2 unused (drive slave-response inputs benign)
        .s1_haddr(), .s1_htrans(), .s1_hwrite(), .s1_hsize(), .s1_hburst(), .s1_hprot(),
        .s1_hwdata(), .s1_hready(), .s1_hready_resp(1'b1), .s1_hresp(1'b0), .s1_hrdata(32'h0),
        .s2_haddr(), .s2_htrans(), .s2_hwrite(), .s2_hsize(), .s2_hburst(), .s2_hprot(),
        .s2_hwdata(), .s2_hready(), .s2_hready_resp(1'b1), .s2_hresp(1'b0), .s2_hrdata(32'h0),
        // APB0
        .apb_paddr(apb_paddr), .apb_psel(apb_psel), .apb_penable(apb_penable),
        .apb_pwrite(apb_pwrite), .apb_pwdata(apb_pwdata),
        .apb_pready(apb_pready), .apb_prdata(apb_prdata), .apb_pslverr(apb_pslverr),
        // APB1 disabled
        .apb1_paddr(), .apb1_psel(), .apb1_penable(), .apb1_pwrite(), .apb1_pwdata(),
        .apb1_pready(16'hFFFF), .apb1_prdata({16*32{1'b0}}), .apb1_pslverr(16'h0)
    );

    zx16_ahb32_sram #(.AW(RAM_AW)) ram (
        .HCLK(clk), .HRESETn(rst_n),
        .HADDR(s0_haddr), .HTRANS(s0_htrans), .HWRITE(s0_hwrite), .HSIZE(s0_hsize),
        .HBURST(s0_hburst), .HPROT(s0_hprot), .HWDATA(s0_hwdata),
        .HREADY(s0_hready), .HREADYOUT(s0_hready_resp), .HRESP(s0_hresp), .HRDATA(s0_hrdata)
    );

    // ---- APB peripherals ----
    // Deep RX FIFO so a host can stream a command line without per-byte flow control
    // (the bit-bang testbench blasts bytes while firmware stalls during TX responses).
    nc_uart #(.RX_FIFO_DEPTH(32)) uart0 (
        .PCLK(clk), .PRESETn(rst_n),
        .PADDR(apb_paddr[0*16 +: 12]), .PSEL(apb_psel[0]), .PENABLE(apb_penable[0]),
        .PWRITE(apb_pwrite[0]), .PWDATA(apb_pwdata[0*32 +: 32]),
        .PRDATA(uart_prdata), .PREADY(uart_pready), .PSLVERR(uart_pslverr),
        .uart_tx_o(uart_tx), .uart_rx_i(uart_rx), .irq_o(uart_irq),
        .dreq_tx_o(), .dreq_rx_o()
    );

    nc_tmr tmr0 (
        .PCLK(clk), .PRESETn(rst_n),
        .PADDR(apb_paddr[1*16 +: 12]), .PSEL(apb_psel[1]), .PENABLE(apb_penable[1]),
        .PWRITE(apb_pwrite[1]), .PWDATA(apb_pwdata[1*32 +: 32]),
        .PRDATA(tmr_prdata), .PREADY(tmr_pready), .PSLVERR(tmr_pslverr),
        .ti1_i(1'b0), .ti2_i(1'b0), .etr_i(1'b0), .bkin_i(1'b0),
        .ch1_o(), .ch1n_o(), .ch2_o(), .ch2n_o(), .ch3_o(), .ch3n_o(), .ch4_o(),
        .trgo_o(), .irq_o(tmr_irq)
    );
endmodule
`default_nettype wire
