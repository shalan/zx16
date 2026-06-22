// ===============================================================================
// nc_glitch_filter - Glitch Filter Module
// ===============================================================================
// Copyright (c) 2021 Mohamed Shalan <shalan@nativechips.ai>
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Description: Glitch Filter
//              - Filters input signal using shift register
//              - Output changes only when all samples are identical
//              - Sample rate controlled by CLKDIV parameter
//
// Dependencies: Requires nc_ticker.v
// ===============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_glitch_filter #(parameter N = 8, CLKDIV = 8'd1) (
    input   wire    clk,
    input   wire    rst_n,
    input   wire    in,
    input   wire    en,
    output  reg     out
);

    reg [N-1:0] shifter;
    wire        tick;

    nc_ticker #(.W(8)) ticker (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .clk_div(CLKDIV),
        .tick(tick)
    );

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            shifter <= {N{1'b0}};
        else if (tick)
            shifter <= {shifter[N-2:0], in};

    wire all_ones  = &shifter;
    wire all_zeros = ~|shifter;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            out <= 1'b0;
        else if (all_ones)
            out <= 1'b1;
        else if (all_zeros)
            out <= 1'b0;

endmodule

`default_nettype wire
