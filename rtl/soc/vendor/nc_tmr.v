//==============================================================================
// Copyright (c) 2025 nativechips.ai
// Author: Mohamed Shalan (shalan@nativechips.ai)
// License: Apache License 2.0
//==============================================================================
// Module: nc_tmr
// Description: 32-bit General Purpose Timer with Capture/Compare, PWM, and
//              Quadrature Encoder Interface
//
// Features:
//   - 32-bit up/down/center-aligned counter with 16-bit prescaler
//   - 4 capture/compare channels
//   - PWM generation (modes 1 and 2)
//   - Quadrature encoder interface (x1, x2, x4)
//   - Input capture with digital filtering
//   - Complementary outputs (ch1_o-3) with dead-time insertion
//   - Break input for emergency shutdown
//   - External clock/trigger modes
//   - Master/slave synchronization via trgo_o
//   - APB3 slave interface
//   - Timer-class interrupt model
//
// Copyright (c) 2026 nativechips.ai
// Author: Mohamed Shalan (shalan@nativechips.ai)
// License: Apache License 2.0
//==============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_tmr (
    // APB3 Interface
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

    // Timer External Inputs
    input  wire        ti1_i,
    input  wire        ti2_i,
    input  wire        etr_i,
    input  wire        bkin_i,

    // Timer Outputs
    output wire        ch1_o,
    output wire        ch1n_o,
    output wire        ch2_o,
    output wire        ch2n_o,
    output wire        ch3_o,
    output wire        ch3n_o,
    output wire        ch4_o,
    output wire        trgo_o,

    // Interrupt
    output wire        irq_o
);

//------------------------------------------------------------------------------
// Parameters
//------------------------------------------------------------------------------
localparam FEATURE_VALUE = 32'h000000CF;  // All features enabled
localparam ID_VALUE      = 32'h00100010;  // Timer ID

//------------------------------------------------------------------------------
// Forward Declarations (declaration-before-use for iverilog v13)
//------------------------------------------------------------------------------
wire sel_cr;
wire encoder_mode;
wire cnt_write_block;
wire update_event;
reg  encoder_count_pulse;
reg  encoder_dir_up;

//------------------------------------------------------------------------------
// APB3 Interface - Address Decode
//------------------------------------------------------------------------------
wire apb_write = PSEL & PENABLE & PWRITE;
wire apb_read  = PSEL & PENABLE & ~PWRITE;
wire srst_req  = apb_write && sel_cr && PWDATA[1];

