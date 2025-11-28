 // Copyright lowRISC contributors.
 // Licensed under the Apache License, Version 2.0, see LICENSE for details.
 // SPDX-License-Identifier: Apache-2.0
 //
 // Simplified generic flop implementation for FPGA builds.
 //
 // This replaces the auto-generated prim_flop for environments where
 // FuseSoC/primgen are not available. It is compatible with existing
 // lowRISC code by matching the expected interface, but avoids any
 // dependency on assertion / flop macros so synthesis tools see a
 // plain SystemVerilog always_ff flop.

 module prim_flop #(
   parameter int               Width      = 1,
   parameter logic [Width-1:0] ResetValue = '0
 ) (
   input                    clk_i,
   input                    rst_ni,
   input        [Width-1:0] d_i,
   output logic [Width-1:0] q_o
 );

   // Simple async-reset flop array.
   always_ff @(posedge clk_i or negedge rst_ni) begin
     if (!rst_ni) begin
       q_o <= ResetValue;
     end else begin
       q_o <= d_i;
     end
   end

 endmodule : prim_flop