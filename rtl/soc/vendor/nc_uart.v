//==============================================================================
// Copyright (c) 2025 nativechips.ai
// Author: Mohamed Shalan (shalan@nativechips.ai)
// License: Apache License 2.0
//==============================================================================
// Module: nc_uart
// Description: UART Controller with APB3 interface, FIFOs, DMA support
//
// Features:
// - Full-duplex UART operation
// - Configurable data format (5-8 bits, 1-2 stop bits, parity)
// - 16-entry TX and RX FIFOs
// - DMA request generation
// - Comprehensive interrupt handling
// - Break detection and generation
// - RX timeout detection
//==============================================================================

`timescale 1ns/1ps

module nc_uart #(
    parameter TX_FIFO_DEPTH = 16,
    parameter RX_FIFO_DEPTH = 16,
    parameter HAS_FIFO      = 1,
    parameter HAS_FRAC_BRR  = 0,
    parameter HAS_RXTO      = 1,
    parameter HAS_LIN       = 0
)(
    // APB3 Slave Interface
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire [11:0] PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // UART Interface
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // Interrupt
    output wire        irq_o,

    // DMA Requests
    output wire        dreq_tx_o,
    output wire        dreq_rx_o
);

    //==========================================================================
    // Parameter Validation (Simulation Only)
    //==========================================================================
    initial begin
        if (!(TX_FIFO_DEPTH == 4 || TX_FIFO_DEPTH == 8 ||
              TX_FIFO_DEPTH == 16 || TX_FIFO_DEPTH == 32)) begin
            $error("%m: Invalid TX_FIFO_DEPTH: %0d. Must be 4, 8, 16, or 32.",
                   TX_FIFO_DEPTH);
            $finish;
        end
        if (!(RX_FIFO_DEPTH == 4 || RX_FIFO_DEPTH == 8 ||
              RX_FIFO_DEPTH == 16 || RX_FIFO_DEPTH == 32)) begin
            $error("%m: Invalid RX_FIFO_DEPTH: %0d. Must be 4, 8, 16, or 32.",
                   RX_FIFO_DEPTH);
            $finish;
        end
        if (HAS_FIFO != 1) begin
            $error("%m: HAS_FIFO must be 1. FIFO-less mode is not supported.");
            $finish;
        end
        if (HAS_FRAC_BRR != 0) begin
            $error("%m: HAS_FRAC_BRR must be 0. Fractional divider is not supported.");
            $finish;
        end
        if (HAS_LIN != 0) begin
            $error("%m: HAS_LIN must be 0. LIN mode is not supported.");
            $finish;
        end
    end

    //==========================================================================
    // Register Address Definitions
    //==========================================================================
    localparam ADDR_CR        = 12'h000;
    localparam ADDR_SR        = 12'h004;
    localparam ADDR_DR        = 12'h008;
    localparam ADDR_IM        = 12'h020;
    localparam ADDR_RIS       = 12'h024;
    localparam ADDR_MIS       = 12'h028;
    localparam ADDR_ICR       = 12'h02C;
    localparam ADDR_DMACR     = 12'h040;
    localparam ADDR_FIFOCTRL  = 12'h050;
    localparam ADDR_FIFOSTR   = 12'h054;
    localparam ADDR_ERRCR     = 12'h090;
    localparam ADDR_BRR       = 12'h100;
    localparam ADDR_LINCR     = 12'h104;
    localparam ADDR_RXTO      = 12'h108;
    localparam ADDR_FEATURE   = 12'hFF8;
    localparam ADDR_IDR       = 12'hFFC;

    //==========================================================================
    // Forward Declarations (declaration-before-use for iverilog v13)
    //==========================================================================
    reg        uart_tx_reg;
    reg        tx_can_load;
    wire       wr_icr;

    //==========================================================================
    // APB3 Interface Signals
    //==========================================================================
    wire apb_setup;
    wire apb_access;
    wire apb_write;
    wire apb_read;

    assign apb_setup  = PSEL & ~PENABLE;
    assign apb_access = PSEL & PENABLE;
    assign apb_write  = apb_access & PWRITE;
    assign apb_read   = apb_access & ~PWRITE;

    //==========================================================================
    // Register Declarations
    //==========================================================================
    // Control Register (CR)
    reg [31:0] cr_reg;
    wire       cr_en;
    wire       cr_srst;
    wire [1:0] cr_mode;
    wire       cr_lpmen;
    wire       cr_dbgen;
    wire       cr_txen;
    wire       cr_rxen;

    assign cr_en    = cr_reg[0];
    assign cr_srst  = cr_reg[1];
    assign cr_mode  = cr_reg[3:2];
    assign cr_lpmen = cr_reg[4];
    assign cr_dbgen = cr_reg[5];
    assign cr_txen  = cr_reg[8];
    assign cr_rxen  = cr_reg[9];

    // Status Register (SR) - read-only
    reg [31:0] sr_reg;

    // Interrupt Registers
    reg [31:0] im_reg;   // Interrupt Mask
    reg [31:0] ris_reg;  // Raw Interrupt Status
    wire [31:0] mis_reg; // Masked Interrupt Status

    assign mis_reg = ris_reg & im_reg;

    // DMA Control Register
    reg [31:0] dmacr_reg;
    wire       dmacr_txdmaen;
    wire       dmacr_rxdmaen;
    wire [7:0] dmacr_txdmath;
    wire [7:0] dmacr_rxdmath;

    assign dmacr_txdmaen = dmacr_reg[0];
    assign dmacr_rxdmaen = dmacr_reg[1];
    assign dmacr_txdmath = dmacr_reg[15:8];
    assign dmacr_rxdmath = dmacr_reg[23:16];

    // FIFO Control Register
    reg [31:0] fifoctrl_reg;
    wire [3:0] fifoctrl_txth;
    wire [3:0] fifoctrl_rxth;
    wire       fifoctrl_txfifo_flush;
    wire       fifoctrl_rxfifo_flush;

    assign fifoctrl_txth          = fifoctrl_reg[3:0];
    assign fifoctrl_rxth          = fifoctrl_reg[7:4];

    // Error Clear Register
    reg [31:0] errcr_reg;

    // Baud Rate Register
    reg [31:0] brr_reg;
    wire [15:0] brr_div;
    wire [3:0]  brr_frac;

    assign brr_div  = brr_reg[15:0];
    assign brr_frac = brr_reg[19:16];

    // Line Control Register
    reg [31:0] lincr_reg;
    wire [1:0] lincr_wls;  // Word length
    wire       lincr_stb;  // Stop bits
    wire       lincr_pen;  // Parity enable
    wire       lincr_eps;  // Even parity select
    wire       lincr_sps;  // Stick parity
    wire       lincr_brk;  // Break control

    assign lincr_wls = lincr_reg[1:0];
    assign lincr_stb = lincr_reg[2];
    assign lincr_pen = lincr_reg[3];
    assign lincr_eps = lincr_reg[4];
    assign lincr_sps = lincr_reg[5];
    assign lincr_brk = lincr_reg[6];

    // Parity type derived from EPS and SPS bits
    wire [1:0] lincr_ptyp;
    assign lincr_ptyp = {lincr_sps, lincr_eps};  // {SPS, EPS}

    // Baud rate divider
    wire [15:0] brr_div_int;
    assign brr_div_int = brr_div;  // Full 16-bit DIV field

    // RX Timeout Register
    reg [31:0] rxto_reg;
    wire [7:0] rxto_val;

    assign rxto_val = rxto_reg[7:0];

    // Feature Register (read-only, computed from parameters)
    wire [31:0] feature_reg;
    wire [3:0]  feature_tx_fifo_sz;
    wire [3:0]  feature_rx_fifo_sz;
    wire        feature_has_rxto;
    wire        feature_has_frac_brr;

    assign feature_tx_fifo_sz = TX_FIFO_DEPTH - 1;
    assign feature_rx_fifo_sz = RX_FIFO_DEPTH - 1;
    assign feature_has_rxto = (HAS_RXTO == 1) ? 1'b1 : 1'b0;
    assign feature_has_frac_brr = (HAS_FRAC_BRR == 1) ? 1'b1 : 1'b0;
    assign feature_reg = {21'h0, 1'b0, feature_has_rxto, feature_has_frac_brr,
                          feature_rx_fifo_sz, feature_tx_fifo_sz};  // TX and RX FIFO sizes (HAS_LIN tied to 0)

    // IDR (read-only)
    localparam IDR_VALUE = 32'h00100001;

    //==========================================================================
    // TX FIFO Instantiation (8-bit data, configurable depth)
    //==========================================================================
    // Calculate address width from depth: AW = clog2(depth)
    localparam TX_FIFO_AW = (TX_FIFO_DEPTH == 4) ? 2 :
                            (TX_FIFO_DEPTH == 8) ? 3 :
                            (TX_FIFO_DEPTH == 16) ? 4 : 5;  // for 32

    wire        tx_fifo_wr;
    wire        tx_fifo_rd;
    wire        tx_fifo_flush;
    wire [7:0]  tx_fifo_wdata;
    wire [7:0]  tx_fifo_rdata;
    wire        tx_fifo_empty;
    wire        tx_fifo_full;
    localparam TX_LVL_W = TX_FIFO_AW + 1;
    wire [TX_LVL_W-1:0] tx_fifo_level;

    // FIFO flush logic
    wire tx_fifo_flush_int;
    assign tx_fifo_flush_int = cr_srst | fifoctrl_txfifo_flush | (!cr_en);

    nc_fifo #(
        .DW(8),
        .AW(TX_FIFO_AW)
    ) u_tx_fifo (
        .clk    (PCLK),
        .rst_n  (PRESETn),
        .rd     (tx_fifo_rd),
        .wr     (tx_fifo_wr),
        .flush  (tx_fifo_flush_int),
        .wdata  (tx_fifo_wdata),
        .empty  (tx_fifo_empty),
        .full   (tx_fifo_full),
        .rdata  (tx_fifo_rdata),
        .level  (tx_fifo_level)
    );

    //==========================================================================
    // RX FIFO Instantiation (12-bit data: 8-bit data + 4 error flags)
    //==========================================================================
    // Calculate address width from depth: AW = clog2(depth)
    localparam RX_FIFO_AW = (RX_FIFO_DEPTH == 4) ? 2 :
                            (RX_FIFO_DEPTH == 8) ? 3 :
                            (RX_FIFO_DEPTH == 16) ? 4 : 5;  // for 32

    wire        rx_fifo_wr;
    wire        rx_fifo_rd;
    wire        rx_fifo_flush;
    wire [11:0] rx_fifo_wdata;
    wire [11:0] rx_fifo_rdata;
    wire        rx_fifo_empty;
    wire        rx_fifo_full;
    localparam RX_LVL_W = RX_FIFO_AW + 1;
    wire [RX_LVL_W-1:0] rx_fifo_level;

    // FIFO flush logic
    wire rx_fifo_flush_int;
    assign rx_fifo_flush_int = cr_srst | fifoctrl_rxfifo_flush | (!cr_en);

    nc_fifo #(
        .DW(12),
        .AW(RX_FIFO_AW)
    ) u_rx_fifo (
        .clk    (PCLK),
        .rst_n  (PRESETn),
        .rd     (rx_fifo_rd),
        .wr     (rx_fifo_wr),
        .flush  (rx_fifo_flush_int),
        .wdata  (rx_fifo_wdata),
        .empty  (rx_fifo_empty),
        .full   (rx_fifo_full),
        .rdata  (rx_fifo_rdata),
        .level  (rx_fifo_level)
    );

    // Zero-extend FIFO levels for threshold comparisons
    wire [7:0] tx_level_ext = {{(8-TX_LVL_W){1'b0}}, tx_fifo_level};
    wire [7:0] rx_level_ext = {{(8-RX_LVL_W){1'b0}}, rx_fifo_level};

    // Pack FIFO levels into 5-bit status fields
    wire [4:0] tx_level_5;
    wire [4:0] rx_level_5;
    generate
        if (TX_LVL_W >= 5) begin : gen_tx_lvl_5_big
            assign tx_level_5 = tx_fifo_level[4:0];
        end else begin : gen_tx_lvl_5_small
            assign tx_level_5 = {{(5-TX_LVL_W){1'b0}}, tx_fifo_level};
        end
    endgenerate
    generate
        if (RX_LVL_W >= 5) begin : gen_rx_lvl_5_big
            assign rx_level_5 = rx_fifo_level[4:0];
        end else begin : gen_rx_lvl_5_small
            assign rx_level_5 = {{(5-RX_LVL_W){1'b0}}, rx_fifo_level};
        end
    endgenerate

    //==========================================================================
    // RX Input Synchronization and Loopback MUX
    //==========================================================================
    wire uart_rx_sync;
    wire uart_rx_loopback;   // Loopback data from TX (with 1-cycle delay)
    wire uart_rx_source;     // RX data source (external or internal)

    nc_sync #(
        .NUM_STAGES(2)
    ) u_rx_sync (
        .clk   (PCLK),
        .rst_n (PRESETn),
        .in    (uart_rx_i),
        .out   (uart_rx_sync)
    );

    // Internal loopback: RX receives TX output directly
    // In loopback mode, sample uart_tx_reg directly since it updates at the end
    // of the clock cycle and will have the correct value when RX samples at counts 6-8.
    // The 1-cycle delay was causing us to sample old values during transitions.
    // RX source MUX: select between external RX pin and internal loopback
    assign uart_rx_source = (cr_mode == 2'b01) ? uart_tx_reg : uart_rx_sync;

    //==========================================================================
    // Baud Rate Generator
    //==========================================================================
    // Baud rate formula: Baud = PCLK / (16 × (DIV + FRAC/16 + 1))
    // nc_ticker period = clk_div + 1, so tick_x16 freq = PCLK / (brr_divider + 1)
    // Final baud = tick_x16 / 16 = PCLK / (16 × (brr_divider + 1))
    // Therefore: brr_divider = DIV + FRAC/16
    wire [15:0] brr_divider;
    wire        baud_tick_x16;

    // For now, use integer divider only (fractional support needs accumulator)
    assign brr_divider = brr_div_int;  // Use full 16-bit DIV value

    nc_ticker #(
        .W(16)
    ) u_baud_ticker (
        .clk        (PCLK),
        .rst_n      (PRESETn),
        .en         (cr_en),  // Enable when UART is enabled
        .clk_div    (brr_divider),
        .tick       (baud_tick_x16)
    );

    // Generate 1x baud tick for TX data shift
    reg [3:0] baud_tick_1x_counter;
    reg       baud_tick_1x;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            baud_tick_1x_counter <= 4'd0;
            baud_tick_1x        <= 1'b0;
        end else begin
            if (baud_tick_x16) begin
                if (baud_tick_1x_counter == 4'd15) begin
                    baud_tick_1x_counter <= 4'd0;
                    baud_tick_1x        <= 1'b1;
                end else begin
                    baud_tick_1x_counter <= baud_tick_1x_counter + 4'd1;
                    baud_tick_1x        <= 1'b0;
                end
            end else begin
                baud_tick_1x <= 1'b0;
            end
        end
    end

    //==========================================================================
    // TX Path
    //==========================================================================
    // Calculate data bits to transmit
    wire [3:0] tx_data_bits;
    assign tx_data_bits = {1'b0, lincr_wls} + 3'd5;  // 5-8 bits

    // Calculate frame size: 1 start + data bits + parity + stop bits
    wire [3:0] tx_frame_size;
    assign tx_frame_size = 4'd1 + tx_data_bits + (lincr_pen ? 4'd1 : 4'd0) +
                           (lincr_stb ? 4'd2 : 4'd1);

    // TX state machine
    reg [3:0]  tx_bit_index;      // Which bit we're currently transmitting (0 to frame_size-1)
    reg        tx_transmitting;   // High after first cycle of transmission
    reg [7:0]  tx_data_reg;       // Data being transmitted
    reg        tx_parity_reg;     // Computed parity bit
    reg        tx_idle;           // High when not transmitting
    reg        tx_tail;           // Hold BUSY through final stop bit
    wire       tx_active;
    wire       tx_busy;

    // Data used for parity calculation (use FIFO data when loading)
    wire [7:0] tx_parity_data;
    assign tx_parity_data = (tx_idle && !tx_fifo_empty && tx_can_load) ? tx_fifo_rdata : tx_data_reg;

    // Parity calculation (uses data_for_parity to ensure correct data)
    reg tx_parity;
    function [7:0] mask_tx_data;
        input [7:0] data;
        input [3:0] nbits;
        reg [8:0] mask;
        begin
            if (nbits >= 8)
                mask = 9'h1FF;
            else
                mask = (9'h1 << nbits) - 1'b1;
            mask_tx_data = data & mask[7:0];
        end
    endfunction
    always @(*) begin
        case (lincr_ptyp)
            2'b00: tx_parity = ~^mask_tx_data(tx_parity_data, tx_data_bits);  // Odd parity (EPS=0)
            2'b01: tx_parity = ^mask_tx_data(tx_parity_data, tx_data_bits);   // Even parity (EPS=1)
            2'b10: tx_parity = 1'b1;                                              // Mark parity (always 1)
            2'b11: tx_parity = 1'b0;                                              // Space parity (always 0)
            default: tx_parity = 1'b0;
        endcase
    end

    // TX state machine - enforce at least 1 bit period between frames
    // (tx_can_load forward-declared above)
    reg tx_can_load_d;
    wire tx_can_load_rise;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            tx_can_load_d <= 1'b0;
        else if (!cr_en || cr_srst)
            tx_can_load_d <= 1'b0;
        else
            tx_can_load_d <= tx_can_load;
    end

    assign tx_can_load_rise = tx_can_load && !tx_can_load_d;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_bit_index     <= 4'd0;
            tx_transmitting  <= 1'b0;
            tx_data_reg      <= 8'd0;
            tx_parity_reg    <= 1'b0;
            tx_idle          <= 1'b1;
            tx_tail          <= 1'b0;
            tx_can_load      <= 1'b0;  // Don't load immediately after reset
        end else if (!cr_en || cr_srst) begin
            tx_bit_index     <= 4'd0;
            tx_transmitting  <= 1'b0;
            tx_data_reg      <= 8'd0;
            tx_parity_reg    <= 1'b0;
            tx_idle          <= 1'b1;
            tx_tail          <= 1'b0;
            tx_can_load      <= 1'b0;  // Don't load immediately after reset
        end else begin
            if (tx_idle) begin
                // Set can_load flag on baud_tick while idle (ensures 1 bit period spacing)
                if (baud_tick_1x)
                    tx_can_load <= 1'b1;

                // Load new data from FIFO (only when allowed)
                if (!tx_fifo_empty && cr_txen && tx_can_load) begin
                    tx_data_reg     <= tx_fifo_rdata;
                    tx_parity_reg   <= tx_parity;
                    tx_bit_index    <= 4'd0;
                    tx_transmitting <= 1'b0;
                    tx_idle         <= 1'b0;
                    tx_can_load     <= 1'b0;  // Clear until next idle period
                    `ifdef DEBUG_TX
                    $display("[%0t] TX: Loading byte 0x%02X from FIFO", $time, tx_fifo_rdata);
                    `endif
                end
            end else begin
                // Transmitting in progress
                if (baud_tick_1x) begin
                    `ifdef DEBUG_TX
                    $display("[%0t] TX: bit_idx=%0d/%0d, bit=%0d, data=0x%02X",
                             $time, tx_bit_index, tx_frame_size-1, tx_next_bit, tx_data_reg);
                    `endif
                    if (tx_bit_index == tx_frame_size - 4'd1) begin
                        // Last bit transmitted
                        tx_idle <= 1'b1;
                        tx_tail <= 1'b1;  // Hold BUSY until next baud tick
                    end else begin
                        // Move to next bit
                        tx_bit_index <= tx_bit_index + 4'd1;
                    end
                end
                // Set transmitting flag one cycle after start
                tx_transmitting <= 1'b1;
            end

            // Clear tail flag one baud tick after last bit launch
            if (tx_tail && baud_tick_1x)
                tx_tail <= 1'b0;
        end
    end

    assign tx_active = ~tx_idle;
    assign tx_busy   = ~tx_idle | tx_tail;

    // TX output mux based on bit index
    // Bit 0: start bit (always 0)
    // Bits 1..N: data bits (LSB first)
    // Next bit: parity (if enabled)
    // Remaining bits: stop bits (always 1)
    reg tx_next_bit;
    wire [3:0] tx_parity_index;
    assign tx_parity_index = 4'd1 + tx_data_bits;
    function tx_data_bit;
        input [7:0] data;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: tx_data_bit = data[0];
                4'd1: tx_data_bit = data[1];
                4'd2: tx_data_bit = data[2];
                4'd3: tx_data_bit = data[3];
                4'd4: tx_data_bit = data[4];
                4'd5: tx_data_bit = data[5];
                4'd6: tx_data_bit = data[6];
                4'd7: tx_data_bit = data[7];
                default: tx_data_bit = 1'b0;
            endcase
        end
    endfunction
    always @(*) begin
        if (tx_bit_index == 4'd0) begin
            tx_next_bit = 1'b0;  // Start bit
        end else if (tx_bit_index <= tx_data_bits) begin
            tx_next_bit = tx_data_bit(tx_data_reg, tx_bit_index - 4'd1);
        end else if (lincr_pen && (tx_bit_index == tx_parity_index)) begin
            tx_next_bit = tx_parity_reg;
        end else begin
            tx_next_bit = 1'b1;  // Stop bits
        end
    end

    // TX output register - update only on baud_tick or when idle/break
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            uart_tx_reg <= 1'b1;  // Idle line is high
        else if (lincr_brk)
            uart_tx_reg <= 1'b0;  // Break forces low
        else if (tx_idle)
            uart_tx_reg <= 1'b1;  // Idle
        else if (baud_tick_1x) begin
            uart_tx_reg <= tx_next_bit;  // Update to next bit on baud tick
            `ifdef DEBUG_TX
            $display("[%0t] TX: uart_tx_o <= %0d", $time, tx_next_bit);
            `endif
        end
    end

    assign uart_tx_o = uart_tx_reg;

    // TX FIFO read - read when idle and starting new transmission
    // Must match the condition for loading tx_data_reg
    assign tx_fifo_rd = tx_idle && cr_txen && !tx_fifo_empty && tx_can_load;

    // TX FIFO write from APB
    assign tx_fifo_wdata = PWDATA[7:0];
    assign tx_fifo_wr    = apb_write && (PADDR[11:0] == ADDR_DR) &&
                          cr_txen && !tx_fifo_full;

    //==========================================================================
    // RX Path
    //==========================================================================
    // RX State Machine States
    localparam RX_IDLE      = 3'd0;
    localparam RX_START     = 3'd1;
    localparam RX_DATA      = 3'd2;
    localparam RX_PARITY    = 3'd3;
    localparam RX_STOP      = 3'd4;
    localparam RX_PUSH      = 3'd5;

    reg [2:0]  rx_state;
    reg [3:0]  rx_bit_count;
    reg [7:0]  rx_shift_reg;
    reg [3:0]  rx_sample_count;
    reg [7:0]  rx_sample_count_abs;  // Absolute sample count (doesn't reset per bit)
    reg [2:0]  rx_samples;  // Majority voting samples
    reg        rx_sampled_bit;  // Majority-voted bit value

    // Majority voting: count ones in 3 samples
    wire rx_majority_one;
    assign rx_majority_one = (rx_samples[0] + rx_samples[1] + rx_samples[2]) >= 2;
    reg        rx_frame_err;
    reg        rx_parity_err;
    reg        rx_break_err;
    reg        rx_overflow_err;
    reg        rx_data_valid;
    reg [7:0]  rx_data_out;

    // Calculate data bits to receive
    wire [3:0] rx_data_bits;
    assign rx_data_bits = {1'b0, lincr_wls} + 3'd5;  // 5-8 bits

    // Calculate RX frame size: 1 start + data bits + parity + stop bits
    wire [3:0] rx_frame_size;
    assign rx_frame_size = 4'd1 + rx_data_bits + (lincr_pen ? 4'd1 : 4'd0) +
                           (lincr_stb ? 4'd2 : 4'd1);

    // Start bit detection (falling edge)
    // Detect falling edge on the RX source (external pin or internal loopback)
    reg uart_rx_source_d1;
    wire rx_start_detected;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            uart_rx_source_d1 <= 1'b1;
        else
            uart_rx_source_d1 <= uart_rx_source;
    end

    assign rx_start_detected = uart_rx_source_d1 && !uart_rx_source;

    // RX state machine
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_state          <= RX_IDLE;
            rx_bit_count      <= 4'd0;
            rx_shift_reg      <= 8'd0;
            rx_sample_count   <= 4'd0;
            rx_sample_count_abs <= 8'd0;
            rx_samples        <= 3'd0;
            rx_sampled_bit    <= 1'b0;
            rx_frame_err      <= 1'b0;
            rx_parity_err     <= 1'b0;
            rx_break_err      <= 1'b0;
            rx_overflow_err   <= 1'b0;
            rx_data_valid     <= 1'b0;
            rx_data_out       <= 8'd0;
        end else if (!cr_en || cr_srst) begin
            rx_state          <= RX_IDLE;
            rx_bit_count      <= 4'd0;
            rx_shift_reg      <= 8'd0;
            rx_sample_count   <= 4'd0;
            rx_sample_count_abs <= 8'd0;
            rx_samples        <= 3'd0;
            rx_sampled_bit    <= 1'b0;
            rx_frame_err      <= 1'b0;
            rx_parity_err     <= 1'b0;
            rx_break_err      <= 1'b0;
            rx_overflow_err   <= 1'b0;
            rx_data_valid     <= 1'b0;
            rx_data_out       <= 8'd0;
        end else begin
            rx_data_valid <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (cr_rxen && rx_start_detected) begin
                        rx_state <= RX_START;
                        rx_sample_count <= 4'd0;
                    end
                end

                RX_START: begin
                    if (baud_tick_x16) begin
                        if (rx_sample_count < 4'd7) begin
                            rx_sample_count <= rx_sample_count + 1'b1;
                            rx_sample_count_abs <= rx_sample_count_abs + 1'b1;
                        end else begin
                            // Sample at center of start bit (count 7)
                            if (uart_rx_source == 1'b0) begin
                                // Valid start bit
                                rx_state <= RX_DATA;
                                rx_bit_count <= 4'd0;
                                rx_sample_count <= 4'd0;  // Reset for next bit period
                                rx_shift_reg <= 8'd0;
                                rx_parity_err <= 1'b0;
                                rx_frame_err <= 1'b0;
                                rx_break_err <= 1'b0;
                                rx_overflow_err <= 1'b0;
                            end else begin
                                // False start bit (noise)
                                rx_state <= RX_IDLE;
                            end
                        end
                    end
                end

                RX_DATA: begin
                    if (baud_tick_x16) begin
                        if (rx_sample_count < 4'd15) begin
                            rx_sample_count <= rx_sample_count + 1'b1;
                            rx_sample_count_abs <= rx_sample_count_abs + 1'b1;
                            // Collect samples at true center (counts 7, 8, 9 for majority voting)
                            if (rx_sample_count >= 4'd7 && rx_sample_count <= 4'd9)
                                rx_samples <= {rx_samples[1:0], uart_rx_source};
                        end else begin
                            // End of bit period - store majority-voted bit
                            // UART is LSB-first: store by bit index
                            rx_sampled_bit <= rx_majority_one;
                            rx_shift_reg[rx_bit_count] <= rx_majority_one;
                            rx_sample_count <= 4'd0;  // Reset relative counter
                            `ifdef DEBUG_RX
                            $display("RX_DATA[%0d]: abs_cnt=%0d bit=%b, reg=0x%02X",
                                     rx_bit_count, rx_sample_count_abs, rx_majority_one, rx_shift_reg);
                            `endif

                            if (rx_bit_count < rx_data_bits - 1) begin
                                rx_bit_count <= rx_bit_count + 1'b1;
                            end else begin
                                // All data bits received
                                if (lincr_pen)
                                    rx_state <= RX_PARITY;
                                else
                                    rx_state <= RX_STOP;
                            end
                        end
                    end
                end

                RX_PARITY: begin
                    if (baud_tick_x16) begin
                        if (rx_sample_count < 4'd15) begin
                            rx_sample_count <= rx_sample_count + 1'b1;
                            // Collect samples at true center for majority voting
                            if (rx_sample_count >= 4'd7 && rx_sample_count <= 4'd9)
                                rx_samples <= {rx_samples[1:0], uart_rx_source};
                        end else begin
                            // Sample parity bit and check
                            rx_sampled_bit <= rx_majority_one;
                            if (lincr_sps) begin
                                // Stick parity: received bit should match EPS polarity
                                rx_parity_err <= (rx_majority_one != lincr_eps);
                            end else begin
                                // Normal parity: XOR all data bits, compare with received
                                // For even parity (EPS=1): error when data_xor != parity_bit
                                // For odd parity (EPS=0): error when data_xor == parity_bit
                                rx_parity_err <= (^rx_shift_reg ^ rx_majority_one ^ ~lincr_eps);
                            end
                            rx_state <= RX_STOP;
                            rx_sample_count <= 4'd0;
                        end
                    end
                end

                RX_STOP: begin
                    if (baud_tick_x16) begin
                        if (rx_sample_count < 4'd15) begin
                            rx_sample_count <= rx_sample_count + 1'b1;
                            // Collect samples at true center for majority voting
                            if (rx_sample_count >= 4'd7 && rx_sample_count <= 4'd9)
                                rx_samples <= {rx_samples[1:0], uart_rx_source};
                        end else begin
                            // Sample stop bit
                            rx_sampled_bit <= rx_majority_one;
                            // Frame error if stop bit is not 1
                            rx_frame_err <= (rx_majority_one == 1'b0);

                            // Check for break condition (all zeros + framing error)
                            rx_break_err <= (rx_shift_reg == 8'd0) && (rx_majority_one == 1'b0);

                            rx_state <= RX_PUSH;
                            rx_sample_count <= 4'd0;
                        end
                    end
                end

                RX_PUSH: begin
                    // Push data to FIFO
                    rx_data_out <= rx_shift_reg;
                    rx_data_valid <= 1'b1;
                    rx_overflow_err <= rx_fifo_full;
                    rx_state <= RX_IDLE;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // RX FIFO write
    assign rx_fifo_wdata = {rx_overflow_err, rx_break_err,
                            rx_parity_err, rx_frame_err, rx_data_out};
    assign rx_fifo_wr    = rx_data_valid && cr_rxen;

    //==========================================================================
    // RX Timeout Counter (character times)
    //==========================================================================
    reg [7:0] rx_timeout_char_cnt;
    reg [3:0] rx_timeout_bit_cnt;
    reg       rx_timeout_irq;
    wire      rx_timeout_active;
    assign rx_timeout_active = cr_en && cr_rxen && !rx_fifo_empty && (rxto_val != 0);

    generate
        if (HAS_RXTO == 1) begin : gen_rxto
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    rx_timeout_char_cnt <= 8'd0;
                    rx_timeout_bit_cnt  <= 4'd0;
                    rx_timeout_irq      <= 1'b0;
                end else if (!rx_timeout_active) begin
                    rx_timeout_char_cnt <= 8'd0;
                    rx_timeout_bit_cnt  <= 4'd0;
                    rx_timeout_irq      <= 1'b0;
                end else begin
                    if (rx_data_valid) begin
                        rx_timeout_char_cnt <= 8'd0;
                        rx_timeout_bit_cnt  <= 4'd0;
                        rx_timeout_irq      <= 1'b0;
                    end else if (baud_tick_1x) begin
                        if (!rx_timeout_irq) begin
                            if (rx_timeout_bit_cnt == rx_frame_size - 4'd1) begin
                                rx_timeout_bit_cnt <= 4'd0;
                                if (rx_timeout_char_cnt == rxto_val - 8'd1)
                                    rx_timeout_irq <= 1'b1;
                                else
                                    rx_timeout_char_cnt <= rx_timeout_char_cnt + 8'd1;
                            end else begin
                                rx_timeout_bit_cnt <= rx_timeout_bit_cnt + 4'd1;
                            end
                        end
                    end
                end
            end
        end else begin : gen_no_rxto
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn)
                    rx_timeout_irq <= 1'b0;
                else
                    rx_timeout_irq <= 1'b0;
            end
        end
    endgenerate

    //==========================================================================
    // Interrupt Generation
    //==========================================================================
    // Interrupt sources
    wire irq_tx;
    wire irq_rx;
    wire irq_tc;
    wire irq_err;
    wire irq_idle;
    wire irq_ovr;
    wire irq_udr;
    wire irq_rto;

    // TX interrupt: FIFO level <= threshold (only when UART enabled and not empty)
    assign irq_tx = cr_en && cr_txen && (tx_level_ext <= {4'b0, fifoctrl_txth});

    // RX interrupt: FIFO level >= threshold (only when UART enabled and not empty)
    assign irq_rx = cr_en && cr_rxen && (rx_level_ext >= {4'b0, fifoctrl_rxth});

    // TX complete: FIFO empty and not busy (only when UART enabled)
    assign irq_tc = cr_en && tx_fifo_empty && !tx_busy;

    // Error interrupt: any error in ERRCR (only when UART enabled)
    assign irq_err = cr_en && |errcr_reg[6:0];

    // Idle interrupt: line idle (not busy and not receiving, only when UART enabled)
    assign irq_idle = cr_en && !tx_busy && (rx_state == RX_IDLE);

    // Overflow interrupt
    wire irq_ovr_int;
    assign irq_ovr_int = rx_overflow_err;
    assign irq_ovr = irq_ovr_int;

    // Underflow interrupt: TX FIFO read when empty (only when UART and TX enabled)
    wire tx_underflow_err;
    assign tx_underflow_err = cr_en && cr_txen && tx_idle && tx_can_load_rise && tx_fifo_empty;
    assign irq_udr = tx_underflow_err;

    // RX timeout interrupt
    assign irq_rto = rx_timeout_irq;

    // Edge detection for interrupt sources
    reg irq_tx_prev, irq_rx_prev, irq_tc_prev, irq_err_prev;
    reg irq_idle_prev, irq_ovr_prev, irq_udr_prev, irq_rto_prev;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            irq_tx_prev   <= 1'b0;
            irq_rx_prev   <= 1'b0;
            irq_tc_prev   <= 1'b0;
            irq_err_prev  <= 1'b0;
            irq_idle_prev <= 1'b0;
            irq_ovr_prev  <= 1'b0;
            irq_udr_prev  <= 1'b0;
            irq_rto_prev  <= 1'b0;
        end else begin
            irq_tx_prev   <= irq_tx;
            irq_rx_prev   <= irq_rx;
            irq_tc_prev   <= irq_tc;
            irq_err_prev  <= irq_err;
            irq_idle_prev <= irq_idle;
            irq_ovr_prev  <= irq_ovr;
            irq_udr_prev  <= irq_udr;
            irq_rto_prev  <= irq_rto;
        end
    end

    // Raw interrupt status - Sticky bits set on rising edge, cleared by ICR
    // Standard behavior: interrupts are set when condition rises (0->1), stay set until cleared
    // For level-sensitive interrupts, they will be re-set on next cycle if condition persists
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ris_reg <= 32'h0;
        end else begin
            // Clear via ICR (write-1-to-clear) - has priority
            if (wr_icr) begin
                if (PWDATA[0]) ris_reg[0] <= 1'b0;
                if (PWDATA[1]) ris_reg[1] <= 1'b0;
                if (PWDATA[2]) ris_reg[2] <= 1'b0;
                if (PWDATA[3]) ris_reg[3] <= 1'b0;
                if (PWDATA[4]) ris_reg[4] <= 1'b0;
                if (PWDATA[5]) ris_reg[5] <= 1'b0;
                if (PWDATA[6]) ris_reg[6] <= 1'b0;
                if (PWDATA[7]) ris_reg[7] <= 1'b0;
            // Set on rising edge of interrupt conditions (only if not being cleared)
            end else begin
                if (irq_tx && !irq_tx_prev)     ris_reg[0] <= 1'b1;
                if (irq_rx && !irq_rx_prev)     ris_reg[1] <= 1'b1;
                if (irq_tc && !irq_tc_prev)     ris_reg[2] <= 1'b1;
                if (irq_err && !irq_err_prev)   ris_reg[3] <= 1'b1;
                if (irq_idle && !irq_idle_prev) ris_reg[4] <= 1'b1;
                if (irq_ovr && !irq_ovr_prev)   ris_reg[5] <= 1'b1;
                if (irq_udr && !irq_udr_prev)   ris_reg[6] <= 1'b1;
                if (irq_rto && !irq_rto_prev)   ris_reg[7] <= 1'b1;
            end
        end
    end

    // Interrupt output
    assign irq_o = |mis_reg[7:0];

    //==========================================================================
    // DMA Request Generation
    //==========================================================================
    wire dma_tx_req;
    wire dma_rx_req;

    // DMA requests: zero-extend 4-bit level to 8-bit for comparison with threshold
    assign dma_tx_req = dmacr_txdmaen && (tx_level_ext <= dmacr_txdmath);
    assign dma_rx_req = dmacr_rxdmaen && (rx_level_ext >= dmacr_rxdmath);

    assign dreq_tx_o = dma_tx_req;
    assign dreq_rx_o = dma_rx_req;

    //==========================================================================
    // Status Register Update
    //==========================================================================
    always @(*) begin
        sr_reg = 32'h0;
        sr_reg[0] = tx_fifo_empty;        // TXE
        sr_reg[1] = !rx_fifo_empty;       // RXNE
        sr_reg[2] = tx_busy;              // BUSY
        sr_reg[3] = |errcr_reg[6:0];      // ERR
        sr_reg[4] = !tx_busy && (rx_state == RX_IDLE);  // IDLE
        sr_reg[5] = tx_fifo_empty && !tx_busy;  // TC
    end

    //==========================================================================
    // APB Register Write Logic
    //==========================================================================
    wire wr_cr;
    wire wr_im;
    // (wr_icr forward-declared above)
    wire wr_dmacr;
    wire wr_fifoctrl;
    wire wr_errcr;
    wire wr_brr;
    wire wr_lincr;
    wire wr_rxto;

    assign wr_cr        = apb_write && (PADDR[11:0] == ADDR_CR);
    assign wr_im        = apb_write && (PADDR[11:0] == ADDR_IM);
    assign wr_icr       = apb_write && (PADDR[11:0] == ADDR_ICR);
    assign wr_dmacr     = apb_write && (PADDR[11:0] == ADDR_DMACR);
    assign wr_fifoctrl  = apb_write && (PADDR[11:0] == ADDR_FIFOCTRL);
    assign wr_errcr     = apb_write && (PADDR[11:0] == ADDR_ERRCR);
    assign wr_brr       = apb_write && (PADDR[11:0] == ADDR_BRR);
    assign wr_lincr     = apb_write && (PADDR[11:0] == ADDR_LINCR);
    assign wr_rxto      = apb_write && (PADDR[11:0] == ADDR_RXTO);

    // FIFO flush pulses (self-clearing)
    assign fifoctrl_txfifo_flush = wr_fifoctrl && PWDATA[8];
    assign fifoctrl_rxfifo_flush = wr_fifoctrl && PWDATA[9];

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            cr_reg       <= 32'h0;
            im_reg       <= 32'h0;
            dmacr_reg    <= 32'h0;
            fifoctrl_reg <= 32'h0;
            errcr_reg    <= 32'h0;
            brr_reg      <= 32'h0;
            lincr_reg    <= 32'h3;  // Default: 8N1
            rxto_reg     <= 32'h0;
        end else begin
            // Software reset: reset all registers when SRST is written
            if (wr_cr && PWDATA[1]) begin
                // Reset all registers to default values
                cr_reg       <= 32'h0;
                im_reg       <= 32'h0;
                dmacr_reg    <= 32'h0;
                fifoctrl_reg <= 32'h0;
                errcr_reg    <= 32'h0;
                // Note: BRR, LINCR, RXTO are not reset by software reset
                // SRST bit is self-clearing (not stored)
            end
            // CR register (normal write when SRST not asserted)
            else if (wr_cr) begin
                cr_reg[0]       <= PWDATA[0];       // EN
                // SRST is self-clearing (bit 1 not stored)
                cr_reg[3:2]     <= PWDATA[3:2];    // MODE
                cr_reg[4]       <= PWDATA[4];       // LPMEN
                cr_reg[5]       <= PWDATA[5];       // DBGEN
                cr_reg[8]       <= PWDATA[8];       // TXEN
                cr_reg[9]       <= PWDATA[9];       // RXEN
            end

            // Other registers (only if not in software reset)
            if (!(wr_cr && PWDATA[1])) begin
                // IM register
                if (wr_im)
                    im_reg[7:0] <= PWDATA[7:0];

                // ICR register handled in interrupt status always block above

                // DMACR register
                if (wr_dmacr)
                    dmacr_reg <= PWDATA;

                // FIFOCTRL register
                if (wr_fifoctrl) begin
                    fifoctrl_reg[7:0] <= PWDATA[7:0];
                    // Flush bits are self-clearing
                end

                // ERRCR register (write-1-to-clear)
                if (wr_errcr) begin
                    if (PWDATA[0]) errcr_reg[0] <= 1'b0;  // OVR
                    if (PWDATA[1]) errcr_reg[1] <= 1'b0;  // UDR
                    if (PWDATA[2]) errcr_reg[2] <= 1'b0;  // FRAME
                    if (PWDATA[3]) errcr_reg[3] <= 1'b0;  // PARITY
                    if (PWDATA[5]) errcr_reg[5] <= 1'b0;  // TIMEOUT
                    if (PWDATA[6]) errcr_reg[6] <= 1'b0;  // BREAK
                end
            end

            // BRR register
            if (wr_brr) begin
                brr_reg[19:0] <= PWDATA[19:0];
            end

            // LINCR register
            if (wr_lincr) begin
                lincr_reg[6:0] <= PWDATA[6:0];
            end

            // RXTO register
            if (HAS_RXTO == 1) begin
                if (wr_rxto)
                    rxto_reg[7:0] <= PWDATA[7:0];
            end

            // Update error flags (only when UART enabled)
            if (cr_en) begin
                if (rx_data_valid && cr_rxen) begin
                    if (rx_frame_err)
                        errcr_reg[2] <= 1'b1;
                    if (rx_parity_err)
                        errcr_reg[3] <= 1'b1;
                    if (rx_break_err)
                        errcr_reg[6] <= 1'b1;
                    if (rx_overflow_err)
                        errcr_reg[0] <= 1'b1;
                end
                if (rx_timeout_irq && cr_rxen)
                    errcr_reg[5] <= 1'b1;
                if (tx_underflow_err)
                    errcr_reg[1] <= 1'b1;
            end
        end
    end

    //==========================================================================
    // APB Register Read Logic (Combinational)
    //==========================================================================
    reg [31:0] prdata_mux;

    always @(*) begin
        prdata_mux = 32'h0;  // Default to prevent latches

        case (PADDR[11:0])
            ADDR_CR:       prdata_mux = cr_reg;
            ADDR_SR:       prdata_mux = sr_reg;
            // DR: Return 0 when FIFO empty, otherwise return data with error flags
            ADDR_DR:       prdata_mux = rx_fifo_empty ? 32'h0 : {20'h0, rx_fifo_rdata};
            ADDR_IM:       prdata_mux = im_reg;
            ADDR_RIS:      prdata_mux = ris_reg;
            ADDR_MIS:      prdata_mux = mis_reg;
            ADDR_ICR:      prdata_mux = 32'h0;  // Write-only
            ADDR_DMACR:    prdata_mux = dmacr_reg;
            ADDR_FIFOCTRL: prdata_mux = fifoctrl_reg;
            ADDR_FIFOSTR:  prdata_mux = {11'h0, rx_level_5, 11'h0, tx_level_5};
            ADDR_ERRCR:    prdata_mux = errcr_reg;
            ADDR_BRR:      prdata_mux = brr_reg;
            ADDR_LINCR:    prdata_mux = lincr_reg;
            ADDR_RXTO:     prdata_mux = (HAS_RXTO == 1) ? rxto_reg : 32'h0;
            ADDR_FEATURE:  prdata_mux = feature_reg;
            ADDR_IDR:      prdata_mux = IDR_VALUE;
            default:       prdata_mux = 32'h0;
        endcase
    end

    // APB backpressure: stall when writing to full TX FIFO
    wire tx_fifo_write_stall = apb_write && (PADDR[11:0] == ADDR_DR) &&
                               tx_fifo_full && cr_txen;

    assign PRDATA  = prdata_mux;
    assign PREADY  = ~tx_fifo_write_stall;  // Stall on TX FIFO full
    assign PSLVERR = 1'b0;  // No errors

    //==========================================================================
    // RX FIFO read from APB
    //==========================================================================
    assign rx_fifo_rd = apb_read && (PADDR[11:0] == ADDR_DR) && cr_rxen &&
                       !rx_fifo_empty;

    //==========================================================================
    // Assertions for verification
    //==========================================================================
    // synthesis translate_off

    // Check that break bit is cleared eventually
    always @(posedge PCLK) begin
        if (lincr_brk)
            $warning("%m: Break condition active - TX line forced low");
    end

    // synthesis translate_on

endmodule
