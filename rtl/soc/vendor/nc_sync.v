// ===============================================================================
// nc_sync - Synchronizer Module
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
// Description: Brute-force Synchronizer
//              - Parameterizable number of stages (default: 2)
//              - Asynchronous reset to known state
// ===============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_sync #(parameter NUM_STAGES = 2) (
    input   wire    clk,
    input   wire    rst_n,
    input   wire    in,
    output  wire    out
);

    reg [NUM_STAGES-1:0] sync;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            sync <= {NUM_STAGES{1'b0}};
        else
            sync <= {sync[NUM_STAGES-2:0], in};

    assign out = sync[NUM_STAGES-1];

endmodule

`default_nettype wire