// Standard registers
assign sel_cr    = (PADDR[11:0] == 12'h000);
wire sel_sr      = (PADDR[11:0] == 12'h004);
wire sel_im      = (PADDR[11:0] == 12'h020);
wire sel_ris     = (PADDR[11:0] == 12'h024);
wire sel_mis     = (PADDR[11:0] == 12'h028);
wire sel_icr     = (PADDR[11:0] == 12'h02C);
wire sel_dmacr   = (PADDR[11:0] == 12'h040);
wire sel_errcr   = (PADDR[11:0] == 12'h090);

// Timer-specific registers
wire sel_cnt     = (PADDR[11:0] == 12'h100);
wire sel_psc     = (PADDR[11:0] == 12'h104);
wire sel_arr     = (PADDR[11:0] == 12'h108);
wire sel_rcr     = (PADDR[11:0] == 12'h10C);
wire sel_ccr1    = (PADDR[11:0] == 12'h110);
wire sel_ccr2    = (PADDR[11:0] == 12'h114);
wire sel_ccr3    = (PADDR[11:0] == 12'h118);
wire sel_ccr4    = (PADDR[11:0] == 12'h11C);
wire sel_bdtr    = (PADDR[11:0] == 12'h120);
wire sel_smcr    = (PADDR[11:0] == 12'h124);
wire sel_ccmr1   = (PADDR[11:0] == 12'h128);
wire sel_ccmr2   = (PADDR[11:0] == 12'h12C);
wire sel_ccer    = (PADDR[11:0] == 12'h130);
wire sel_egr     = (PADDR[11:0] == 12'h134);

// Identification registers
wire sel_feature = (PADDR[11:0] == 12'hFF8);
wire sel_id      = (PADDR[11:0] == 12'hFFC);

//------------------------------------------------------------------------------
// Register Definitions
//------------------------------------------------------------------------------
// CR - Control Register
reg [15:0] cr_reg;
wire       cr_en   = cr_reg[0];
wire [1:0] cr_mode = cr_reg[3:2];
wire       cr_dir  = cr_reg[6];
wire [1:0] cr_cms  = cr_reg[9:8];
wire       cr_arpe = cr_reg[10];
wire [1:0] cr_ckd  = cr_reg[12:11];
wire       srst    = cr_reg[1] | srst_req;
wire       one_pulse_mode = (cr_mode == 2'b01);
localparam [15:0] CR_WRITABLE_MASK = 16'h1F7F;

// IM - Interrupt Mask
reg [7:0] im_reg;

// RIS - Raw Interrupt Status
reg       ris_uif;
reg       ris_cc1if;
reg       ris_cc2if;
reg       ris_cc3if;
reg       ris_cc4if;
reg       ris_tif;
reg       ris_bif;
wire [7:0] ris_reg = {ris_bif, ris_tif, 1'b0, ris_cc4if, ris_cc3if, ris_cc2if, ris_cc1if, ris_uif};

// MIS - Masked Interrupt Status
wire [7:0] mis_reg = ris_reg & im_reg;

// ERRCR - Error Status
reg [1:0] errcr_reg;

// Timer registers
reg [31:0] cnt_reg;
reg [15:0] psc_reg;
reg [31:0] arr_reg;
reg [7:0]  rcr_reg;
reg [31:0] ccr1_reg;
reg [31:0] ccr2_reg;
reg [31:0] ccr3_reg;
reg [31:0] ccr4_reg;
reg [15:0] bdtr_reg;
reg [15:0] smcr_reg;
reg [15:0] ccmr1_reg;
reg [15:0] ccmr2_reg;
reg [15:0] ccer_reg;

// Overcapture flags
reg cc1of_flag;
reg cc2of_flag;
reg cc3of_flag;
reg cc4of_flag;

//------------------------------------------------------------------------------
// Register Field Extraction
//------------------------------------------------------------------------------
// BDTR fields
wire [8:0] bdtr_dtg = bdtr_reg[8:0];
wire       bdtr_bke = bdtr_reg[12];
wire       bdtr_bkp = bdtr_reg[13];
wire       bdtr_aoe = bdtr_reg[14];
wire       bdtr_moe = bdtr_reg[15];

// SMCR fields
wire [2:0] smcr_sms  = smcr_reg[2:0];
wire [2:0] smcr_ts   = smcr_reg[6:4];
wire       smcr_msm  = smcr_reg[7];
wire [3:0] smcr_etf  = smcr_reg[11:8];
wire [1:0] smcr_etps = smcr_reg[13:12];
wire       smcr_ece  = smcr_reg[14];
wire       smcr_etp  = smcr_reg[15];

// CCMR1 fields (Channel 1 and 2)
wire [1:0] ccmr1_cc1s  = ccmr1_reg[1:0];
wire [1:0] ccmr1_ic1psc = ccmr1_reg[3:2];
wire       ccmr1_oc1pe = ccmr1_reg[3];
wire [3:0] ccmr1_ic1f  = {ccmr1_reg[7], ccmr1_reg[6:4]};
wire [2:0] ccmr1_oc1m  = ccmr1_reg[6:4];

wire [1:0] ccmr1_cc2s  = ccmr1_reg[9:8];
wire [1:0] ccmr1_ic2psc = ccmr1_reg[11:10];
wire       ccmr1_oc2pe = ccmr1_reg[11];
wire [3:0] ccmr1_ic2f  = {ccmr1_reg[15], ccmr1_reg[14:12]};
wire [2:0] ccmr1_oc2m  = ccmr1_reg[14:12];

// CCMR2 fields (Channel 3 and 4)
wire [1:0] ccmr2_cc3s  = ccmr2_reg[1:0];
wire [1:0] ccmr2_ic3psc = ccmr2_reg[3:2];
wire       ccmr2_oc3pe = ccmr2_reg[3];
wire [3:0] ccmr2_ic3f  = {ccmr2_reg[7], ccmr2_reg[6:4]};
wire [2:0] ccmr2_oc3m  = ccmr2_reg[6:4];

wire [1:0] ccmr2_cc4s  = ccmr2_reg[9:8];
wire [1:0] ccmr2_ic4psc = ccmr2_reg[11:10];
wire       ccmr2_oc4pe = ccmr2_reg[11];
wire [3:0] ccmr2_ic4f  = {ccmr2_reg[15], ccmr2_reg[14:12]};
wire [2:0] ccmr2_oc4m  = ccmr2_reg[14:12];

// CCER fields
wire ccer_cc1e  = ccer_reg[0];
wire ccer_cc1p  = ccer_reg[1];
wire ccer_cc1ne = ccer_reg[2];
wire ccer_cc1np = ccer_reg[3];
wire ccer_cc2e  = ccer_reg[4];
wire ccer_cc2p  = ccer_reg[5];
wire ccer_cc2ne = ccer_reg[6];
wire ccer_cc2np = ccer_reg[7];
wire ccer_cc3e  = ccer_reg[8];
wire ccer_cc3p  = ccer_reg[9];
wire ccer_cc3ne = ccer_reg[10];
wire ccer_cc3np = ccer_reg[11];
wire ccer_cc4e  = ccer_reg[12];
wire ccer_cc4p  = ccer_reg[13];

//------------------------------------------------------------------------------
// Input Synchronization
//------------------------------------------------------------------------------
wire ti1_sync, ti2_sync, etr_sync, bkin_sync;

nc_sync #(.NUM_STAGES(2)) sync_ti1 (
    .clk    (PCLK),
    .rst_n  (PRESETn),
    .in     (ti1_i),
    .out    (ti1_sync)
);

nc_sync #(.NUM_STAGES(2)) sync_ti2 (
    .clk    (PCLK),
    .rst_n  (PRESETn),
    .in     (ti2_i),
    .out    (ti2_sync)
);

nc_sync #(.NUM_STAGES(2)) sync_etr (
    .clk    (PCLK),
    .rst_n  (PRESETn),
    .in     (etr_i),
    .out    (etr_sync)
);

nc_sync #(.NUM_STAGES(2)) sync_bkin (
    .clk    (PCLK),
    .rst_n  (PRESETn),
    .in     (bkin_i),
    .out    (bkin_sync)
);

//------------------------------------------------------------------------------
// Input Filtering
//------------------------------------------------------------------------------
// Programmable Digital Filters (0-15 stages) with CKD-based sampling
//------------------------------------------------------------------------------
reg  [2:0] ckd_cnt;
wire [2:0] ckd_divisor = (cr_ckd == 2'b00) ? 3'd1 :
                         (cr_ckd == 2'b01) ? 3'd2 :
                         (cr_ckd == 2'b10) ? 3'd4 : 3'd1;
wire       ckd_tick    = (ckd_cnt == 3'd0);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ckd_cnt <= 3'd0;
    else if (srst || !cr_en)
        ckd_cnt <= 3'd0;
    else if (ckd_cnt == (ckd_divisor - 3'd1))
        ckd_cnt <= 3'd0;
    else
        ckd_cnt <= ckd_cnt + 3'd1;
end

function [15:0] filt_mask;
    input [3:0] len;
    begin
        case (len)
            4'd0:  filt_mask = 16'h0000;
            4'd1:  filt_mask = 16'h0001;
            4'd2:  filt_mask = 16'h0003;
            4'd3:  filt_mask = 16'h0007;
            4'd4:  filt_mask = 16'h000F;
            4'd5:  filt_mask = 16'h001F;
            4'd6:  filt_mask = 16'h003F;
            4'd7:  filt_mask = 16'h007F;
            4'd8:  filt_mask = 16'h00FF;
            4'd9:  filt_mask = 16'h01FF;
            4'd10: filt_mask = 16'h03FF;
            4'd11: filt_mask = 16'h07FF;
            4'd12: filt_mask = 16'h0FFF;
            4'd13: filt_mask = 16'h1FFF;
            4'd14: filt_mask = 16'h3FFF;
            4'd15: filt_mask = 16'h7FFF;
            default: filt_mask = 16'h0000;
        endcase
    end
endfunction

reg [15:0] ti1_shift;
reg [15:0] ti2_shift;
reg [15:0] etr_shift;
reg        ti1_filtered;
reg        ti2_filtered;
reg        etr_filtered;

wire       ti1_use_filter = (ccmr1_ic1f != 4'h0);
wire       ti2_use_filter = (ccmr1_ic2f != 4'h0);
wire       etr_use_filter = (smcr_etf   != 4'h0);

wire [15:0] ti1_mask = filt_mask(ccmr1_ic1f);
wire [15:0] ti2_mask = filt_mask(ccmr1_ic2f);
wire [15:0] etr_mask = filt_mask(smcr_etf);

wire [15:0] ti1_shift_next = {ti1_shift[14:0], ti1_sync};
wire [15:0] ti2_shift_next = {ti2_shift[14:0], ti2_sync};
wire [15:0] etr_shift_next = {etr_shift[14:0], etr_sync};

wire ti1_all_ones_next  = ti1_use_filter && &(ti1_shift_next & ti1_mask);
wire ti1_all_zeros_next = ti1_use_filter && ~|(ti1_shift_next & ti1_mask);
wire ti2_all_ones_next  = ti2_use_filter && &(ti2_shift_next & ti2_mask);
wire ti2_all_zeros_next = ti2_use_filter && ~|(ti2_shift_next & ti2_mask);
wire etr_all_ones_next  = etr_use_filter && &(etr_shift_next & etr_mask);
wire etr_all_zeros_next = etr_use_filter && ~|(etr_shift_next & etr_mask);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ti1_shift    <= 16'h0000;
        ti1_filtered <= 1'b0;
    end else if (srst) begin
        ti1_shift    <= 16'h0000;
        ti1_filtered <= 1'b0;
    end else if (!cr_en || !ti1_use_filter) begin
        ti1_shift    <= {16{ti1_sync}};
        ti1_filtered <= ti1_sync;
    end else if (ckd_tick) begin
        ti1_shift <= ti1_shift_next;
        if (ti1_all_ones_next)
            ti1_filtered <= 1'b1;
        else if (ti1_all_zeros_next)
            ti1_filtered <= 1'b0;
    end
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ti2_shift    <= 16'h0000;
        ti2_filtered <= 1'b0;
    end else if (srst) begin
        ti2_shift    <= 16'h0000;
        ti2_filtered <= 1'b0;
    end else if (!cr_en || !ti2_use_filter) begin
        ti2_shift    <= {16{ti2_sync}};
        ti2_filtered <= ti2_sync;
    end else if (ckd_tick) begin
        ti2_shift <= ti2_shift_next;
        if (ti2_all_ones_next)
            ti2_filtered <= 1'b1;
        else if (ti2_all_zeros_next)
            ti2_filtered <= 1'b0;
    end
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        etr_shift    <= 16'h0000;
        etr_filtered <= 1'b0;
    end else if (srst) begin
        etr_shift    <= 16'h0000;
        etr_filtered <= 1'b0;
    end else if (!cr_en || !etr_use_filter) begin
        etr_shift    <= {16{etr_sync}};
        etr_filtered <= etr_sync;
    end else if (ckd_tick) begin
        etr_shift <= etr_shift_next;
        if (etr_all_ones_next)
            etr_filtered <= 1'b1;
        else if (etr_all_zeros_next)
            etr_filtered <= 1'b0;
    end
end

wire ti1_final = (ccmr1_ic1f != 4'h0) ? ti1_filtered : ti1_sync;
wire ti2_final = (ccmr1_ic2f != 4'h0) ? ti2_filtered : ti2_sync;
wire etr_final = (smcr_etf != 4'h0) ? etr_filtered : etr_sync;
wire etr_pol   = smcr_etp ? ~etr_final : etr_final;

//------------------------------------------------------------------------------
// Edge Detection
//------------------------------------------------------------------------------
reg ti1_d, ti2_d, etr_d;
wire ti1_rise, ti1_fall, ti2_rise, ti2_fall, etr_rise, etr_fall;
reg [1:0] enc_state_d;
wire [1:0] enc_state = {ti1_final, ti2_final};
wire       enc_change = (enc_state != enc_state_d);
wire       enc_invalid = encoder_mode && enc_change &&
                         (enc_state[0] != enc_state_d[0]) &&
                         (enc_state[1] != enc_state_d[1]);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ti1_d <= 1'b0;
        ti2_d <= 1'b0;
        etr_d <= 1'b0;
        enc_state_d <= 2'b00;
    end else if (srst) begin
        ti1_d <= 1'b0;
        ti2_d <= 1'b0;
        etr_d <= 1'b0;
        enc_state_d <= 2'b00;
    end else begin
        ti1_d <= ti1_final;
        ti2_d <= ti2_final;
        etr_d <= etr_final;
        enc_state_d <= enc_state;
    end
end

assign ti1_rise = ti1_final && !ti1_d;
assign ti1_fall = !ti1_final && ti1_d;
assign ti2_rise = ti2_final && !ti2_d;
assign ti2_fall = !ti2_final && ti2_d;
assign etr_rise = etr_final && !etr_d;
assign etr_fall = !etr_final && etr_d;

//------------------------------------------------------------------------------
// Prescaler Logic
//------------------------------------------------------------------------------
reg [15:0] psc_counter;
reg [15:0] psc_shadow;
wire       psc_tick;

wire counter_clk_enable;  // Modified by slave mode logic
wire count_tick;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        psc_counter <= 16'h0;
        psc_shadow  <= 16'h0;
    end else if (srst) begin
        psc_counter <= 16'h0;
        psc_shadow  <= 16'h0;
    end else begin
        // Update shadow register on update event (even when disabled)
        if (update_event) begin
            psc_shadow <= psc_reg;
        end

        // Prescaler counter logic
        if (apb_write && sel_cnt) begin
            // BUG FIX #2: Reset prescaler when CNT is written
            psc_counter <= psc_shadow;
        end else if (!cr_en) begin
            // When disabled, reset counter but keep shadow
            psc_counter <= 16'h0;
        end else if (update_event) begin
            psc_counter <= psc_reg;
        end else if (counter_clk_enable) begin
            if (psc_counter == 16'h0) begin
                psc_counter <= psc_shadow;
            end else begin
                psc_counter <= psc_counter - 16'h1;
            end
        end
    end
end

// BUG FIX #2: Also block psc_tick during CNT write to ensure counter stays stable
assign psc_tick = (psc_counter == 16'h0) && counter_clk_enable && !cnt_write_block && !(apb_write && sel_cnt);

//------------------------------------------------------------------------------
// Counter Core
//------------------------------------------------------------------------------
reg [31:0] arr_shadow;
reg        dir_reg;  // Internal direction for center-aligned mode

// Auto-reload shadow
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        arr_shadow <= 32'hFFFFFFFF;
    end else if (srst) begin
        arr_shadow <= 32'hFFFFFFFF;
    end else if (update_event || !cr_arpe) begin
        arr_shadow <= arr_reg;
    end
end

// BUG FIX #3: Register overflow/underflow flags to avoid race condition
// These are set when wrap actually occurs, used by repetition counter and update event
reg cnt_overflow;
reg cnt_underflow;

// Counter logic
// (encoder_mode forward-declared above)
assign encoder_mode = (cr_mode == 2'b10) &&
                      (smcr_sms == 3'b001 || smcr_sms == 3'b010 || smcr_sms == 3'b011);
wire counter_reset_req;

// BUG FIX #2: Block counter increment for TWO cycles after CNT write
// (to account for APB read transaction timing)
reg [1:0] cnt_write_block_cnt;
// (cnt_write_block forward-declared above)
assign cnt_write_block = (cnt_write_block_cnt != 2'b00);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        cnt_write_block_cnt <= 2'b00;
    else if (srst)
        cnt_write_block_cnt <= 2'b00;
    else if (apb_write && sel_cnt)
        cnt_write_block_cnt <= 2'b10;  // Block for 2 cycles (10→01→00)
    else if (cnt_write_block_cnt != 2'b00)
        cnt_write_block_cnt <= cnt_write_block_cnt - 2'b01;
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        cnt_reg <= 32'h0;
        dir_reg <= 1'b0;
        cnt_overflow <= 1'b0;   // BUG FIX #3
        cnt_underflow <= 1'b0;  // BUG FIX #3
    end else if (srst) begin
        cnt_reg <= 32'h0;
        dir_reg <= 1'b0;
        cnt_overflow <= 1'b0;
        cnt_underflow <= 1'b0;
    end else if (apb_write && sel_cnt) begin
        // BUG FIX #2: CNT write has highest priority (works when disabled too)
        cnt_reg <= PWDATA;
        cnt_overflow <= 1'b0;   // Clear flags on manual write
        cnt_underflow <= 1'b0;
    end else if (cnt_write_block) begin
        // BUG FIX #2: Hold counter for one cycle after write to prevent increment
        cnt_reg <= cnt_reg;
        cnt_overflow <= 1'b0;
        cnt_underflow <= 1'b0;
    end else if (!cr_en) begin
        // Counter stopped - hold value
        cnt_reg <= cnt_reg;
        cnt_overflow <= 1'b0;
        cnt_underflow <= 1'b0;
    end else if (counter_reset_req) begin
        cnt_reg <= 32'h0;
        dir_reg <= 1'b0;
        cnt_overflow <= 1'b0;
        cnt_underflow <= 1'b0;
    end else if (encoder_mode) begin
        // Encoder mode counting
        if (encoder_count_pulse) begin
            if (encoder_dir_up) begin
                if (cnt_reg == arr_shadow) begin
                    cnt_reg <= 32'h0;
                    cnt_overflow <= 1'b1;  // BUG FIX #3: Set flag when wrap occurs
                    cnt_underflow <= 1'b0;
                end else begin
                    cnt_reg <= cnt_reg + 32'h1;
                    cnt_overflow <= 1'b0;
                    cnt_underflow <= 1'b0;
                end
            end else begin
                if (cnt_reg == 32'h0) begin
                    cnt_reg <= arr_shadow;
                    cnt_overflow <= 1'b0;
                    cnt_underflow <= 1'b1;  // BUG FIX #3: Set flag when wrap occurs
                end else begin
                    cnt_reg <= cnt_reg - 32'h1;
                    cnt_overflow <= 1'b0;
                    cnt_underflow <= 1'b0;
                end
            end
        end else begin
            // No encoder pulse, hold values
            cnt_overflow <= 1'b0;
            cnt_underflow <= 1'b0;
        end
    end else if (count_tick) begin
        case (cr_cms)
            2'b00: begin  // Edge-aligned mode
                if (cr_dir == 1'b0) begin
                    // BUG FIX #3: Check for wrap BEFORE incrementing
                    if (cnt_reg == arr_shadow) begin
                        cnt_reg <= 32'h0;
                        cnt_overflow <= 1'b1;  // Set flag when wrap occurs
                        cnt_underflow <= 1'b0;
                    end else begin
                        cnt_reg <= cnt_reg + 32'h1;
                        cnt_overflow <= 1'b0;
                        cnt_underflow <= 1'b0;
                    end
                end else begin
                    // BUG FIX #3: Check for wrap BEFORE decrementing
                    if (cnt_reg == 32'h0) begin
                        cnt_reg <= arr_shadow;
                        cnt_overflow <= 1'b0;
                        cnt_underflow <= 1'b1;  // Set flag when wrap occurs
                    end else begin
                        cnt_reg <= cnt_reg - 32'h1;
                        cnt_overflow <= 1'b0;
                        cnt_underflow <= 1'b0;
                    end
                end
            end
            default: begin  // Center-aligned modes
                if (dir_reg == 1'b0) begin
                    // BUG FIX #3: Check for wrap BEFORE incrementing
                    if (cnt_reg == arr_shadow) begin
                        dir_reg <= 1'b1;
                        cnt_reg <= cnt_reg - 32'h1;
                        cnt_overflow <= 1'b1;  // Set flag when wrap occurs
                        cnt_underflow <= 1'b0;
                    end else begin
                        cnt_reg <= cnt_reg + 32'h1;
                        cnt_overflow <= 1'b0;
                        cnt_underflow <= 1'b0;
                    end
                end else begin
                    // BUG FIX #3: Check for wrap BEFORE decrementing
                    if (cnt_reg == 32'h0) begin
                        dir_reg <= 1'b0;
                        cnt_reg <= cnt_reg + 32'h1;
                        cnt_overflow <= 1'b0;
                        cnt_underflow <= 1'b1;  // Set flag when wrap occurs
                    end else begin
                        cnt_reg <= cnt_reg - 32'h1;
                        cnt_overflow <= 1'b0;
                        cnt_underflow <= 1'b0;
                    end
                end
            end
        endcase
    end else begin
        // psc_tick not active, clear flags
        cnt_overflow <= 1'b0;
        cnt_underflow <= 1'b0;
    end
end

//------------------------------------------------------------------------------
// Repetition Counter
//------------------------------------------------------------------------------
reg [7:0] rcr_counter;
reg [7:0] rcr_shadow;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        rcr_counter <= 8'h0;
        rcr_shadow  <= 8'h0;
    end else if (srst) begin
        rcr_counter <= 8'h0;
        rcr_shadow  <= 8'h0;
    end else if (update_event) begin
        rcr_counter <= rcr_reg;
        rcr_shadow  <= rcr_reg;
    end else if (cnt_overflow || cnt_underflow) begin
        if (rcr_counter == 8'h0) begin
            rcr_counter <= rcr_shadow;
        end else begin
            rcr_counter <= rcr_counter - 8'h1;
        end
    end
end

wire rcr_underflow = (rcr_counter == 8'h0);

//------------------------------------------------------------------------------
// Update Event Generation
//------------------------------------------------------------------------------
wire update_event_internal = (cnt_overflow || cnt_underflow) && rcr_underflow;
wire ug_trigger = apb_write && sel_egr && PWDATA[0];

// (update_event forward-declared above)
assign update_event = update_event_internal || ug_trigger || counter_reset_req;

//------------------------------------------------------------------------------
// Quadrature Encoder Decoder
//------------------------------------------------------------------------------
// (encoder_count_pulse, encoder_dir_up forward-declared above)

always @(*) begin
    encoder_count_pulse = 1'b0;
    encoder_dir_up = 1'b0;

    if (encoder_mode) begin
        if (smcr_sms == 3'b001) begin
            // Encoder Mode 1 (x1): Count on ti1_i rising edges only, direction from ti2_i
            if (ti1_rise) begin
                encoder_count_pulse = 1'b1;
                encoder_dir_up = ti2_final ? 1'b0 : 1'b1;  // ti2_i=1 => reverse, ti2_i=0 => forward
            end
        end else if (smcr_sms == 3'b010) begin
            // Encoder Mode 2 (x1): Count on ti2_i rising edges only, direction from ti1_i
            if (ti2_rise) begin
                encoder_count_pulse = 1'b1;
                encoder_dir_up = ti1_final ? 1'b1 : 1'b0;  // ti1_i=1 => forward, ti1_i=0 => reverse
            end
        end else if (smcr_sms == 3'b011) begin
            // Encoder Mode 3: Count on both edges (x4)
            if (ti1_rise || ti1_fall || ti2_rise || ti2_fall) begin
                encoder_count_pulse = 1'b1;
                case ({ti1_rise, ti1_fall, ti2_rise, ti2_fall})
                    4'b1000: encoder_dir_up = !ti2_final;
                    4'b0100: encoder_dir_up = ti2_final;
                    4'b0010: encoder_dir_up = ti1_final;
                    4'b0001: encoder_dir_up = !ti1_final;
                    default: encoder_dir_up = 1'b0;
                endcase
            end
        end
    end
end

//------------------------------------------------------------------------------
// Slave Mode Controller
//------------------------------------------------------------------------------
wire trigger_level;
wire trigger_rise;
wire trigger_fall;
wire trigger_event;
wire etr_event;
reg  trigger_d;
reg  trigger_start;

wire reset_mode    = (smcr_sms == 3'b100);
wire gated_mode    = (smcr_sms == 3'b101);
wire trigger_mode  = (smcr_sms == 3'b110);
wire extclk_mode1  = (smcr_sms == 3'b111);
wire extclk_mode2  = smcr_ece;

// Trigger selection (level sources)
assign trigger_level = (smcr_ts == 3'b101) ? ti1_final :
                       (smcr_ts == 3'b110) ? ti2_final :
                       (smcr_ts == 3'b111) ? etr_pol  :
                       1'b0;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        trigger_d <= 1'b0;
    else if (srst)
        trigger_d <= 1'b0;
    else
        trigger_d <= trigger_level;
end

assign trigger_rise = trigger_level && !trigger_d;
assign trigger_fall = !trigger_level && trigger_d;

// etr_i prescaler and event generation (applies to ETRF)
wire [3:0] etr_psc_div = (smcr_etps == 2'b00) ? 4'd1 :
                         (smcr_etps == 2'b01) ? 4'd2 :
                         (smcr_etps == 2'b10) ? 4'd4 : 4'd8;
wire       etr_event_raw = smcr_etp ? etr_fall : etr_rise;
reg  [3:0] etr_psc_cnt;
wire       etr_psc_hit = (etr_psc_cnt == (etr_psc_div - 4'd1));

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        etr_psc_cnt <= 3'd0;
    else if (srst)
        etr_psc_cnt <= 3'd0;
    else if (etr_event_raw) begin
        if (etr_psc_hit)
            etr_psc_cnt <= 3'd0;
        else
            etr_psc_cnt <= etr_psc_cnt + 3'd1;
    end
end

assign etr_event = etr_event_raw && (smcr_etps == 2'b00 || etr_psc_hit);
assign trigger_event = (smcr_ts == 3'b100) ? (ti1_rise || ti1_fall) :
                       (smcr_ts == 3'b111) ? etr_event : trigger_rise;

// Trigger mode: latch start on trigger event
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        trigger_start <= 1'b0;
    else if (srst || !cr_en || !trigger_mode)
        trigger_start <= 1'b0;
    else if (trigger_event)
        trigger_start <= 1'b1;
end

// Slave mode logic
assign counter_reset_req = reset_mode && trigger_event;
assign counter_clk_enable = gated_mode ? trigger_level :
                            trigger_mode ? trigger_start : 1'b1;
wire count_tick_raw = extclk_mode2 ? etr_event :
                      extclk_mode1 ? trigger_event : psc_tick;
assign count_tick = count_tick_raw && counter_clk_enable;

//------------------------------------------------------------------------------
// Capture/Compare Channel 1
//------------------------------------------------------------------------------
reg [31:0] ccr1_shadow;
wire       ic1_capture_trigger;
wire       oc1_match;
reg        oc1ref;

// Input capture logic for ch1_o
wire ic1_input = (ccmr1_cc1s == 2'b01) ? ti1_final :
                 (ccmr1_cc1s == 2'b10) ? ti2_final : 1'b0;

reg ic1_input_d;
wire ic1_edge;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ic1_input_d <= 1'b0;
    else if (srst)
        ic1_input_d <= 1'b0;
    else
        ic1_input_d <= ic1_input;
end

wire ic1_rise = ic1_input && !ic1_input_d;
wire ic1_fall = !ic1_input && ic1_input_d;

assign ic1_edge = ccer_cc1p ? ic1_fall : ic1_rise;

// Input capture prescaler
reg [2:0] ic1_psc_counter;  // BUG FIX #7: Expanded to 3 bits for /8 support

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ic1_psc_counter <= 3'b000;
    end else if (srst) begin
        ic1_psc_counter <= 3'b000;
    end else if (ic1_edge && ccer_cc1e && (ccmr1_cc1s != 2'b00)) begin
        ic1_psc_counter <= ic1_psc_counter + 3'b001;
    end
end

assign ic1_capture_trigger = ic1_edge && ccer_cc1e && (ccmr1_cc1s != 2'b00) &&
    ((ccmr1_ic1psc == 2'b00) ||  // Every event
     (ccmr1_ic1psc == 2'b01 && ic1_psc_counter[0] == 1'b1) ||  // /2
     (ccmr1_ic1psc == 2'b10 && ic1_psc_counter[1:0] == 2'b11) ||  // /4
     (ccmr1_ic1psc == 2'b11 && ic1_psc_counter == 3'b111));  // /8 (now works!)

// Output compare logic for ch1_o
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ccr1_shadow <= 32'hFFFFFFFF;  // BUG FIX #1: Prevent false match at reset
    else if (srst)
        ccr1_shadow <= 32'hFFFFFFFF;
    else if (update_event || !ccmr1_oc1pe)
        ccr1_shadow <= ccr1_reg;
end

assign oc1_match = (cnt_reg == ccr1_shadow);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        oc1ref <= 1'b0;
    end else if (srst) begin
        oc1ref <= 1'b0;
    end else if (ccer_cc1e && (ccmr1_cc1s == 2'b00)) begin
        case (ccmr1_oc1m)
            3'b000: oc1ref <= oc1ref;  // Frozen
            3'b001: oc1ref <= oc1_match ? 1'b1 : oc1ref;  // Active on match
            3'b010: oc1ref <= oc1_match ? 1'b0 : oc1ref;  // Inactive on match
            3'b011: oc1ref <= oc1_match ? ~oc1ref : oc1ref;  // Toggle
            3'b100: oc1ref <= 1'b0;  // Force inactive
            3'b101: oc1ref <= 1'b1;  // Force active
            3'b110: oc1ref <= (cnt_reg < ccr1_shadow) ? 1'b1 : 1'b0;  // PWM mode 1
            3'b111: oc1ref <= (cnt_reg < ccr1_shadow) ? 1'b0 : 1'b1;  // PWM mode 2
        endcase
    end
end

//------------------------------------------------------------------------------
// Capture/Compare Channel 2
//------------------------------------------------------------------------------
reg [31:0] ccr2_shadow;
wire       ic2_capture_trigger;
wire       oc2_match;
reg        oc2ref;

// Input capture logic for ch2_o
wire ic2_input = (ccmr1_cc2s == 2'b01) ? ti2_final :
                 (ccmr1_cc2s == 2'b10) ? ti1_final : 1'b0;

reg ic2_input_d;
wire ic2_edge;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ic2_input_d <= 1'b0;
    else if (srst)
        ic2_input_d <= 1'b0;
    else
        ic2_input_d <= ic2_input;
end

wire ic2_rise = ic2_input && !ic2_input_d;
wire ic2_fall = !ic2_input && ic2_input_d;

assign ic2_edge = ccer_cc2p ? ic2_fall : ic2_rise;

// Input capture prescaler
reg [2:0] ic2_psc_counter;  // BUG FIX #7: Expanded to 3 bits for /8 support

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ic2_psc_counter <= 3'b000;
    end else if (srst) begin
        ic2_psc_counter <= 3'b000;
    end else if (ic2_edge && ccer_cc2e && (ccmr1_cc2s != 2'b00)) begin
        ic2_psc_counter <= ic2_psc_counter + 3'b001;
    end
end

assign ic2_capture_trigger = ic2_edge && ccer_cc2e && (ccmr1_cc2s != 2'b00) &&
    ((ccmr1_ic2psc == 2'b00) ||  // Every event
     (ccmr1_ic2psc == 2'b01 && ic2_psc_counter[0] == 1'b1) ||  // /2
     (ccmr1_ic2psc == 2'b10 && ic2_psc_counter[1:0] == 2'b11) ||  // /4
     (ccmr1_ic2psc == 2'b11 && ic2_psc_counter == 3'b111));  // /8 (now works!)

// Output compare logic for ch2_o
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ccr2_shadow <= 32'hFFFFFFFF;  // BUG FIX #1: Prevent false match at reset
    else if (srst)
        ccr2_shadow <= 32'hFFFFFFFF;
    else if (update_event || !ccmr1_oc2pe)
        ccr2_shadow <= ccr2_reg;
end

assign oc2_match = (cnt_reg == ccr2_shadow);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        oc2ref <= 1'b0;
    end else if (srst) begin
        oc2ref <= 1'b0;
    end else if (ccer_cc2e && (ccmr1_cc2s == 2'b00)) begin
        case (ccmr1_oc2m)
            3'b000: oc2ref <= oc2ref;
            3'b001: oc2ref <= oc2_match ? 1'b1 : oc2ref;
            3'b010: oc2ref <= oc2_match ? 1'b0 : oc2ref;
            3'b011: oc2ref <= oc2_match ? ~oc2ref : oc2ref;
            3'b100: oc2ref <= 1'b0;
            3'b101: oc2ref <= 1'b1;
            3'b110: oc2ref <= (cnt_reg < ccr2_shadow) ? 1'b1 : 1'b0;
            3'b111: oc2ref <= (cnt_reg < ccr2_shadow) ? 1'b0 : 1'b1;
        endcase
    end
end

//------------------------------------------------------------------------------
// Capture/Compare Channel 3
//------------------------------------------------------------------------------
reg [31:0] ccr3_shadow;
wire       ic3_capture_trigger;
wire       oc3_match;
reg        oc3ref;

// Input capture logic for ch3_o (note: no TI3/TI4, uses ti1_i/ti2_i)
wire ic3_input = (ccmr2_cc3s == 2'b01) ? ti1_final :
                 (ccmr2_cc3s == 2'b10) ? ti2_final : 1'b0;

reg ic3_input_d;
wire ic3_edge;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ic3_input_d <= 1'b0;
    else if (srst)
        ic3_input_d <= 1'b0;
    else
        ic3_input_d <= ic3_input;
end

wire ic3_rise = ic3_input && !ic3_input_d;
wire ic3_fall = !ic3_input && ic3_input_d;

assign ic3_edge = ccer_cc3p ? ic3_fall : ic3_rise;

// Input capture prescaler
reg [2:0] ic3_psc_counter;  // BUG FIX #7: Expanded to 3 bits for /8 support

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ic3_psc_counter <= 3'b000;
    end else if (srst) begin
        ic3_psc_counter <= 3'b000;
    end else if (ic3_edge && ccer_cc3e && (ccmr2_cc3s != 2'b00)) begin
        ic3_psc_counter <= ic3_psc_counter + 3'b001;
    end
end

assign ic3_capture_trigger = ic3_edge && ccer_cc3e && (ccmr2_cc3s != 2'b00) &&
    ((ccmr2_ic3psc == 2'b00) ||  // Every event
     (ccmr2_ic3psc == 2'b01 && ic3_psc_counter[0] == 1'b1) ||  // /2
     (ccmr2_ic3psc == 2'b10 && ic3_psc_counter[1:0] == 2'b11) ||  // /4
     (ccmr2_ic3psc == 2'b11 && ic3_psc_counter == 3'b111));  // /8 (now works!)

// Output compare logic for ch3_o
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ccr3_shadow <= 32'hFFFFFFFF;  // BUG FIX #1: Prevent false match at reset
    else if (srst)
        ccr3_shadow <= 32'hFFFFFFFF;
    else if (update_event || !ccmr2_oc3pe)
        ccr3_shadow <= ccr3_reg;
end

assign oc3_match = (cnt_reg == ccr3_shadow);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        oc3ref <= 1'b0;
    end else if (srst) begin
        oc3ref <= 1'b0;
    end else if (ccer_cc3e && (ccmr2_cc3s == 2'b00)) begin
        case (ccmr2_oc3m)
            3'b000: oc3ref <= oc3ref;
            3'b001: oc3ref <= oc3_match ? 1'b1 : oc3ref;
            3'b010: oc3ref <= oc3_match ? 1'b0 : oc3ref;
            3'b011: oc3ref <= oc3_match ? ~oc3ref : oc3ref;
            3'b100: oc3ref <= 1'b0;
            3'b101: oc3ref <= 1'b1;
            3'b110: oc3ref <= (cnt_reg < ccr3_shadow) ? 1'b1 : 1'b0;
            3'b111: oc3ref <= (cnt_reg < ccr3_shadow) ? 1'b0 : 1'b1;
        endcase
    end
end

//------------------------------------------------------------------------------
// Capture/Compare Channel 4
//------------------------------------------------------------------------------
reg [31:0] ccr4_shadow;
wire       ic4_capture_trigger;
wire       oc4_match;
reg        oc4ref;

// Input capture logic for ch4_o (uses ti1_i/ti2_i)
wire ic4_input = (ccmr2_cc4s == 2'b01) ? ti2_final :
                 (ccmr2_cc4s == 2'b10) ? ti1_final : 1'b0;

reg ic4_input_d;
wire ic4_edge;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ic4_input_d <= 1'b0;
    else if (srst)
        ic4_input_d <= 1'b0;
    else
        ic4_input_d <= ic4_input;
end

wire ic4_rise = ic4_input && !ic4_input_d;
wire ic4_fall = !ic4_input && ic4_input_d;

assign ic4_edge = ccer_cc4p ? ic4_fall : ic4_rise;

// Input capture prescaler
reg [2:0] ic4_psc_counter;  // BUG FIX #7: Expanded to 3 bits for /8 support

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ic4_psc_counter <= 3'b000;
    end else if (srst) begin
        ic4_psc_counter <= 3'b000;
    end else if (ic4_edge && ccer_cc4e && (ccmr2_cc4s != 2'b00)) begin
        ic4_psc_counter <= ic4_psc_counter + 3'b001;
    end
end

assign ic4_capture_trigger = ic4_edge && ccer_cc4e && (ccmr2_cc4s != 2'b00) &&
    ((ccmr2_ic4psc == 2'b00) ||  // Every event
     (ccmr2_ic4psc == 2'b01 && ic4_psc_counter[0] == 1'b1) ||  // /2
     (ccmr2_ic4psc == 2'b10 && ic4_psc_counter[1:0] == 2'b11) ||  // /4
     (ccmr2_ic4psc == 2'b11 && ic4_psc_counter == 3'b111));  // /8 (now works!)

// Output compare logic for ch4_o
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ccr4_shadow <= 32'hFFFFFFFF;  // BUG FIX #1: Prevent false match at reset
    else if (srst)
        ccr4_shadow <= 32'hFFFFFFFF;
    else if (update_event || !ccmr2_oc4pe)
        ccr4_shadow <= ccr4_reg;
end

assign oc4_match = (cnt_reg == ccr4_shadow);

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        oc4ref <= 1'b0;
    end else if (srst) begin
        oc4ref <= 1'b0;
    end else if (ccer_cc4e && (ccmr2_cc4s == 2'b00)) begin
        case (ccmr2_oc4m)
            3'b000: oc4ref <= oc4ref;
            3'b001: oc4ref <= oc4_match ? 1'b1 : oc4ref;
            3'b010: oc4ref <= oc4_match ? 1'b0 : oc4ref;
            3'b011: oc4ref <= oc4_match ? ~oc4ref : oc4ref;
            3'b100: oc4ref <= 1'b0;
            3'b101: oc4ref <= 1'b1;
            3'b110: oc4ref <= (cnt_reg < ccr4_shadow) ? 1'b1 : 1'b0;
            3'b111: oc4ref <= (cnt_reg < ccr4_shadow) ? 1'b0 : 1'b1;
        endcase
    end
end

//------------------------------------------------------------------------------
// Dead-Time Generator
//------------------------------------------------------------------------------
reg [8:0] dt1_counter;
reg [8:0] dt1n_counter;
reg       ch1_out_raw;
reg       ch1n_out_raw;

reg oc1ref_d;
wire oc1_rising;
wire oc1_falling;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        oc1ref_d <= 1'b0;
    else if (srst)
        oc1ref_d <= 1'b0;
    else
        oc1ref_d <= oc1ref;
end

assign oc1_rising  = oc1ref && !oc1ref_d;
assign oc1_falling = !oc1ref && oc1ref_d;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        dt1_counter <= 9'h0;
        ch1_out_raw <= 1'b0;
    end else if (srst) begin
        dt1_counter <= 9'h0;
        ch1_out_raw <= 1'b0;
    end else begin
        // BUG FIX #4: Dead-time counter - load with DTG-1 for exact timing
        if (oc1_rising) begin
            dt1_counter <= (bdtr_dtg == 9'h0) ? 9'h0 : (bdtr_dtg - 9'h1);
        end else if (dt1_counter != 9'h0) begin
            dt1_counter <= dt1_counter - 9'h1;
        end

        // BUG FIX #4: Output control - allow turn-on when counter expires
        if (oc1_rising) begin
            ch1_out_raw <= (bdtr_dtg == 9'h0) ? oc1ref : 1'b0;  // If DTG=0, no delay
        end else if (dt1_counter == 9'h0) begin
            ch1_out_raw <= oc1ref;  // Follow reference when dead-time expired
        end
    end
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        dt1n_counter <= 9'h0;
        ch1n_out_raw <= 1'b0;
    end else if (srst) begin
        dt1n_counter <= 9'h0;
        ch1n_out_raw <= 1'b0;
    end else begin
        // BUG FIX #4: Dead-time counter - load with DTG-1 for exact timing
        if (oc1_falling) begin
            dt1n_counter <= (bdtr_dtg == 9'h0) ? 9'h0 : (bdtr_dtg - 9'h1);
        end else if (dt1n_counter != 9'h0) begin
            dt1n_counter <= dt1n_counter - 9'h1;
        end

        // BUG FIX #4: Output control - allow turn-on when counter expires
        if (oc1_falling) begin
            ch1n_out_raw <= (bdtr_dtg == 9'h0) ? !oc1ref : 1'b0;  // If DTG=0, no delay
        end else if (dt1n_counter == 9'h0) begin
            ch1n_out_raw <= !oc1ref;  // Follow inverted reference when dead-time expired
        end
    end
end

// Dead-time for ch2_o
reg [8:0] dt2_counter;
reg [8:0] dt2n_counter;
reg       ch2_out_raw;
reg       ch2n_out_raw;

reg oc2ref_d;
wire oc2_rising;
wire oc2_falling;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        oc2ref_d <= 1'b0;
    else if (srst)
        oc2ref_d <= 1'b0;
    else
        oc2ref_d <= oc2ref;
end

assign oc2_rising  = oc2ref && !oc2ref_d;
assign oc2_falling = !oc2ref && oc2ref_d;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        dt2_counter <= 9'h0;
        ch2_out_raw <= 1'b0;
    end else if (srst) begin
        dt2_counter <= 9'h0;
        ch2_out_raw <= 1'b0;
    end else begin
        // BUG FIX #4: Dead-time counter - load with DTG-1 for exact timing
        if (oc2_rising) begin
            dt2_counter <= (bdtr_dtg == 9'h0) ? 9'h0 : (bdtr_dtg - 9'h1);
        end else if (dt2_counter != 9'h0) begin
            dt2_counter <= dt2_counter - 9'h1;
        end

        // BUG FIX #4: Output control - allow turn-on when counter expires
        if (oc2_rising) begin
            ch2_out_raw <= (bdtr_dtg == 9'h0) ? oc2ref : 1'b0;
        end else if (dt2_counter == 9'h0) begin
            ch2_out_raw <= oc2ref;
        end
    end
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        dt2n_counter <= 9'h0;
        ch2n_out_raw <= 1'b0;
    end else if (srst) begin
        dt2n_counter <= 9'h0;
        ch2n_out_raw <= 1'b0;
    end else begin
        // BUG FIX #4: Dead-time counter - load with DTG-1 for exact timing
        if (oc2_falling) begin
            dt2n_counter <= (bdtr_dtg == 9'h0) ? 9'h0 : (bdtr_dtg - 9'h1);
        end else if (dt2n_counter != 9'h0) begin
            dt2n_counter <= dt2n_counter - 9'h1;
        end

        // BUG FIX #4: Output control - allow turn-on when counter expires
        if (oc2_falling) begin
            ch2n_out_raw <= (bdtr_dtg == 9'h0) ? !oc2ref : 1'b0;
        end else if (dt2n_counter == 9'h0) begin
            ch2n_out_raw <= !oc2ref;
        end
    end
end

// Dead-time for ch3_o
reg [8:0] dt3_counter;
reg [8:0] dt3n_counter;
reg       ch3_out_raw;
reg       ch3n_out_raw;

reg oc3ref_d;
wire oc3_rising;
wire oc3_falling;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        oc3ref_d <= 1'b0;
    else if (srst)
        oc3ref_d <= 1'b0;
    else
        oc3ref_d <= oc3ref;
end

assign oc3_rising  = oc3ref && !oc3ref_d;
assign oc3_falling = !oc3ref && oc3ref_d;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        dt3_counter <= 9'h0;
        ch3_out_raw <= 1'b0;
    end else if (srst) begin
        dt3_counter <= 9'h0;
        ch3_out_raw <= 1'b0;
    end else begin
        // BUG FIX #4: Dead-time counter - load with DTG-1 for exact timing
        if (oc3_rising) begin
            dt3_counter <= (bdtr_dtg == 9'h0) ? 9'h0 : (bdtr_dtg - 9'h1);
        end else if (dt3_counter != 9'h0) begin
            dt3_counter <= dt3_counter - 9'h1;
        end

        // BUG FIX #4: Output control - allow turn-on when counter expires
        if (oc3_rising) begin
            ch3_out_raw <= (bdtr_dtg == 9'h0) ? oc3ref : 1'b0;
        end else if (dt3_counter == 9'h0) begin
            ch3_out_raw <= oc3ref;
        end
    end
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        dt3n_counter <= 9'h0;
        ch3n_out_raw <= 1'b0;
    end else if (srst) begin
        dt3n_counter <= 9'h0;
        ch3n_out_raw <= 1'b0;
    end else begin
        // BUG FIX #4: Dead-time counter - load with DTG-1 for exact timing
        if (oc3_falling) begin
            dt3n_counter <= (bdtr_dtg == 9'h0) ? 9'h0 : (bdtr_dtg - 9'h1);
        end else if (dt3n_counter != 9'h0) begin
            dt3n_counter <= dt3n_counter - 9'h1;
        end

        // BUG FIX #4: Output control - allow turn-on when counter expires
        if (oc3_falling) begin
            ch3n_out_raw <= (bdtr_dtg == 9'h0) ? !oc3ref : 1'b0;
        end else if (dt3n_counter == 9'h0) begin
            ch3n_out_raw <= !oc3ref;
        end
    end
end

//------------------------------------------------------------------------------
// Break Input Logic
//------------------------------------------------------------------------------
wire break_active = bdtr_bke && (bkin_sync == bdtr_bkp);

// BUG FIX #5: Generate update event pulse for MOE auto-reenable
reg update_event_d;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        update_event_d <= 1'b0;
    else if (srst)
        update_event_d <= 1'b0;
    else
        update_event_d <= update_event;
end
wire update_event_pulse = update_event && !update_event_d;

// MOE (Main Output Enable) control
reg  moe_reg;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        moe_reg <= 1'b0;
    end else if (srst) begin
        moe_reg <= 1'b0;
    end else begin
        if (break_active) begin
            // BUG FIX #5: Disable MOE on break
            moe_reg <= 1'b0;
        end else if (bdtr_aoe && update_event_pulse && ris_bif) begin
            // BUG FIX #5: Auto re-enable MOE on update event only if AOE is set
            moe_reg <= 1'b1;
        end else if (apb_write && sel_bdtr) begin
            // Software control of MOE
            moe_reg <= PWDATA[15];
        end
    end
end

//------------------------------------------------------------------------------
// Output Assignment with Polarity Control
//------------------------------------------------------------------------------
assign ch1_o  = ccer_cc1e  ? (moe_reg && (ch1_out_raw  ^ ccer_cc1p))  : 1'b0;
assign ch1n_o = ccer_cc1ne ? (moe_reg && (ch1n_out_raw ^ ccer_cc1np)) : 1'b0;
assign ch2_o  = ccer_cc2e  ? (moe_reg && (ch2_out_raw  ^ ccer_cc2p))  : 1'b0;
assign ch2n_o = ccer_cc2ne ? (moe_reg && (ch2n_out_raw ^ ccer_cc2np)) : 1'b0;
assign ch3_o  = ccer_cc3e  ? (moe_reg && (ch3_out_raw  ^ ccer_cc3p))  : 1'b0;
assign ch3n_o = ccer_cc3ne ? (moe_reg && (ch3n_out_raw ^ ccer_cc3np)) : 1'b0;
assign ch4_o  = ccer_cc4e  ? (moe_reg && (oc4ref       ^ ccer_cc4p))  : 1'b0;

//------------------------------------------------------------------------------
// Master Output (trgo_o)
//------------------------------------------------------------------------------
assign trgo_o = oc1ref;  // Simplified: use OC1REF as trgo_o

//------------------------------------------------------------------------------
// Interrupt Logic
//------------------------------------------------------------------------------
// Update interrupt
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ris_uif <= 1'b0;
    end else if (srst) begin
        ris_uif <= 1'b0;
    end else begin
        // BUG FIX #6: Hardware set takes priority over software clear
        if (update_event)
            ris_uif <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[0])
            ris_uif <= 1'b0;
    end
end

// Capture/Compare interrupts
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ris_cc1if <= 1'b0;
        ris_cc2if <= 1'b0;
        ris_cc3if <= 1'b0;
        ris_cc4if <= 1'b0;
    end else if (srst) begin
        ris_cc1if <= 1'b0;
        ris_cc2if <= 1'b0;
        ris_cc3if <= 1'b0;
        ris_cc4if <= 1'b0;
    end else begin
        // BUG FIX #6: Hardware set takes priority over software clear
        // FIX: Interrupt flags should set when timer enabled, not when channel enabled
        // (Channel enable CCxE is for output pins, not for interrupt generation)

        // CC1IF
        if (cr_en && ((ccmr1_cc1s != 2'b00 && ic1_capture_trigger) ||
                      (ccmr1_cc1s == 2'b00 && oc1_match)))
            ris_cc1if <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[1])
            ris_cc1if <= 1'b0;

        // CC2IF
        if (cr_en && ((ccmr1_cc2s != 2'b00 && ic2_capture_trigger) ||
                      (ccmr1_cc2s == 2'b00 && oc2_match)))
            ris_cc2if <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[2])
            ris_cc2if <= 1'b0;

        // CC3IF
        if (cr_en && ((ccmr2_cc3s != 2'b00 && ic3_capture_trigger) ||
                      (ccmr2_cc3s == 2'b00 && oc3_match)))
            ris_cc3if <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[3])
            ris_cc3if <= 1'b0;

        // CC4IF
        if (cr_en && ((ccmr2_cc4s != 2'b00 && ic4_capture_trigger) ||
                      (ccmr2_cc4s == 2'b00 && oc4_match)))
            ris_cc4if <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[4])
            ris_cc4if <= 1'b0;
    end
end

// Trigger interrupt
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ris_tif <= 1'b0;
    end else if (srst) begin
        ris_tif <= 1'b0;
    end else begin
        // BUG FIX #6: Hardware set takes priority over software clear
        if (trigger_event && (smcr_sms != 3'b000))
            ris_tif <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[6])
            ris_tif <= 1'b0;
    end
end

// Break interrupt and error flag
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ris_bif <= 1'b0;
    end else if (srst) begin
        ris_bif <= 1'b0;
    end else begin
        // BUG FIX #6: Hardware set takes priority over software clear
        if (break_active)
            ris_bif <= 1'b1;
        else if (apb_write && sel_icr && PWDATA[7])
            ris_bif <= 1'b0;
    end
end

// Set BRKERR flag in ERRCR when break occurs
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        errcr_reg <= 2'h0;
    end else if (srst) begin
        errcr_reg <= 2'h0;
    end else begin
        // Set BRKERR (bit 1) when break active
        if (break_active && !errcr_reg[1])
            errcr_reg[1] <= 1'b1;
        // Clear on write-1-to-clear
        else if (apb_write && sel_errcr && PWDATA[1])
            errcr_reg[1] <= 1'b0;

        // Set ENCERR (bit 0) on invalid encoder transition
        if (enc_invalid && !errcr_reg[0])
            errcr_reg[0] <= 1'b1;
        else if (apb_write && sel_errcr && PWDATA[0])
            errcr_reg[0] <= 1'b0;
    end
end

// irq_o output
assign irq_o = |mis_reg;

//------------------------------------------------------------------------------
// APB3 Register Writes
//------------------------------------------------------------------------------
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        cr_reg    <= 16'h0;
        im_reg    <= 8'h0;
        psc_reg   <= 16'h0;
        arr_reg   <= 32'hFFFFFFFF;
        rcr_reg   <= 8'h0;
        ccr1_reg  <= 32'h0;
        ccr2_reg  <= 32'h0;
        ccr3_reg  <= 32'h0;
        ccr4_reg  <= 32'h0;
        bdtr_reg  <= 16'h0;
        smcr_reg  <= 16'h0;
        ccmr1_reg <= 16'h0;
        ccmr2_reg <= 16'h0;
        ccer_reg  <= 16'h0;
        // errcr_reg is handled by separate error flag logic block (lines 1470-1489)
        cc1of_flag <= 1'b0;
        cc2of_flag <= 1'b0;
        cc3of_flag <= 1'b0;
        cc4of_flag <= 1'b0;
    end else if (srst_req) begin
        cr_reg    <= 16'h0;
        im_reg    <= 8'h0;
        psc_reg   <= 16'h0;
        arr_reg   <= 32'hFFFFFFFF;
        rcr_reg   <= 8'h0;
        ccr1_reg  <= 32'h0;
        ccr2_reg  <= 32'h0;
        ccr3_reg  <= 32'h0;
        ccr4_reg  <= 32'h0;
        bdtr_reg  <= 16'h0;
        smcr_reg  <= 16'h0;
        ccmr1_reg <= 16'h0;
        ccmr2_reg <= 16'h0;
        ccer_reg  <= 16'h0;
        // errcr_reg is handled by separate error flag logic block (lines 1470-1489)
        cc1of_flag <= 1'b0;
        cc2of_flag <= 1'b0;
        cc3of_flag <= 1'b0;
        cc4of_flag <= 1'b0;
    end else begin
        // Self-clearing SRST bit
        if (cr_reg[1])
            cr_reg[1] <= 1'b0;

        if (apb_write) begin
            case (1'b1)
                sel_cr:    cr_reg    <= PWDATA[15:0] & CR_WRITABLE_MASK;
                sel_im:    im_reg    <= PWDATA[7:0];
                sel_psc:   psc_reg   <= PWDATA[15:0];
                sel_arr:   arr_reg   <= PWDATA;
                sel_rcr:   rcr_reg   <= PWDATA[7:0];
                sel_bdtr:  bdtr_reg  <= PWDATA[15:0];
                sel_smcr:  smcr_reg  <= PWDATA[15:0];
                sel_ccmr1: ccmr1_reg <= PWDATA[15:0];
                sel_ccmr2: ccmr2_reg <= PWDATA[15:0];
                sel_ccer:  ccer_reg  <= PWDATA[15:0];
                // ERRCR handled in separate always block with break flag logic
                default: ;
            endcase
        end

        // One-pulse mode: stop on update event
        if (one_pulse_mode && update_event)
            cr_reg[0] <= 1'b0;

        // CCR register writes (in compare mode) or capture updates (in capture mode)
        if (apb_write && sel_ccr1 && (ccmr1_cc1s == 2'b00))
            ccr1_reg <= PWDATA;
        else if (ic1_capture_trigger) begin
            if (ris_cc1if)
                cc1of_flag <= 1'b1;
            ccr1_reg <= cnt_reg;
        end

        if (apb_write && sel_ccr2 && (ccmr1_cc2s == 2'b00))
            ccr2_reg <= PWDATA;
        else if (ic2_capture_trigger) begin
            if (ris_cc2if)
                cc2of_flag <= 1'b1;
            ccr2_reg <= cnt_reg;
        end

        if (apb_write && sel_ccr3 && (ccmr2_cc3s == 2'b00))
            ccr3_reg <= PWDATA;
        else if (ic3_capture_trigger) begin
            if (ris_cc3if)
                cc3of_flag <= 1'b1;
            ccr3_reg <= cnt_reg;
        end

        if (apb_write && sel_ccr4 && (ccmr2_cc4s == 2'b00))
            ccr4_reg <= PWDATA;
        else if (ic4_capture_trigger) begin
            if (ris_cc4if)
                cc4of_flag <= 1'b1;
            ccr4_reg <= cnt_reg;
        end

        // Clear overcapture flags
        if (apb_write && sel_icr) begin
            if (PWDATA[9])  cc1of_flag <= 1'b0;
            if (PWDATA[10]) cc2of_flag <= 1'b0;
            if (PWDATA[11]) cc3of_flag <= 1'b0;
            if (PWDATA[12]) cc4of_flag <= 1'b0;
        end
    end
end

//------------------------------------------------------------------------------
// APB3 Read Data Mux
//------------------------------------------------------------------------------
reg [31:0] prdata_reg;

always @(*) begin
    prdata_reg = 32'h0;
    case (1'b1)
        sel_cr:      prdata_reg = {16'h0, cr_reg};
        sel_sr:      prdata_reg = {19'h0, cc4of_flag, cc3of_flag, cc2of_flag, cc1of_flag, 3'b000,
                                   update_event, 1'b0, (errcr_reg != 2'h0), cr_en, 2'b00};
        sel_im:      prdata_reg = {24'h0, im_reg};
        sel_ris:     prdata_reg = {24'h0, ris_reg};
        sel_mis:     prdata_reg = {24'h0, mis_reg};
        sel_icr:     prdata_reg = 32'h0;
        sel_dmacr:   prdata_reg = 32'h0;
        sel_errcr:   prdata_reg = {30'h0, errcr_reg};
        sel_cnt:     prdata_reg = cnt_reg;
        sel_psc:     prdata_reg = {16'h0, psc_reg};
        sel_arr:     prdata_reg = arr_reg;
        sel_rcr:     prdata_reg = {24'h0, rcr_reg};
        sel_ccr1:    prdata_reg = ccr1_reg;
        sel_ccr2:    prdata_reg = ccr2_reg;
        sel_ccr3:    prdata_reg = ccr3_reg;
        sel_ccr4:    prdata_reg = ccr4_reg;
        sel_bdtr:    prdata_reg = {16'h0, moe_reg, bdtr_reg[14:0]};  // Return actual MOE state
        sel_smcr:    prdata_reg = {16'h0, smcr_reg};
        sel_ccmr1:   prdata_reg = {16'h0, ccmr1_reg};
        sel_ccmr2:   prdata_reg = {16'h0, ccmr2_reg};
        sel_ccer:    prdata_reg = {16'h0, ccer_reg};
        sel_egr:     prdata_reg = 32'h0;
        sel_feature: prdata_reg = FEATURE_VALUE;
        sel_id:      prdata_reg = ID_VALUE;
        default:     prdata_reg = 32'h0;
    endcase
end

assign PRDATA  = prdata_reg;
assign PREADY  = 1'b1;
assign PSLVERR = 1'b0;

endmodule

`default_nettype wire
