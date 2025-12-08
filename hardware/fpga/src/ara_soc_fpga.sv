// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's SoC, containing CVA6, Ara, and a L2 cache.

module ara_soc import axi_pkg::*; import ara_pkg::*; #(
    // RVV Parameters
    parameter  int           unsigned NrLanes      = 0,                          // Number of parallel vector lanes.
    parameter  int           unsigned VLEN         = 0,                          // VLEN [bit]
    parameter  int           unsigned OSSupport    = 1,                          // Support for OS
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // External support for vfrec7, vfrsqrt7
    parameter  fpext_support_e        FPExtSupport = FPExtSupportEnable,
    // Support for fixed-point data types
    parameter  fixpt_support_e        FixPtSupport = FixedPointEnable,
    // Support for segment memory operations
    parameter  seg_support_e          SegSupport   = SegSupportEnable,
    // AXI Interface
    parameter  int           unsigned AxiDataWidth = 32*NrLanes,
    parameter  int           unsigned AxiAddrWidth = 64,
    parameter  int           unsigned AxiUserWidth = 1,
    parameter  int           unsigned AxiIdWidth   = 5,
    // AXI Resp Delay [ps] for gate-level simulation
    parameter  int           unsigned AxiRespDelay = 200,
    // Main memory
    parameter  int           unsigned L2NumWords   = (2**22) / NrLanes,
    // Dependant parameters. DO NOT CHANGE!
    localparam type                   axi_data_t   = logic [AxiDataWidth-1:0],
    localparam type                   axi_strb_t   = logic [AxiDataWidth/8-1:0],
    localparam type                   axi_addr_t   = logic [AxiAddrWidth-1:0],
    localparam type                   axi_user_t   = logic [AxiUserWidth-1:0],
    // System-level AXI ID type (output of ara_system / DM SBA, slave side of SoC crossbar).
    // This uses the system ID width (AxiSocIdWidth). Peripheral-side IDs (soc_wide_*, soc_narrow_*)
    // use AxiPeriphIdWidth, and core-side IDs (inside ara_system) use AxiCoreIdWidth.
    localparam type                   axi_id_t     = logic [AxiSocIdWidth-1:0]
  ) (
    input  logic        clk_i,
    // SoC-level reset: resets fabric, L2 SRAM, peripherals, and debug window.
    // This is driven by the board/PLL reset and is NOT gated by ndmreset.
    input  logic        rst_ni,
    // Core-level reset: used only for the CVA6+Ara core complex (ara_system).
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
    // UART APB interface
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
  `include "ara/intf_typedef.svh"

  //////////////////////
  //  Memory Regions  //
  //////////////////////

  localparam NrAXIMasters    = 1; // CVA6/Ara only (core-level, used for ID slicing)
  // Number of SoC-level AXI initiators connected to the SoC crossbar:
  //   - Port 0 : ara_system (CVA6 + Ara combined)
  //   - Port 1 : RISC-V Debug Module SBA master (to be connected)
  localparam int unsigned NrAXIMastersSoc = 2;

   typedef enum int unsigned {
     L2MEM = 0,
     UART  = 1,
     CTRL  = 2,
     DEBUG = 3
   } axi_slaves_e;
  localparam NrAXISlaves = DEBUG + 1;

  // Memory Map
  // 1GByte of DDR (split between two chips on Genesys2)
  localparam logic [63:0] DRAMLength  = 64'h40000000;
  localparam logic [63:0] UARTLength  = 64'h1000;
  localparam logic [63:0] CTRLLength  = 64'h1000;
  localparam logic [63:0] DebugLength = 64'h1000;

  typedef enum logic [63:0] {
    DRAMBase  = 64'h8000_0000,
    UARTBase  = 64'hC000_0000,
    CTRLBase  = 64'hD000_0000,
    // Place Debug window at same base as Ibex demo system
    DebugBase = 64'h1A11_0000
  } soc_bus_start_e;

  ///////////
  //  AXI  //
  ///////////

  // Ariane's AXI port data width
  localparam AxiNarrowDataWidth = 64;
  localparam AxiNarrowStrbWidth = AxiNarrowDataWidth / 8;
  // Ara's AXI port data width
  localparam AxiWideDataWidth   = AxiDataWidth;
  localparam AXiWideStrbWidth   = AxiWideDataWidth / 8;

  localparam AxiSocIdWidth  = AxiIdWidth - $clog2(NrAXIMasters);
  localparam AxiCoreIdWidth = AxiSocIdWidth - 1;
  // Peripheral-side ID width: system ID width extended by log2(#SoC masters)
  localparam int unsigned AxiPeriphIdWidth = AxiSocIdWidth + $clog2(NrAXIMastersSoc);


  // Internal types
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t;
  typedef logic [AxiNarrowStrbWidth-1:0] axi_narrow_strb_t;
  // Peripheral-side IDs (crossbar master ports and peripherals)
  typedef logic [AxiPeriphIdWidth-1:0] axi_soc_id_t;
  // Core-side IDs (inside ara_system: CVA6 + Ara)
  typedef logic [AxiCoreIdWidth-1:0] axi_core_id_t;

  // AXI Typedefs
  `AXI_TYPEDEF_ALL(system, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(ara_axi, axi_addr_t, axi_core_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(ariane_axi, axi_addr_t, axi_core_id_t, axi_narrow_data_t, axi_narrow_strb_t,
    axi_user_t)
  `AXI_TYPEDEF_ALL(soc_narrow, axi_addr_t, axi_soc_id_t, axi_narrow_data_t, axi_narrow_strb_t,
    axi_user_t)
  `AXI_TYPEDEF_ALL(soc_wide, axi_addr_t, axi_soc_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(soc_narrow_lite, axi_addr_t, axi_narrow_data_t, axi_narrow_strb_t)



  // Buses
  system_req_t  system_axi_req_spill;
  system_resp_t system_axi_resp_spill;
  system_resp_t system_axi_resp_spill_del;
  system_req_t  system_axi_req;
  system_resp_t system_axi_resp;
  // SoC-level AXI master ports towards the crossbar:
  //   soc_axi_req[0] / soc_axi_resp[0] : ara_system (CVA6 + Ara)
  //   soc_axi_req[1] / soc_axi_resp[1] : Debug Module SBA master (to be connected)
  system_req_t  [NrAXIMastersSoc-1:0] soc_axi_req;
  system_resp_t [NrAXIMastersSoc-1:0] soc_axi_resp;


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
    // Slave-port ID width is the system-level ID width (output of ara_system / DM SBA).
    AxiIdWidthSlvPorts: AxiSocIdWidth,
    AxiIdUsedSlvPorts : AxiSocIdWidth,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiWideDataWidth,
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

  // Connect ara_system AXI master to SoC crossbar master port 0.
  assign soc_axi_req[0]  = system_axi_req;
  assign system_axi_resp = soc_axi_resp[0];

  // soc_axi_req[1] / soc_axi_resp[1] will be driven by the Debug Module SBA AXI master.

  //////////
  //  L2  //
  //////////

  // The L2 memory does not support atomics

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

  // L2 SRAM (no direct SBA arbitration here; all accesses come via AXI)
  logic                      l2_req;
  logic                      l2_we;
  logic [AxiAddrWidth-1:0]   l2_addr;
  logic [AxiDataWidth/8-1:0] l2_be;
  logic [AxiDataWidth-1:0]   l2_wdata;
  logic [AxiDataWidth-1:0]   l2_rdata;
  logic                      l2_rvalid;

  axi_to_mem #(
    .AddrWidth (AxiAddrWidth      ),
    .DataWidth (AxiDataWidth      ),
    .IdWidth   (AxiPeriphIdWidth  ),
    .NumBanks  (1                 ),
    .axi_req_t (soc_wide_req_t    ),
    .axi_resp_t(soc_wide_resp_t   )
  ) i_axi_to_mem (
    .clk_i       (clk_i                         ),
    .rst_ni      (rst_ni                        ),
    .axi_req_i   (l2mem_wide_axi_req_wo_atomics ),
    .axi_resp_o  (l2mem_wide_axi_resp_wo_atomics),
    .mem_req_o   (l2_req                        ),
    .mem_gnt_i   (l2_req                        ), // Always available
    .mem_we_o    (l2_we                         ),
    .mem_addr_o  (l2_addr                       ),
    .mem_strb_o  (l2_be                         ),
    .mem_wdata_o (l2_wdata                      ),
    .mem_rdata_i (l2_rdata                      ),
    .mem_rvalid_i(l2_rvalid                     ),
    .mem_atop_o  (/* Unused */                  ),
    .busy_o      (/* Unused */                  )
  );

`ifndef SPYGLASS
  tc_sram #(
    .NumWords (L2NumWords  ),
    .NumPorts (1           ),
    .DataWidth(AxiDataWidth),
    .SimInit("random")
  ) i_dram (
    .clk_i  (clk_i                                                                      ),
    .rst_ni (rst_ni                                                                     ),
    .req_i  (l2_req                                                                     ),
    .we_i   (l2_we                                                                      ),
    .addr_i (l2_addr[$clog2(L2NumWords)-1+$clog2(AxiDataWidth/8):$clog2(AxiDataWidth/8)]),
    .wdata_i(l2_wdata                                                                   ),
    .be_i   (l2_be                                                                      ),
    .rdata_o(l2_rdata                                                                   )
  );
`else
  assign l2_rdata = '0;
`endif

  // One-cycle latency for L2
  `FF(l2_rvalid, l2_req, 1'b0);

  //////////////////////////////
  //  System Bus Access (SBA) //
  //////////////////////////////

  // Simple AXI master for DM SBA, using SoC crossbar port 1.
  typedef enum logic [2:0] {
    SBA_IDLE,
    SBA_SEND_WRITE,
    SBA_WAIT_WRITE_RESP,
    SBA_SEND_READ,
    SBA_WAIT_READ_DATA
  } sba_state_e;

  sba_state_e               sba_state_d, sba_state_q;
  logic [AxiAddrWidth-1:0]  sba_addr_q;
  logic                     sba_we_q;
  logic [AxiDataWidth/8-1:0] sba_be_q;
  logic [AxiDataWidth-1:0]  sba_wdata_q;

  // Use 32-bit accesses on the 64-bit AXI bus; size is log2(#bytes) = 2 for 4 bytes.
  localparam logic [2:0] SBA_AXI_SIZE = 3'd2;

  // Combinational SBA -> AXI master logic
  always_comb begin
    // Defaults for AXI master port 1
    soc_axi_req[1] = '0;

    // Defaults for SBA handshake back to DM
    sba_gnt_o     = 1'b0;
    sba_r_valid_o = 1'b0;
    sba_r_rdata_o = '0;

    sba_state_d = sba_state_q;

    unique case (sba_state_q)
      SBA_IDLE: begin
        // Accept a new SBA request and provide immediate grant. The AXI
        // transaction itself is issued in the next cycle based on the
        // latched address/control.
        if (sba_req_i) begin
          sba_gnt_o   = 1'b1;
          sba_state_d = sba_we_i ? SBA_SEND_WRITE : SBA_SEND_READ;
        end
      end

      SBA_SEND_WRITE: begin
        // Issue a single-beat write transaction.
        soc_axi_req[1].aw_valid      = 1'b1;
        soc_axi_req[1].aw.addr       = sba_addr_q;
        soc_axi_req[1].aw.prot       = 3'b000;
        soc_axi_req[1].aw.region     = 4'b0000;
        soc_axi_req[1].aw.len        = 8'd0;              // single beat
        soc_axi_req[1].aw.size       = SBA_AXI_SIZE;      // 4 bytes
        soc_axi_req[1].aw.burst      = axi_pkg::BURST_INCR;
        soc_axi_req[1].aw.lock       = 1'b0;
        soc_axi_req[1].aw.cache      = axi_pkg::CACHE_MODIFIABLE;
        soc_axi_req[1].aw.qos        = 4'b0000;
        soc_axi_req[1].aw.id         = '0;
        soc_axi_req[1].aw.atop       = '0;
        soc_axi_req[1].aw.user       = '0;

        soc_axi_req[1].w_valid       = 1'b1;
        soc_axi_req[1].w.data        = sba_wdata_q;
        soc_axi_req[1].w.strb        = sba_be_q;
        soc_axi_req[1].w.last        = 1'b1;
        soc_axi_req[1].w.user        = '0;

        soc_axi_req[1].b_ready       = 1'b1;
        soc_axi_req[1].r_ready       = 1'b0;

        // Wait until both address and data beats have been accepted.
        if (soc_axi_resp[1].aw_ready && soc_axi_resp[1].w_ready) begin
          sba_state_d = SBA_WAIT_WRITE_RESP;
        end
      end

      SBA_WAIT_WRITE_RESP: begin
        soc_axi_req[1].b_ready = 1'b1;
        if (soc_axi_resp[1].b_valid) begin
          // Signal completion of the write to the DM via sbdata_valid.
          sba_r_valid_o = 1'b1;
          sba_state_d   = SBA_IDLE;
        end
      end

      SBA_SEND_READ: begin
        // Issue a single-beat read transaction.
        soc_axi_req[1].ar_valid      = 1'b1;
        soc_axi_req[1].ar.addr       = sba_addr_q;
        soc_axi_req[1].ar.prot       = 3'b000;
        soc_axi_req[1].ar.region     = 4'b0000;
        soc_axi_req[1].ar.len        = 8'd0;              // single beat
        soc_axi_req[1].ar.size       = SBA_AXI_SIZE;      // 4 bytes
        soc_axi_req[1].ar.burst      = axi_pkg::BURST_INCR;
        soc_axi_req[1].ar.lock       = 1'b0;
        soc_axi_req[1].ar.cache      = axi_pkg::CACHE_MODIFIABLE;
        soc_axi_req[1].ar.qos        = 4'b0000;
        soc_axi_req[1].ar.id         = '0;
        soc_axi_req[1].ar.user       = '0;

        soc_axi_req[1].r_ready       = 1'b1;
        soc_axi_req[1].b_ready       = 1'b0;

        if (soc_axi_resp[1].ar_ready) begin
          sba_state_d = SBA_WAIT_READ_DATA;
        end
      end

      SBA_WAIT_READ_DATA: begin
        soc_axi_req[1].r_ready = 1'b1;
        if (soc_axi_resp[1].r_valid) begin
          // Return read data to DM via sbdata_valid/sbdata.
          sba_r_valid_o = 1'b1;
          sba_r_rdata_o = soc_axi_resp[1].r.data;
          if (soc_axi_resp[1].r.last) begin
            sba_state_d = SBA_IDLE;
          end
        end
      end

      default: begin
        sba_state_d = SBA_IDLE;
      end
    endcase
  end

  // SBA state and request latching
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sba_state_q  <= SBA_IDLE;
      sba_addr_q   <= '0;
      sba_we_q     <= 1'b0;
      sba_be_q     <= '0;
      sba_wdata_q  <= '0;
    end else begin
      sba_state_q <= sba_state_d;
      // Latch request parameters in IDLE when a new SBA request arrives.
      if (sba_state_q == SBA_IDLE && sba_req_i) begin
        sba_addr_q  <= sba_addr_i;
        sba_we_q    <= sba_we_i;
        sba_be_q    <= sba_be_i;
        sba_wdata_q <= sba_wdata_i;
      end
    end
  end

  //////////////////////////////
  //  Debug Module memory win //
  //////////////////////////////

  // Map the Debug Module's memory window into the SoC AXI address space at
  // DebugBase .. DebugBase + DebugLength, and expose a simple request/response
  // interface to the external debug module (dm_top).
  logic dm_device_rvalid;

  axi_to_mem #(
    .AddrWidth (AxiAddrWidth      ),
    .DataWidth (AxiDataWidth      ),
    .IdWidth   (AxiPeriphIdWidth  ),
    .NumBanks  (1                 ),
    .axi_req_t (soc_wide_req_t    ),
    .axi_resp_t(soc_wide_resp_t   )
  ) i_axi_to_dm_mem (
    .clk_i       (clk_i                      ),
    .rst_ni      (rst_ni                     ),
    .axi_req_i   (periph_wide_axi_req[DEBUG] ),
    .axi_resp_o  (periph_wide_axi_resp[DEBUG]),
    .mem_req_o   (dm_device_req_o            ),
    .mem_gnt_i   (1'b1                       ), // always ready
    .mem_we_o    (dm_device_we_o             ),
    .mem_addr_o  (dm_device_addr_o           ),
    .mem_strb_o  (dm_device_be_o             ),
    .mem_wdata_o (dm_device_wdata_o          ),
    .mem_rdata_i (dm_device_rdata_i          ),
    .mem_rvalid_i(dm_device_rvalid           ),
    .mem_atop_o  (/* Unused */               ),
    .busy_o      (/* Unused */               )
  );

  // Generate a one-cycle read latency for the debug memory window.
  `FF(dm_device_rvalid, dm_device_req_o & ~dm_device_we_o, 1'b0);

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
    .AxiSlvPortDataWidth(AxiWideDataWidth   ),
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
  ) i_axi_to_axi_lite (
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
    .dram_base_addr_o     (/* Unused */                ),
    .dram_end_addr_o      (/* Unused */                ),
    .exit_o               (exit_o                      ),
    .event_trigger_o      (event_trigger)
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiWideDataWidth     ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth   ),
    .AxiAddrWidth       (AxiAddrWidth         ),
    .AxiIdWidth         (AxiPeriphIdWidth     ),
    .AxiMaxReads        (2                    ),
    .ar_chan_t          (soc_wide_ar_chan_t   ),
    .mst_r_chan_t       (soc_narrow_r_chan_t  ),
    .slv_r_chan_t       (soc_wide_r_chan_t    ),
    .aw_chan_t          (soc_narrow_aw_chan_t ),
    .b_chan_t           (soc_narrow_b_chan_t  ),
    .mst_w_chan_t       (soc_narrow_w_chan_t  ),
    .slv_w_chan_t       (soc_wide_w_chan_t    ),
    .axi_mst_req_t      (soc_narrow_req_t     ),
    .axi_mst_resp_t     (soc_narrow_resp_t    ),
    .axi_slv_req_t      (soc_wide_req_t       ),
    .axi_slv_resp_t     (soc_wide_resp_t      )
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

  // Modify configuration parameters
  function automatic config_pkg::cva6_user_cfg_t gen_usr_cva6_config(config_pkg::cva6_user_cfg_t cfg);
    cfg.AxiAddrWidth          = AxiAddrWidth;
    cfg.AxiDataWidth          = AxiNarrowDataWidth;
    cfg.AxiIdWidth            = AxiIdWidth;
    cfg.AxiUserWidth          = AxiUserWidth;
    cfg.XF16                  = FPUSupport[3];
    cfg.RVF                   = FPUSupport[4];
    cfg.RVD                   = FPUSupport[5];
    cfg.XF16ALT               = FPUSupport[2];
    cfg.XF8                   = FPUSupport[1];
 //  cfg.XF8ALT                = FPUSupport[0]; // Not supported by OpenHW Group's CVFPU
    cfg.NrPMPEntries          = 0;
    // idempotent region
    cfg.NrNonIdempotentRules  = 2;
    cfg.NonIdempotentAddrBase = {UARTBase, CTRLBase};
    cfg.NonIdempotentLength   = {UARTLength, CTRLLength};
    cfg.NrExecuteRegionRules  = 3;
    //                          DRAM;       Boot ROM;   Debug Module
    cfg.ExecuteRegionAddrBase = {DRAMBase,   64'h1_0000, DebugBase};
    cfg.ExecuteRegionLength   = {DRAMLength, 64'h10000,  64'h1000};
    // cached region
    cfg.NrCachedRegionRules   = 1;
    cfg.CachedRegionAddrBase  = {DRAMBase};
    cfg.CachedRegionLength    = {DRAMLength};

    // Debug module location (must match Ara SoC DEBUG window and PULP dm_mem)
    // - Debug window is mapped at DebugBase .. DebugBase + DebugLength.
    //   Here DebugBase = 0x1A11_0000, matching the Ibex demo system.
    // - CVA6 expects HaltAddress/ExceptionAddress as OFFSETS from DmBaseAddress.
    //   Use the standard offsets (0x800 / 0x808) and let DebugBase provide the absolute base.
    cfg.DebugEn               = 1'b1;
    cfg.DmBaseAddress         = DebugBase;
    cfg.HaltAddress           = 64'h800;
    cfg.ExceptionAddress      = 64'h808;

    // Return modified config
    return cfg;
  endfunction

  // Generate the user defined package, starting from the template one for RVV
  localparam config_pkg::cva6_user_cfg_t CVA6AraConfig_user = gen_usr_cva6_config(cva6_config_pkg::cva6_cfg);
  // Build the package
  localparam config_pkg::cva6_cfg_t CVA6AraConfig = build_config_pkg::build_config(CVA6AraConfig_user);

  // Define the exception type
  `CVA6_TYPEDEF_EXCEPTION(exception_t, CVA6AraConfig);

  // Standard interface
  `CVA6_INTF_TYPEDEF_ACC_REQ(accelerator_req_t, CVA6AraConfig, fpnew_pkg::roundmode_e);
  `CVA6_INTF_TYPEDEF_ACC_RESP(accelerator_resp_t, CVA6AraConfig, exception_t);
  // MMU interface
  `CVA6_INTF_TYPEDEF_MMU_REQ(acc_mmu_req_t, CVA6AraConfig);
  `CVA6_INTF_TYPEDEF_MMU_RESP(acc_mmu_resp_t, CVA6AraConfig, exception_t);
  // Accelerator - CVA6's top-level interface
  `CVA6_INTF_TYPEDEF_CVA6_TO_ACC(cva6_to_acc_t, accelerator_req_t, acc_mmu_resp_t);
  `CVA6_INTF_TYPEDEF_ACC_TO_CVA6(acc_to_cva6_t, accelerator_resp_t, acc_mmu_req_t);

`ifndef TARGET_GATESIM
  ara_system #(
    .NrLanes           (NrLanes              ),
    .VLEN              (VLEN                 ),
    .OSSupport         (OSSupport            ),
    .FPUSupport        (FPUSupport           ),
    .FPExtSupport      (FPExtSupport         ),
    .FixPtSupport      (FixPtSupport         ),
    .SegSupport        (SegSupport           ),
    .CVA6Cfg           (CVA6AraConfig        ),
    .exception_t       (exception_t          ),
    .accelerator_req_t (accelerator_req_t    ),
    .accelerator_resp_t(accelerator_resp_t   ),
    .acc_mmu_req_t     (acc_mmu_req_t        ),
    .acc_mmu_resp_t    (acc_mmu_resp_t       ),
    .cva6_to_acc_t     (cva6_to_acc_t        ),
    .acc_to_cva6_t     (acc_to_cva6_t        ),
    .AxiAddrWidth      (AxiAddrWidth         ),
    .AxiIdWidth        (AxiCoreIdWidth       ),
    .AxiNarrowDataWidth(AxiNarrowDataWidth   ),
    .AxiWideDataWidth  (AxiDataWidth         ),
    .ara_axi_ar_t      (ara_axi_ar_chan_t    ),
    .ara_axi_aw_t      (ara_axi_aw_chan_t    ),
    .ara_axi_b_t       (ara_axi_b_chan_t     ),
    .ara_axi_r_t       (ara_axi_r_chan_t     ),
    .ara_axi_w_t       (ara_axi_w_chan_t     ),
    .ara_axi_req_t     (ara_axi_req_t        ),
    .ara_axi_resp_t    (ara_axi_resp_t       ),
    .ariane_axi_ar_t   (ariane_axi_ar_chan_t ),
    .ariane_axi_aw_t   (ariane_axi_aw_chan_t ),
    .ariane_axi_b_t    (ariane_axi_b_chan_t  ),
    .ariane_axi_r_t    (ariane_axi_r_chan_t  ),
    .ariane_axi_w_t    (ariane_axi_w_chan_t  ),
    .ariane_axi_req_t  (ariane_axi_req_t     ),
    .ariane_axi_resp_t (ariane_axi_resp_t    ),
    .system_axi_ar_t   (system_ar_chan_t     ),
    .system_axi_aw_t   (system_aw_chan_t     ),
    .system_axi_b_t    (system_b_chan_t      ),
    .system_axi_r_t    (system_r_chan_t      ),
    .system_axi_w_t    (system_w_chan_t      ),
    .system_axi_req_t  (system_req_t         ),
    .system_axi_resp_t (system_resp_t        ))
`else
  ara_system
`endif
i_system (
  .clk_i        (clk_i                    ),
  // Only reset the core complex (CVA6+Ara) with the core-level reset.
  // This allows the debug module's ndmreset to hold the core in reset
  // while leaving the SoC fabric + L2 SRAM accessible for SBA.
  .rst_ni       (core_rst_ni_i            ),
  .boot_addr_i  (DRAMBase                 ), // start fetching from DRAM
  .hart_id_i    (hart_id                  ),
  .scan_enable_i(1'b0                     ),
  .scan_data_i  (1'b0                     ),
  .scan_data_o  (/* Unconnected */        ),
  .debug_req_i  (debug_req_i              ),
`ifndef TARGET_GATESIM
    .axi_req_o    (system_axi_req           ),
    .axi_resp_i   (system_axi_resp          )
  );
`else
    .axi_req_o    (system_axi_req_spill     ),
    .axi_resp_i   (system_axi_resp_spill_del)
  );
`endif


`ifdef TARGET_GATESIM
  assign #(AxiRespDelay*1ps) system_axi_resp_spill_del = system_axi_resp_spill;

  axi_cut #(
    .ar_chan_t   (system_ar_chan_t     ),
    .aw_chan_t   (system_aw_chan_t     ),
    .b_chan_t    (system_b_chan_t      ),
    .r_chan_t    (system_r_chan_t      ),
    .w_chan_t    (system_w_chan_t      ),
    .req_t       (system_req_t         ),
    .resp_t      (system_resp_t        )
  ) i_system_cut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .slv_req_i   (system_axi_req_spill),
    .slv_resp_o  (system_axi_resp_spill),
    .mst_req_o   (system_axi_req),
    .mst_resp_i  (system_axi_resp)
  );
`endif

  //////////////////
  //  Assertions  //
  //////////////////

  if (NrLanes == 0)
    $error("[ara_soc] Ara needs to have at least one lane.");

  if (AxiDataWidth == 0)
    $error("[ara_soc] The AXI data width must be greater than zero.");

  if (AxiAddrWidth == 0)
    $error("[ara_soc] The AXI address width must be greater than zero.");

  if (AxiUserWidth == 0)
    $error("[ara_soc] The AXI user width must be greater than zero.");

  if (AxiIdWidth == 0)
    $error("[ara_soc] The AXI ID width must be greater than zero.");

  if (RVVD(FPUSupport) && !CVA6AraConfig.RVD)
    $error(
      "[ara] Cannot support double-precision floating-point on Ara if CVA6 does not support it.");

  if (RVVF(FPUSupport) && !CVA6AraConfig.RVF)
    $error(
      "[ara] Cannot support single-precision floating-point on Ara if CVA6 does not support it.");

  if (RVVH(FPUSupport) && !CVA6AraConfig.XF16)
    $error(
      "[ara] Cannot support half-precision floating-point on Ara if CVA6 does not support it.");

  if (RVVHA(FPUSupport) && !CVA6AraConfig.XF16ALT)
    $error(
      "[ara] Cannot support alt-half-precision floating-point on Ara if CVA6 does not support it.");

  if (RVVB(FPUSupport) && !CVA6AraConfig.XF8)
    $error(
      "[ara] Cannot support byte-precision floating-point on Ara if CVA6 does not support it.");

  if (RVVBA(FPUSupport) && !CVA6AraConfig.XF8ALT)
    $error(
      "[ara] Cannot support alt-byte-precision floating-point on Ara if CVA6 does not support it.");

endmodule : ara_soc
