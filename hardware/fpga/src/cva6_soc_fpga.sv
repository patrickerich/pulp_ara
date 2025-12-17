// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Description:
// CVA6-only SoC for FPGA (stripped-down Ara SoC).
// This is the counterpart of [ara_soc_fpga](hardware/fpga/src/ara_soc_fpga.sv:9) but without Ara.
//
// Key characteristics:
// - CVA6-only "system" (see [cva6_system_fpga](hardware/fpga/src/cva6_system_fpga.sv:1)).
// - Same SoC-level fabric style: AXI xbar + BRAM-backed L2 ("DRAM") + UART + CTRL regs.
// - Same riscv-dbg integration style:
//   * Debug memory window at DebugBase=0x0, exposed via dm_device_*
//   * SBA master port implemented as a simple AXI master on xbar port 1
//
// NOTE: We keep naming/ports aligned with [ara_soc_fpga](hardware/fpga/src/ara_soc_fpga.sv:9)
// so the top-level wrapper can be swapped with minimal changes.

module cva6_soc import axi_pkg::*; import ara_pkg::*; #(
    // AXI Interface
    parameter  int unsigned AxiDataWidth = 64,
    parameter  int unsigned AxiAddrWidth = 64,
    parameter  int unsigned AxiUserWidth = 1,
    parameter  int unsigned AxiIdWidth   = 5,
    // AXI Resp Delay [ps] for gate-level simulation
    parameter  int unsigned AxiRespDelay = 200,
    // Main memory (BRAM-backed "DRAM" region behind the SoC xbar)
    parameter  int unsigned L2NumWords   = 2**17, // 512KiB @ 64b = 64KiB words, but allow override

    // Number of SoC-level AXI initiators connected to the SoC crossbar:
    //   - Port 0 : cva6_system (CVA6 only)
    //   - Port 1 : RISC-V Debug Module SBA master
    localparam int unsigned  NrAXIMastersSoc = 2,

    // ID widths:
    // - AxiSocIdWidth: ID width at the SoC crossbar slave ports (one per initiator).
    // - AxiPeriphIdWidth: ID width on the peripheral side of the xbar (extended with log2(#masters)).
    localparam int unsigned  AxiSocIdWidth    = AxiIdWidth,
    localparam int unsigned  AxiPeriphIdWidth = AxiSocIdWidth + $clog2(NrAXIMastersSoc),

    // Dependant parameters. DO NOT CHANGE!
    localparam type         axi_data_t   = logic [AxiDataWidth-1:0],
    localparam type         axi_strb_t   = logic [AxiDataWidth/8-1:0],
    localparam type         axi_addr_t   = logic [AxiAddrWidth-1:0],
    localparam type         axi_user_t   = logic [AxiUserWidth-1:0],
    // System-level AXI ID type (output of cva6_system / DM SBA, slave side of SoC crossbar).
    localparam type         axi_id_t     = logic [AxiSocIdWidth-1:0]
  ) (
    input  logic        clk_i,
    // SoC-level reset: resets fabric, L2 SRAM, peripherals, and debug window.
    // This is driven by the board/PLL reset and is NOT gated by ndmreset.
    input  logic        rst_ni,
    // Core-level reset: used only for the CVA6 core complex (cva6_system).
    // At the FPGA top, this is typically gated by ndmreset so that SBA can
    // keep accessing memory while the core is held in reset.
    input  logic        core_rst_ni_i,

    output logic [63:0] exit_o,
    output logic [63:0] hw_cnt_en_o,

    // Debug request from external Debug Module (dm_top)
    input  logic        debug_req_i,

    // Scan chain
    input  logic        scan_enable_i,
    input  logic        scan_data_i,
    output logic        scan_data_o,

    // UART APB interface (to be connected to an APB UART in the top-level wrapper)
    output logic        uart_penable_o,
    output logic        uart_pwrite_o,
    output logic [31:0] uart_paddr_o,
    output logic        uart_psel_o,
    output logic [31:0] uart_pwdata_o,
    input  logic [31:0] uart_prdata_i,
    input  logic        uart_pready_i,
    input  logic        uart_pslverr_i,

    // Debug Module memory window (connected to external DM)
    output logic                      dm_device_req_o,
    output logic                      dm_device_we_o,
    output logic [AxiAddrWidth-1:0]   dm_device_addr_o,
    output logic [AxiDataWidth/8-1:0] dm_device_be_o,
    output logic [AxiDataWidth-1:0]   dm_device_wdata_o,
    input  logic [AxiDataWidth-1:0]   dm_device_rdata_i,

    // System Bus Access (SBA) host bus from external Debug Module
    input  logic                      sba_req_i,
    input  logic                      sba_we_i,
    input  logic [AxiAddrWidth-1:0]   sba_addr_i,
    input  logic [AxiDataWidth/8-1:0] sba_be_i,
    input  logic [AxiDataWidth-1:0]   sba_wdata_i,
    output logic                      sba_gnt_o,
    output logic                      sba_r_valid_o,
    output logic [AxiDataWidth-1:0]   sba_r_rdata_o
  );

  `include "axi/assign.svh"
  `include "axi/typedef.svh"
  `include "common_cells/registers.svh"
  `include "apb/typedef.svh"
  // Use the same CVA6 interface typedef macros as ara_soc_fpga.
  `include "ara/intf_typedef.svh"

  //////////////////////
  //  Memory Regions  //
  //////////////////////

  // Number of SoC-level AXI initiators connected to the SoC crossbar is provided
  // as a localparam in the module parameter list: NrAXIMastersSoc.

  typedef enum int unsigned {
    L2MEM = 0,
    UART  = 1,
    CTRL  = 2,
    DEBUG = 3
  } axi_slaves_e;
  localparam int unsigned NrAXISlaves = DEBUG + 1;

  // Memory Map
  localparam logic [63:0] DRAMLength  = 64'h4000_0000; // 1GiB decode window (aliases in BRAM backing)
  localparam logic [63:0] UARTLength  = 64'h0000_1000;
  localparam logic [63:0] CTRLLength  = 64'h0000_1000;
  localparam logic [63:0] DebugLength = 64'h0000_1000;

  typedef enum logic [63:0] {
    DRAMBase  = 64'h8000_0000,
    UARTBase  = 64'hC000_0000,
    CTRLBase  = 64'hD000_0000,
    // Place Debug window at 0x0000_0000 to match upstream ariane_soc/ariane_xilinx
    DebugBase = 64'h0000_0000
  } soc_bus_start_e;

  ///////////
  //  AXI  //
  ///////////

  // CVA6 NoC port data width
  localparam int unsigned AxiNarrowDataWidth = 64;
  localparam int unsigned AxiNarrowStrbWidth = AxiNarrowDataWidth / 8;

  // ID slicing strategy (kept compatible with ara_soc_fpga approach):
  // - AxiSocIdWidth is what the SoC crossbar expects at its slave ports (one per initiator).
  // - AxiPeriphIdWidth is what peripherals see (extends with log2(#masters) for uniqueness).
  // Provided via module parameter localparams AxiSocIdWidth/AxiPeriphIdWidth.

  // Internal types
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t;
  typedef logic [AxiNarrowStrbWidth-1:0] axi_narrow_strb_t;

  // Peripheral-side IDs (crossbar master ports and peripherals)
  typedef logic [AxiPeriphIdWidth-1:0] axi_soc_id_t;

  // AXI Typedefs
  // - "system_*": SoC xbar slave-port view (one per initiator, ID width = AxiSocIdWidth)
  // - "soc_*":    SoC xbar master/peripheral view (ID width = AxiPeriphIdWidth)
  // - "ariane_*": Narrow AXI view used by CVA6-style wrappers (needed as typedef parameters)
  `AXI_TYPEDEF_ALL(system,     axi_addr_t, axi_id_t,     axi_data_t,        axi_strb_t,        axi_user_t)
  `AXI_TYPEDEF_ALL(ariane_axi, axi_addr_t, axi_id_t,     axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(soc_wide,   axi_addr_t, axi_soc_id_t, axi_data_t,        axi_strb_t,        axi_user_t)
  `AXI_TYPEDEF_ALL(soc_narrow, axi_addr_t, axi_soc_id_t, axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(soc_narrow_lite, axi_addr_t, axi_narrow_data_t, axi_narrow_strb_t)

  // Buses
  system_req_t  system_axi_req;
  system_resp_t system_axi_resp;

  // SoC-level AXI initiator ports towards the xbar
  system_req_t  [NrAXIMastersSoc-1:0] soc_axi_req;
  system_resp_t [NrAXIMastersSoc-1:0] soc_axi_resp;

  // Peripheral-side AXI ports from the xbar
  soc_wide_req_t    [NrAXISlaves-1:0] periph_wide_axi_req;
  soc_wide_resp_t   [NrAXISlaves-1:0] periph_wide_axi_resp;
  soc_narrow_req_t  [NrAXISlaves-1:0] periph_narrow_axi_req;
  soc_narrow_resp_t [NrAXISlaves-1:0] periph_narrow_axi_resp;

  ////////////////
  //  Crossbar  //
  ////////////////

  localparam axi_pkg::xbar_cfg_t XBarCfg = '{
    NoSlvPorts        : NrAXIMastersSoc,
    NoMstPorts        : NrAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::CUT_MST_PORTS,
    PipelineStages    : 0,
    AxiIdWidthSlvPorts: AxiSocIdWidth,
    AxiIdUsedSlvPorts : AxiSocIdWidth,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiDataWidth,
    NoAddrRules       : NrAXISlaves,
    default           : '0
  };

  axi_pkg::xbar_rule_64_t [NrAXISlaves-1:0] routing_rules;
  assign routing_rules = '{
    '{idx: DEBUG, start_addr: DebugBase, end_addr: DebugBase + DebugLength},
    '{idx: CTRL,  start_addr: CTRLBase,  end_addr: CTRLBase + CTRLLength},
    '{idx: UART,  start_addr: UARTBase,  end_addr: UARTBase + UARTLength},
    '{idx: L2MEM, start_addr: DRAMBase,  end_addr: DRAMBase + DRAMLength}
  };

  axi_xbar #(
    .Cfg          (XBarCfg                ),
    .slv_aw_chan_t(system_aw_chan_t       ),
    .mst_aw_chan_t(soc_wide_aw_chan_t     ),
    .w_chan_t     (system_w_chan_t        ),
    .slv_b_chan_t (system_b_chan_t        ),
    .mst_b_chan_t (soc_wide_b_chan_t      ),
    .slv_ar_chan_t(system_ar_chan_t       ),
    .mst_ar_chan_t(soc_wide_ar_chan_t     ),
    .slv_r_chan_t (system_r_chan_t        ),
    .mst_r_chan_t (soc_wide_r_chan_t      ),
    .slv_req_t    (system_req_t           ),
    .slv_resp_t   (system_resp_t          ),
    .mst_req_t    (soc_wide_req_t         ),
    .mst_resp_t   (soc_wide_resp_t        ),
    .rule_t       (axi_pkg::xbar_rule_64_t)
  ) i_soc_xbar (
    .clk_i                (clk_i               ),
    .rst_ni               (rst_ni              ),
    .test_i               (1'b0                ),
    .slv_ports_req_i      (soc_axi_req         ),
    .slv_ports_resp_o     (soc_axi_resp        ),
    .mst_ports_req_o      (periph_wide_axi_req ),
    .mst_ports_resp_i     (periph_wide_axi_resp),
    .addr_map_i           (routing_rules       ),
    .en_default_mst_port_i('0                  ),
    .default_mst_port_i   ('0                  )
  );

  // Connect CVA6 system AXI master to SoC crossbar slave port 0
  assign soc_axi_req[0]  = system_axi_req;
  assign system_axi_resp = soc_axi_resp[0];

  // soc_axi_req[1] / soc_axi_resp[1] are driven by the SBA master (below).

  //////////
  //  L2  //
  //////////

  // L2 memory does not support atomics
  soc_wide_req_t  l2mem_wide_axi_req_wo_atomics;
  soc_wide_resp_t l2mem_wide_axi_resp_wo_atomics;
  axi_atop_filter #(
    .AxiIdWidth     (AxiPeriphIdWidth  ),
    .AxiMaxWriteTxns(4                 ),
    .axi_req_t      (soc_wide_req_t    ),
    .axi_resp_t     (soc_wide_resp_t   )
  ) i_l2mem_atop_filter (
    .clk_i     (clk_i                         ),
    .rst_ni    (rst_ni                        ),
    .slv_req_i (periph_wide_axi_req[L2MEM]    ),
    .slv_resp_o(periph_wide_axi_resp[L2MEM]   ),
    .mst_req_o (l2mem_wide_axi_req_wo_atomics ),
    .mst_resp_i(l2mem_wide_axi_resp_wo_atomics)
  );

  // L2 SRAM (BRAM-backed)
  logic                      l2_req;
  logic                      l2_we;
  logic [AxiAddrWidth-1:0]   l2_addr;
  logic [AxiDataWidth/8-1:0] l2_be;
  logic [AxiDataWidth-1:0]   l2_wdata;
  logic [AxiDataWidth-1:0]   l2_rdata;
  logic                      l2_rvalid;

  axi_to_mem #(
    .AddrWidth (AxiAddrWidth     ),
    .DataWidth (AxiDataWidth     ),
    .IdWidth   (AxiPeriphIdWidth ),
    .NumBanks  (1                ),
    .axi_req_t (soc_wide_req_t   ),
    .axi_resp_t(soc_wide_resp_t  )
  ) i_axi_to_mem (
    .clk_i       (clk_i                         ),
    .rst_ni      (rst_ni                        ),
    .axi_req_i   (l2mem_wide_axi_req_wo_atomics ),
    .axi_resp_o  (l2mem_wide_axi_resp_wo_atomics),
    .mem_req_o   (l2_req                        ),
    .mem_gnt_i   (l2_req                        ), // always available
    .mem_we_o    (l2_we                         ),
    .mem_addr_o  (l2_addr                       ),
    .mem_strb_o  (l2_be                         ),
    .mem_wdata_o (l2_wdata                      ),
    .mem_rdata_i (l2_rdata                      ),
    .mem_rvalid_i(l2_rvalid                     ),
    .mem_atop_o  (/* unused */                  ),
    .busy_o      (/* unused */                  )
  );

`ifndef SPYGLASS
  localparam int unsigned L2AddrIdxWidth = $clog2(L2NumWords);
  localparam int unsigned L2BytesPerWord = AxiDataWidth / 8;

  logic [AxiDataWidth-1:0]   l2_mem [0:L2NumWords-1];
  logic [L2AddrIdxWidth-1:0] l2_mem_idx;

  // Word-aligned indexing: drop byte offset bits.
  assign l2_mem_idx = l2_addr[L2AddrIdxWidth-1+$clog2(L2BytesPerWord):$clog2(L2BytesPerWord)];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      l2_rdata <= '0;
    end else begin
      if (l2_req) begin
        if (l2_we) begin
          for (int i = 0; i < L2BytesPerWord; i++) begin
            if (l2_be[i]) begin
              l2_mem[l2_mem_idx][8*i +: 8] <= l2_wdata[8*i +: 8];
            end
          end
        end else begin
          l2_rdata <= l2_mem[l2_mem_idx];
        end
      end
    end
  end
`else
  assign l2_rdata = '0;
`endif

  // One-cycle latency
  `FF(l2_rvalid, l2_req, 1'b0);

  //////////////////////////////
  //  System Bus Access (SBA) //
  //////////////////////////////
  //
  // Match the known-good upstream CVA6 FPGA integration:
  // - Use the standard CVA6/Ariane `axi_adapter` to bridge DM SBA master requests
  //   (req/we/addr/be/wdata) into AXI transactions.
  // - This fixes AXI protocol corner cases (independent AW/W handshakes) and uses
  //   correct transfer size encoding (1/2/4/8 bytes) like the reference project.
  //
  // Reference: `axi_adapter` usage in [ariane_xilinx.sv](reference_proj/cva6/corev_apu/fpga/src/ariane_xilinx.sv:654)

  // Adapter AXI connection to SoC crossbar slave port 1
  system_req_t  sba_axi_req;
  system_resp_t sba_axi_resp;

  assign soc_axi_req[1] = sba_axi_req;
  assign sba_axi_resp   = soc_axi_resp[1];

  // Pack/unpack SBA data/byte-enables into the adapter's arrayed ports.
  // We only ever use SINGLE_REQ (one beat) transactions here.
  logic [0:0][AxiNarrowDataWidth-1:0] sba_wdata_arr;
  logic [0:0][AxiNarrowDataWidth/8-1:0] sba_be_arr;
  logic [0:0][AxiNarrowDataWidth-1:0] sba_rdata_arr;

  assign sba_wdata_arr[0] = sba_wdata_i[AxiNarrowDataWidth-1:0];
  assign sba_be_arr[0]    = sba_be_i[AxiNarrowDataWidth/8-1:0];
  assign sba_r_rdata_o    = sba_rdata_arr[0];

  // XLEN==64: size encoding for 8-byte accesses is 2'b11 (matches upstream `axi_adapter_size`).
  // Byte enables (sba_be_i) still allow narrower accesses.
  localparam logic [1:0] SBA_ADAPTER_SIZE = 2'b11;

  axi_adapter #(
    .CVA6Cfg   (CVA6Config   ),
    .DATA_WIDTH(AxiNarrowDataWidth),
    .axi_req_t (system_req_t ),
    .axi_rsp_t (system_resp_t)
  ) i_dm_axi_master (
    .clk_i                 (clk_i                 ),
    .rst_ni                (rst_ni                ),
    .req_i                 (sba_req_i             ),
    .type_i                (ariane_pkg::SINGLE_REQ),
    .amo_i                 (ariane_pkg::AMO_NONE  ),
    .gnt_o                 (sba_gnt_o             ),
    .addr_i                (sba_addr_i            ),
    .we_i                  (sba_we_i              ),
    .wdata_i               (sba_wdata_arr         ),
    .be_i                  (sba_be_arr            ),
    .size_i                (SBA_ADAPTER_SIZE      ),
    .id_i                  ('0                    ),
    .valid_o               (sba_r_valid_o         ),
    .rdata_o               (sba_rdata_arr         ),
    .id_o                  (/* unused */          ),
    .critical_word_o       (/* unused */          ),
    .critical_word_valid_o (/* unused */          ),
    .axi_req_o             (sba_axi_req           ),
    .axi_resp_i            (sba_axi_resp          )
  );

  //////////////////////////////
  //  Debug Module memory win //
  //////////////////////////////
  //
  // Make this path match the known-good upstream CVA6 FPGA integration:
  // - Use `axi2mem` (AXI -> simple mem req/we/addr/be/wdata/rdata) rather than `axi_to_mem`.
  // Reference: [ariane_xilinx.sv](reference_proj/cva6/corev_apu/fpga/src/ariane_xilinx.sv:481)
  //
  // This removes the custom mem_rvalid shaping and relies on the same semantics as the reference.
  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( AxiPeriphIdWidth  ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
  ) dm_debug_axi ();

  `AXI_ASSIGN_FROM_REQ(dm_debug_axi, periph_wide_axi_req[DEBUG])
  `AXI_ASSIGN_TO_RESP(periph_wide_axi_resp[DEBUG], dm_debug_axi)

  logic [AxiUserWidth-1:0] dm_user_unused;

  axi2mem #(
    .AXI_ID_WIDTH   ( AxiPeriphIdWidth ),
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
  ) i_axi2dm (
    .clk_i   ( clk_i           ),
    .rst_ni  ( rst_ni          ),
    .slave   ( dm_debug_axi    ),
    .req_o   ( dm_device_req_o ),
    .we_o    ( dm_device_we_o  ),
    .addr_o  ( dm_device_addr_o),
    .be_o    ( dm_device_be_o  ),
    .user_o  ( dm_user_unused  ),
    .data_o  ( dm_device_wdata_o ),
    .user_i  ( '0              ),
    .data_i  ( dm_device_rdata_i )
  );

  ////////////
  //  UART  //
  ////////////

  `AXI_TYPEDEF_ALL(uart_axi, axi_addr_t, axi_soc_id_t, logic [31:0], logic [3:0], axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(uart_lite, axi_addr_t, logic [31:0], logic [3:0])
  `APB_TYPEDEF_ALL(uart_apb, axi_addr_t, logic [31:0], logic [3:0])

  uart_axi_req_t   uart_axi_req;
  uart_axi_resp_t  uart_axi_resp;
  uart_lite_req_t  uart_lite_req;
  uart_lite_resp_t uart_lite_resp;
  uart_apb_req_t   uart_apb_req;
  uart_apb_resp_t  uart_apb_resp;

  assign uart_penable_o = uart_apb_req.penable;
  assign uart_pwrite_o  = uart_apb_req.pwrite;
  assign uart_paddr_o   = uart_apb_req.paddr;
  assign uart_psel_o    = uart_apb_req.psel;
  assign uart_pwdata_o  = uart_apb_req.pwdata;
  assign uart_apb_resp.prdata  = uart_prdata_i;
  assign uart_apb_resp.pready  = uart_pready_i;
  assign uart_apb_resp.pslverr = uart_pslverr_i;

  typedef struct packed {
    int unsigned idx;
    axi_addr_t   start_addr;
    axi_addr_t   end_addr;
  } uart_apb_rule_t;

  uart_apb_rule_t uart_apb_map = '{idx: 0, start_addr: '0, end_addr: '1};

  axi_lite_to_apb #(
    .NoApbSlaves     (32'd1           ),
    .NoRules         (32'd1           ),
    .AddrWidth       (AxiAddrWidth    ),
    .DataWidth       (32'd32          ),
    .PipelineRequest (1'b0            ),
    .PipelineResponse(1'b0            ),
    .axi_lite_req_t  (uart_lite_req_t ),
    .axi_lite_resp_t (uart_lite_resp_t),
    .apb_req_t       (uart_apb_req_t  ),
    .apb_resp_t      (uart_apb_resp_t ),
    .rule_t          (uart_apb_rule_t )
  ) i_axi_lite_to_apb_uart (
    .clk_i          (clk_i         ),
    .rst_ni         (rst_ni        ),
    .axi_lite_req_i (uart_lite_req ),
    .axi_lite_resp_o(uart_lite_resp),
    .apb_req_o      (uart_apb_req  ),
    .apb_resp_i     (uart_apb_resp ),
    .addr_map_i     (uart_apb_map  )
  );

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth      ),
    .AxiDataWidth   (32'd32            ),
    .AxiIdWidth     (AxiPeriphIdWidth  ),
    .AxiUserWidth   (AxiUserWidth      ),
    .AxiMaxWriteTxns(32'd1             ),
    .AxiMaxReadTxns (32'd1             ),
    .FallThrough    (1'b1              ),
    .full_req_t     (uart_axi_req_t    ),
    .full_resp_t    (uart_axi_resp_t   ),
    .lite_req_t     (uart_lite_req_t   ),
    .lite_resp_t    (uart_lite_resp_t  )
  ) i_axi_to_axi_lite_uart (
    .clk_i     (clk_i         ),
    .rst_ni    (rst_ni        ),
    .test_i    (1'b0          ),
    .slv_req_i (uart_axi_req  ),
    .slv_resp_o(uart_axi_resp ),
    .mst_req_o (uart_lite_req ),
    .mst_resp_i(uart_lite_resp)
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiDataWidth       ),
    .AxiMstPortDataWidth(32                 ),
    .AxiAddrWidth       (AxiAddrWidth       ),
    .AxiIdWidth         (AxiPeriphIdWidth   ),
    .AxiMaxReads        (1                  ),
    .ar_chan_t          (soc_wide_ar_chan_t ),
    .mst_r_chan_t       (uart_axi_r_chan_t  ),
    .slv_r_chan_t       (soc_wide_r_chan_t  ),
    .aw_chan_t          (uart_axi_aw_chan_t ),
    .b_chan_t           (soc_wide_b_chan_t  ),
    .mst_w_chan_t       (uart_axi_w_chan_t  ),
    .slv_w_chan_t       (soc_wide_w_chan_t  ),
    .axi_mst_req_t      (uart_axi_req_t     ),
    .axi_mst_resp_t     (uart_axi_resp_t    ),
    .axi_slv_req_t      (soc_wide_req_t     ),
    .axi_slv_resp_t     (soc_wide_resp_t    )
  ) i_axi_slave_uart_dwc (
    .clk_i     (clk_i                     ),
    .rst_ni    (rst_ni                    ),
    .slv_req_i (periph_wide_axi_req[UART] ),
    .slv_resp_o(periph_wide_axi_resp[UART]),
    .mst_req_o (uart_axi_req              ),
    .mst_resp_i(uart_axi_resp             )
  );

  /////////////////////////
  //  Control registers  //
  /////////////////////////

  soc_narrow_lite_req_t  axi_lite_ctrl_registers_req;
  soc_narrow_lite_resp_t axi_lite_ctrl_registers_resp;

  logic [63:0] event_trigger;

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth           ),
    .AxiDataWidth   (AxiNarrowDataWidth     ),
    .AxiIdWidth     (AxiPeriphIdWidth       ),
    .AxiUserWidth   (AxiUserWidth           ),
    .AxiMaxReadTxns (1                      ),
    .AxiMaxWriteTxns(1                      ),
    .FallThrough    (1'b0                   ),
    .full_req_t     (soc_narrow_req_t       ),
    .full_resp_t    (soc_narrow_resp_t      ),
    .lite_req_t     (soc_narrow_lite_req_t  ),
    .lite_resp_t    (soc_narrow_lite_resp_t )
  ) i_axi_to_axi_lite_ctrl (
    .clk_i     (clk_i                        ),
    .rst_ni    (rst_ni                       ),
    .test_i    (1'b0                         ),
    .slv_req_i (periph_narrow_axi_req[CTRL]  ),
    .slv_resp_o(periph_narrow_axi_resp[CTRL] ),
    .mst_req_o (axi_lite_ctrl_registers_req  ),
    .mst_resp_i(axi_lite_ctrl_registers_resp )
  );

  ctrl_registers #(
    .DRAMBaseAddr   (DRAMBase              ),
    .DRAMLength     (DRAMLength            ),
    .DataWidth      (AxiNarrowDataWidth    ),
    .AddrWidth      (AxiAddrWidth          ),
    .axi_lite_req_t (soc_narrow_lite_req_t ),
    .axi_lite_resp_t(soc_narrow_lite_resp_t)
  ) i_ctrl_registers (
    .clk_i                (clk_i                       ),
    .rst_ni               (rst_ni                      ),
    .axi_lite_slave_req_i (axi_lite_ctrl_registers_req ),
    .axi_lite_slave_resp_o(axi_lite_ctrl_registers_resp),
    .hw_cnt_en_o          (hw_cnt_en_o                 ),
    .dram_base_addr_o     (/* unused */                ),
    .dram_end_addr_o      (/* unused */                ),
    .exit_o               (exit_o                      ),
    .event_trigger_o      (event_trigger               )
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiDataWidth          ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth    ),
    .AxiAddrWidth       (AxiAddrWidth          ),
    .AxiIdWidth         (AxiPeriphIdWidth      ),
    .AxiMaxReads        (2                     ),
    .ar_chan_t          (soc_wide_ar_chan_t    ),
    .mst_r_chan_t       (soc_narrow_r_chan_t   ),
    .slv_r_chan_t       (soc_wide_r_chan_t     ),
    .aw_chan_t          (soc_narrow_aw_chan_t  ),
    .b_chan_t           (soc_narrow_b_chan_t   ),
    .mst_w_chan_t       (soc_narrow_w_chan_t   ),
    .slv_w_chan_t       (soc_wide_w_chan_t     ),
    .axi_mst_req_t      (soc_narrow_req_t      ),
    .axi_mst_resp_t     (soc_narrow_resp_t     ),
    .axi_slv_req_t      (soc_wide_req_t        ),
    .axi_slv_resp_t     (soc_wide_resp_t       )
  ) i_axi_slave_ctrl_dwc (
    .clk_i     (clk_i                       ),
    .rst_ni    (rst_ni                      ),
    .slv_req_i (periph_wide_axi_req[CTRL]   ),
    .slv_resp_o(periph_wide_axi_resp[CTRL]  ),
    .mst_req_o (periph_narrow_axi_req[CTRL] ),
    .mst_resp_i(periph_narrow_axi_resp[CTRL])
  );

  //////////////
  //  System  //
  //////////////

  logic [2:0] hart_id;
  assign hart_id = '0;

  function automatic config_pkg::cva6_user_cfg_t gen_usr_cva6_config(config_pkg::cva6_user_cfg_t cfg);
    cfg.AxiAddrWidth          = AxiAddrWidth;
    cfg.AxiDataWidth          = AxiNarrowDataWidth;
    cfg.AxiIdWidth            = AxiIdWidth;
    cfg.AxiUserWidth          = AxiUserWidth;

    // Keep PMP off in this FPGA build
    cfg.NrPMPEntries          = 0;

    // Idempotent regions (peripherals)
    cfg.NrNonIdempotentRules  = 2;
    cfg.NonIdempotentAddrBase = {UARTBase, CTRLBase};
    cfg.NonIdempotentLength   = {UARTLength, CTRLLength};

    cfg.NrExecuteRegionRules  = 3;
    cfg.ExecuteRegionAddrBase = {DRAMBase,   64'h1_0000, DebugBase};
    cfg.ExecuteRegionLength   = {DRAMLength, 64'h10000,  64'h1000};

    // Cached region (DRAM window)
    cfg.NrCachedRegionRules   = 1;
    cfg.CachedRegionAddrBase  = {DRAMBase};
    cfg.CachedRegionLength    = {DRAMLength};

    // Debug module location (must match SoC DEBUG window and riscv-dbg)
    cfg.DebugEn               = 1'b1;
    cfg.DmBaseAddress         = DebugBase;
    cfg.HaltAddress           = 64'h800;
    cfg.ExceptionAddress      = 64'h808;

    return cfg;
  endfunction

  localparam config_pkg::cva6_user_cfg_t CVA6Config_user = gen_usr_cva6_config(cva6_config_pkg::cva6_cfg);
  localparam config_pkg::cva6_cfg_t      CVA6Config      = build_config_pkg::build_config(CVA6Config_user);

  // Define the exception type
  `CVA6_TYPEDEF_EXCEPTION(exception_t, CVA6Config);

  // Standard interface (we still instantiate the types so cva6 can compile)
  `CVA6_INTF_TYPEDEF_ACC_REQ(accelerator_req_t, CVA6Config, fpnew_pkg::roundmode_e);
  `CVA6_INTF_TYPEDEF_ACC_RESP(accelerator_resp_t, CVA6Config, exception_t);
  // MMU interface
  `CVA6_INTF_TYPEDEF_MMU_REQ(acc_mmu_req_t, CVA6Config);
  `CVA6_INTF_TYPEDEF_MMU_RESP(acc_mmu_resp_t, CVA6Config, exception_t);
  // Accelerator - CVA6 top-level interface
  `CVA6_INTF_TYPEDEF_CVA6_TO_ACC(cva6_to_acc_t, accelerator_req_t, acc_mmu_resp_t);
  `CVA6_INTF_TYPEDEF_ACC_TO_CVA6(acc_to_cva6_t, accelerator_resp_t, acc_mmu_req_t);

`ifndef TARGET_GATESIM
  cva6_system #(
    .CVA6Cfg            (CVA6Config            ),
    .exception_t        (exception_t           ),
    .accelerator_req_t  (accelerator_req_t     ),
    .accelerator_resp_t (accelerator_resp_t    ),
    .acc_mmu_req_t      (acc_mmu_req_t         ),
    .acc_mmu_resp_t     (acc_mmu_resp_t        ),
    .cva6_to_acc_t      (cva6_to_acc_t         ),
    .acc_to_cva6_t      (acc_to_cva6_t         ),
    .AxiAddrWidth       (AxiAddrWidth          ),
    .AxiIdWidth         (AxiSocIdWidth         ),
    .AxiNarrowDataWidth (AxiNarrowDataWidth    ),
    .AxiWideDataWidth   (AxiDataWidth          ),
    .ariane_axi_ar_t    (ariane_axi_ar_chan_t  ),
    .ariane_axi_aw_t    (ariane_axi_aw_chan_t  ),
    .ariane_axi_b_t     (ariane_axi_b_chan_t   ),
    .ariane_axi_r_t     (ariane_axi_r_chan_t   ),
    .ariane_axi_w_t     (ariane_axi_w_chan_t   ),
    .ariane_axi_req_t   (ariane_axi_req_t      ),
    .ariane_axi_resp_t  (ariane_axi_resp_t     ),
    .system_axi_ar_t    (system_ar_chan_t      ),
    .system_axi_aw_t    (system_aw_chan_t      ),
    .system_axi_b_t     (system_b_chan_t       ),
    .system_axi_r_t     (system_r_chan_t       ),
    .system_axi_w_t     (system_w_chan_t       ),
    .system_axi_req_t   (system_req_t          ),
    .system_axi_resp_t  (system_resp_t         )
  ) i_system (
    .clk_i         (clk_i          ),
    .rst_ni        (core_rst_ni_i   ),
    .boot_addr_i   (DRAMBase       ),
    .hart_id_i     (hart_id        ),
    .scan_enable_i (1'b0           ),
    .scan_data_i   (1'b0           ),
    .scan_data_o   (/* unused */   ),
    .debug_req_i   (debug_req_i    ),
    .axi_req_o     (system_axi_req ),
    .axi_resp_i    (system_axi_resp)
  );
`else
  // For gatesim, reuse the ara_soc_fpga cut/delay style if needed.
  cva6_system i_system (
    .clk_i         (clk_i          ),
    .rst_ni        (core_rst_ni_i   ),
    .boot_addr_i   (DRAMBase       ),
    .hart_id_i     (hart_id        ),
    .scan_enable_i (1'b0           ),
    .scan_data_i   (1'b0           ),
    .scan_data_o   (/* unused */   ),
    .debug_req_i   (debug_req_i    ),
    .axi_req_o     (system_axi_req ),
    .axi_resp_i    (system_axi_resp)
  );
`endif

  // Scan chain not used
  assign scan_data_o = 1'b0;

  //////////////////
  //  Assertions  //
  //////////////////

  if (AxiDataWidth == 0)
    $error("[cva6_soc] The AXI data width must be greater than zero.");
  if (AxiAddrWidth == 0)
    $error("[cva6_soc] The AXI address width must be greater than zero.");
  if (AxiUserWidth == 0)
    $error("[cva6_soc] The AXI user width must be greater than zero.");
  if (AxiIdWidth == 0)
    $error("[cva6_soc] The AXI ID width must be greater than zero.");

endmodule : cva6_soc