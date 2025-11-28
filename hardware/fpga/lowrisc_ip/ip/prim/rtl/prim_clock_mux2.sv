// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simplified clock mux for FPGA builds.
//
// This provides a compatible replacement for the lowRISC prim_clock_mux2
// used by the PULP riscv-dbg dmi_cdc module, without pulling in the full
// prim_clock_gp_mux2 / prim_clock_gating hierarchy.
//
// For this Ara FPGA integration it is only used to mux reset-like signals
// (combined_rstn vs test_rst_ni), so a simple combinational mux is
// sufficient.

module prim_clock_mux2 #(
  // Kept for interface compatibility; ignored in this simplified FPGA
  // implementation.
  parameter bit NoFpgaBufG = 1'b0
) (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic sel_i,
  output logic clk_o
);

  // Simple 2:1 mux. In the original implementation this would be a
  // glitch-protected clock mux; here we only use it for reset/control
  // signals in the debug CDC path, where a combinational mux is adequate.
  always_comb begin
    clk_o = sel_i ? clk1_i : clk0_i;
  end

endmodule : prim_clock_mux2