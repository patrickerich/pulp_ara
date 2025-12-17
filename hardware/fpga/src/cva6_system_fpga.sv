// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Description:
// CVA6-only "system" for FPGA.
// This is the stripped-down counterpart of ara_system_fpga:
// - Instantiates CVA6 only (no Ara).
// - Provides a minimal "null accelerator" response on the CVXIF/accelerator port.
// - Exposes a single AXI master port towards the SoC fabric.

module cva6_system import axi_pkg::*; import ara_pkg::*; #(
    // Ariane/CVA6 configuration
    parameter config_pkg::cva6_cfg_t            CVA6Cfg            = cva6_config_pkg::cva6_cfg,
    // CVA6-related parameters
    parameter type                              exception_t        = logic,
    parameter type                              accelerator_req_t  = logic,
    parameter type                              accelerator_resp_t = logic,
    parameter type                              acc_mmu_req_t      = logic,
    parameter type                              acc_mmu_resp_t     = logic,
    parameter type                              cva6_to_acc_t      = logic,
    parameter type                              acc_to_cva6_t      = logic,
    // AXI Interface
    parameter int unsigned                      AxiAddrWidth       = 64,
    parameter int unsigned                      AxiIdWidth         = 6,
    parameter int unsigned                      AxiNarrowDataWidth = 64,
    parameter int unsigned                      AxiWideDataWidth   = 64,
    parameter type                              ariane_axi_ar_t    = logic,
    parameter type                              ariane_axi_r_t     = logic,
    parameter type                              ariane_axi_aw_t    = logic,
    parameter type                              ariane_axi_w_t     = logic,
    parameter type                              ariane_axi_b_t     = logic,
    parameter type                              ariane_axi_req_t   = logic,
    parameter type                              ariane_axi_resp_t  = logic,
    parameter type                              system_axi_ar_t    = logic,
    parameter type                              system_axi_r_t     = logic,
    parameter type                              system_axi_aw_t    = logic,
    parameter type                              system_axi_w_t     = logic,
    parameter type                              system_axi_b_t     = logic,
    parameter type                              system_axi_req_t   = logic,
    parameter type                              system_axi_resp_t  = logic
  ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic             [63:0] boot_addr_i,
    input                     [2:0] hart_id_i,
    // Scan chain
    input  logic                    scan_enable_i,
    input  logic                    scan_data_i,
    output logic                    scan_data_o,
    // Debug request from external Debug Module (dm_top)
    input  logic                    debug_req_i,
    // AXI Interface
    output system_axi_req_t         axi_req_o,
    input  system_axi_resp_t        axi_resp_i
  );

  `include "axi/assign.svh"
  `include "axi/typedef.svh"

  /////////////////
  // CVA6 Core   //
  /////////////////

  ariane_axi_req_t  ariane_narrow_axi_req;
  ariane_axi_resp_t ariane_narrow_axi_resp;

  // Null-accelerator stubs
  cva6_to_acc_t   acc_req;
  acc_to_cva6_t   acc_resp_stub;

  // Provide a safe default response on the accelerator/CVXIF port:
  // - Always accept requests (req_ready=1).
  // - If a request ever arrives (e.g. misconfigured build enabling RVV/CVXIF), respond
  //   immediately with an illegal instruction exception to avoid deadlock.
  always_comb begin : gen_null_accel
    acc_resp_stub = '0;

    // Always accept
    acc_resp_stub.acc_resp.req_ready = 1'b1;

    // If a request arrives, respond immediately (1-cycle response path).
    acc_resp_stub.acc_resp.resp_valid      = acc_req.acc_req.req_valid;
    acc_resp_stub.acc_resp.trans_id        = acc_req.acc_req.trans_id;
    acc_resp_stub.acc_resp.exception.valid = acc_req.acc_req.req_valid;
    acc_resp_stub.acc_resp.exception.cause = riscv::ILLEGAL_INSTR;
    // Provide the faulting instruction as tval where possible.
    acc_resp_stub.acc_resp.exception.tval  = riscv::instruction_t'(acc_req.acc_req.insn);

    // No memory completions / flags from this stub
    acc_resp_stub.acc_resp.load_complete  = 1'b0;
    acc_resp_stub.acc_resp.store_complete = 1'b0;
    acc_resp_stub.acc_resp.store_pending  = 1'b0;
    acc_resp_stub.acc_resp.fflags_valid   = 1'b0;
    acc_resp_stub.acc_resp.fflags         = '0;
    acc_resp_stub.acc_resp.result         = '0;

    // No MMU requests from stub
    acc_resp_stub.acc_mmu_req = '0;
  end

  // Instantiate CVA6
  // NOTE: We keep the accelerator port types wired, but we do not instantiate Ara.
  cva6 #(
    .CVA6Cfg           (CVA6Cfg           ),
    .cvxif_req_t       (cva6_to_acc_t     ),
    .cvxif_resp_t      (acc_to_cva6_t     ),
    .axi_ar_chan_t     (ariane_axi_ar_t   ),
    .axi_aw_chan_t     (ariane_axi_aw_t   ),
    .axi_w_chan_t      (ariane_axi_w_t    ),
    .b_chan_t          (ariane_axi_b_t    ),
    .r_chan_t          (ariane_axi_r_t    ),
    .noc_req_t         (ariane_axi_req_t  ),
    .noc_resp_t        (ariane_axi_resp_t ),
    .accelerator_req_t (accelerator_req_t ),
    .accelerator_resp_t(accelerator_resp_t),
    .acc_mmu_req_t     (acc_mmu_req_t     ),
    .acc_mmu_resp_t    (acc_mmu_resp_t    )
  ) i_cva6 (
    .clk_i            (clk_i                   ),
    .rst_ni           (rst_ni                  ),
    .boot_addr_i      (boot_addr_i             ),
    .hart_id_i        ({61'b0, hart_id_i}      ),
    .irq_i            ('0                      ),
    .ipi_i            ('0                      ),
    .time_irq_i       ('0                      ),
    .debug_req_i      (debug_req_i             ),
    .clic_irq_valid_i ('0                      ),
    .clic_irq_id_i    ('0                      ),
    .clic_irq_level_i ('0                      ),
    .clic_irq_priv_i  (riscv::priv_lvl_t'(2'b0)),
    .clic_irq_shv_i   ('0                      ),
    .clic_irq_ready_o (/* unused */            ),
    .clic_kill_req_i  ('0                      ),
    .clic_kill_ack_o  (/* unused */            ),
    .rvfi_probes_o    (/* unused */            ),

    // Accelerator / CVXIF ports (stubbed)
    .cvxif_req_o      (acc_req                 ),
    .cvxif_resp_i     (acc_resp_stub           ),

    // AXI NoC port
    .noc_req_o        (ariane_narrow_axi_req   ),
    .noc_resp_i       (ariane_narrow_axi_resp  )
  );

  //////////////////////
  // AXI width bridge //
  //////////////////////

  // Convert CVA6 narrow AXI (64-bit) to the SoC-wide AXI bus width (AxiWideDataWidth).
  // In the default FPGA configuration used in this repo, AxiWideDataWidth == 64, so
  // this typically becomes a pass-through.
  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiNarrowDataWidth),
    .AxiMstPortDataWidth(AxiWideDataWidth  ),
    .AxiAddrWidth       (AxiAddrWidth      ),
    .AxiIdWidth         (AxiIdWidth        ),
    .AxiMaxReads        (2                 ),
    .ar_chan_t          (ariane_axi_ar_t   ),
    .mst_r_chan_t       (system_axi_r_t    ),
    .slv_r_chan_t       (ariane_axi_r_t    ),
    .aw_chan_t          (ariane_axi_aw_t   ),
    .b_chan_t           (ariane_axi_b_t    ),
    .mst_w_chan_t       (system_axi_w_t    ),
    .slv_w_chan_t       (ariane_axi_w_t    ),
    .axi_mst_req_t      (system_axi_req_t  ),
    .axi_mst_resp_t     (system_axi_resp_t ),
    .axi_slv_req_t      (ariane_axi_req_t  ),
    .axi_slv_resp_t     (ariane_axi_resp_t )
  ) i_cva6_axi_dwc (
    .clk_i      (clk_i               ),
    .rst_ni     (rst_ni              ),
    .slv_req_i  (ariane_narrow_axi_req),
    .slv_resp_o (ariane_narrow_axi_resp),
    .mst_req_o  (axi_req_o           ),
    .mst_resp_i (axi_resp_i          )
  );

  // Scan chain not used
  assign scan_data_o = 1'b0;

endmodule : cva6_system