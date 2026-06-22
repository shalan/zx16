// ===============================================================================
// nc_ticker - Tick Generator Module
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
// Description: Tick Generator
//              - Generates periodic tick pulse
//              - Period = clk_div + 1 clock cycles when enabled
//              - Output is registered (1 cycle latency)
// ===============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_ticker #(parameter W = 8) (
    input   wire            clk,
    input   wire            rst_n,
    input   wire            en,
    input   wire [W-1:0]    clk_div,
    output  wire            tick
);

    reg [W-1:0] counter;
    wire        counter_is_zero = (counter == {W{1'b0}});
    wire        tick_w;
    reg         tick_reg;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            counter <= {W{1'b0}};
        else if (en)
            if (counter_is_zero)
                counter <= clk_div;
            else
                counter <= counter - 1'b1;

    assign tick_w = (clk_div == {W{1'b0}}) ? 1'b1 : counter_is_zero;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            tick_reg <= 1'b0;
        else if (en)
            tick_reg <= tick_w;
        else
            tick_reg <= 1'b0;

    assign tick = tick_reg;

endmodule

`default_nettype wire
