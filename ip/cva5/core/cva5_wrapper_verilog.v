/*
 * Copyright © 2022 Carsten Heinz
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module cva5_wrapper_verilog (
	input wire clk,
	input wire rst,

	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram CLK" *)
	output wire        instruction_bram_clk,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram RST" *)
	output wire        instruction_bram_rst,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram ADDR" *)
	output wire [29:0] instruction_bram_addr,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram EN" *)
	output wire        instruction_bram_en,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram WE" *)
	output wire [3:0]  instruction_bram_we,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram DIN" *)
	output wire [31:0] instruction_bram_din,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 instruction_bram DOUT" *)
	input  wire [31:0] instruction_bram_dout,

	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram CLK" *)
	output wire        data_bram_clk,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram RST" *)
	output wire        data_bram_rst,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram ADDR" *)
	output wire [29:0] data_bram_addr,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram EN" *)
	output wire        data_bram_en,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram WE" *)
	output wire [3:0]  data_bram_we,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram DIN" *)
	output wire [31:0] data_bram_din,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 data_bram DOUT" *)
	input  wire [31:0] data_bram_dout,

	// AXI Bus
	// AXI Write Channels
	output wire                            m_axi_awvalid,
	input  wire                            m_axi_awready,
	//~ output wire [5:0]                      m_axi_awid,
	output wire [31:0]                     m_axi_awaddr,
	//~ output wire [3:0]                      m_axi_awregion,
	output wire [7:0]                      m_axi_awlen,
	output wire [2:0]                      m_axi_awsize,
	output wire [1:0]                      m_axi_awburst,
	//~ output wire                            m_axi_awlock,
	output wire [3:0]                      m_axi_awcache,
	//~ output wire [2:0]                      m_axi_awprot,
	//~ output wire [3:0]                      m_axi_awqos,

	output wire                            m_axi_wvalid,
	input  wire                            m_axi_wready,
	output wire [31:0]                     m_axi_wdata,
	output wire [3:0]                      m_axi_wstrb,
	output wire                            m_axi_wlast,

	input  wire                            m_axi_bvalid,
	output wire                            m_axi_bready,
	input  wire [1:0]                      m_axi_bresp,
	//~ input  wire [5:0]                      m_axi_bid,

	// AXI Read Channels
	output wire                            m_axi_arvalid,
	input  wire                            m_axi_arready,
	//~ output wire [5:0]                      m_axi_arid,
	output wire [31:0]                     m_axi_araddr,
	//~ output wire [3:0]                      m_axi_arregion,
	output wire [7:0]                      m_axi_arlen,
	output wire [2:0]                      m_axi_arsize,
	output wire [1:0]                      m_axi_arburst,
	//~ output wire                            m_axi_arlock,
	output wire [3:0]                      m_axi_arcache,
	//~ output wire [2:0]                      m_axi_arprot,
	//~ output wire [3:0]                      m_axi_arqos,

	input  wire                            m_axi_rvalid,
	output wire                            m_axi_rready,
	//~ input  wire [5:0]                      m_axi_rid,
	input  wire [31:0]                     m_axi_rdata,
	input  wire [1:0]                      m_axi_rresp,
	input  wire                            m_axi_rlast,

	// AXI Cache
	// AXI Write Channels
	output wire                            m_axi_cache_awvalid,
	input  wire                            m_axi_cache_awready,
	output wire [5:0]                      m_axi_cache_awid,
	output wire [31:0]                     m_axi_cache_awaddr,
	//~ output wire [3:0]                      m_axi_cache_awregion,
	output wire [7:0]                      m_axi_cache_awlen,
	output wire [2:0]                      m_axi_cache_awsize,
	output wire [1:0]                      m_axi_cache_awburst,
	//~ output wire                            m_axi_cache_awlock,
	output wire [3:0]                      m_axi_cache_awcache,
	output wire [2:0]                      m_axi_cache_awprot,
	//~ output wire [3:0]                      m_axi_cache_awqos,

	output wire                            m_axi_cache_wvalid,
	input  wire                            m_axi_cache_wready,
	output wire [31:0]                     m_axi_cache_wdata,
	output wire [3:0]                      m_axi_cache_wstrb,
	output wire                            m_axi_cache_wlast,

	input  wire                            m_axi_cache_bvalid,
	output wire                            m_axi_cache_bready,
	input  wire [1:0]                      m_axi_cache_bresp,
	input  wire [5:0]                      m_axi_cache_bid,

	// AXI Read Channels
	output wire                            m_axi_cache_arvalid,
	input  wire                            m_axi_cache_arready,
	output wire [5:0]                      m_axi_cache_arid,
	output wire [31:0]                     m_axi_cache_araddr,
	//~ output wire [3:0]                      m_axi_cache_arregion,
	output wire [7:0]                      m_axi_cache_arlen,
	output wire [2:0]                      m_axi_cache_arsize,
	output wire [1:0]                      m_axi_cache_arburst,
	//~ output wire                            m_axi_cache_arlock,
	output wire [3:0]                      m_axi_cache_arcache,
	output wire [2:0]                      m_axi_cache_arprot,
	//~ output wire [3:0]                      m_axi_cache_arqos,

	input  wire                            m_axi_cache_rvalid,
	output wire                            m_axi_cache_rready,
	input  wire [5:0]                      m_axi_cache_rid,
	input  wire [31:0]                     m_axi_cache_rdata,
	input  wire [1:0]                      m_axi_cache_rresp,
	input  wire                            m_axi_cache_rlast,

	output wire tr_early_branch_correction,
    output wire tr_operand_stall,
    output wire tr_unit_stall,
    output wire tr_no_id_stall,
    output wire tr_no_instruction_stall,
    output wire tr_other_stall,
    output wire tr_branch_operand_stall,
    output wire tr_alu_operand_stall,
    output wire tr_ls_operand_stall,
    output wire tr_div_operand_stall,
    output wire tr_alu_op,
    output wire tr_branch_or_jump_op,
	output wire tr_load_op,
    output wire tr_store_op,
    output wire tr_mul_op,
    output wire tr_div_op,
    output wire tr_misc_op, 
    output wire tr_instruction_issued_dec,
    output wire [31:0] tr_instruction_pc_dec,
    output wire [31:0] tr_instruction_data_dec,
    output wire tr_branch_correct,
    output wire tr_branch_misspredict,
    output wire tr_return_correct,
    output wire tr_return_misspredict, 
    output wire tr_load_conflict_delay,
    output wire tr_rs1_forwarding_needed,
    output wire tr_rs2_forwarding_needed,
    output wire tr_rs1_and_rs2_forwarding_needed,
	
	input wire dexie_stall,
	output wire fuzztr_exception_valid,
	output wire [4:0] fuzztr_exception_code, //mcause, scause value
	output wire [31:0] fuzztr_exception_tval, //mtval, stval value
	output wire [31:0] fuzztr_exception_pc,  //mepc, sepc
		
	input wire icache_set_invalidate_all,
	output wire icache_invalidating_all,
	input wire bp_set_invalidate_all,
	output wire bp_invalidating_all,
	input wire dcache_set_invalidate_all,
	output wire dcache_invalidating_all
);

assign instruction_bram_clk = clk;
assign instruction_bram_rst = rst;
assign data_bram_clk = clk;
assign data_bram_rst = rst;

wire [5:0]                      m_axi_awid;
wire [5:0]                      m_axi_bid;
wire [5:0]                      m_axi_arid;
wire [5:0]                      m_axi_rid;


cva5_wrapper cva5_wrapper (
	.clk(clk),
	.rst(rst),

	.instruction_bram_addr(instruction_bram_addr),
	.instruction_bram_en(instruction_bram_en),
	.instruction_bram_we(instruction_bram_we),
	.instruction_bram_din(instruction_bram_din),
	.instruction_bram_dout(instruction_bram_dout),

	.data_bram_addr(data_bram_addr),
	.data_bram_en(data_bram_en),
	.data_bram_we(data_bram_we),
	.data_bram_din(data_bram_din),
	.data_bram_dout(data_bram_dout),

	// AXI Bus
	.m_axi_awvalid(m_axi_awvalid),
	.m_axi_awready(m_axi_awready),
	.m_axi_awid(m_axi_awid),
	.m_axi_awaddr(m_axi_awaddr),
	//~ .m_axi_awregion(m_axi_awregion),
	.m_axi_awlen(m_axi_awlen),
	.m_axi_awsize(m_axi_awsize),
	.m_axi_awburst(m_axi_awburst),
	//~ .m_axi_awlock(m_axi_awlock),
	.m_axi_awcache(m_axi_awcache),
	//~ .m_axi_awprot(m_axi_awprot),
	//~ .m_axi_awqos(m_axi_awqos),

	.m_axi_wvalid(m_axi_wvalid),
	.m_axi_wready(m_axi_wready),
	.m_axi_wdata(m_axi_wdata),
	.m_axi_wstrb(m_axi_wstrb),
	.m_axi_wlast(m_axi_wlast),

	.m_axi_bvalid(m_axi_bvalid),
	.m_axi_bready(m_axi_bready),
	.m_axi_bresp(m_axi_bresp),
	.m_axi_bid(m_axi_bid),

	.m_axi_arvalid(m_axi_arvalid),
	.m_axi_arready(m_axi_arready),
	.m_axi_arid(m_axi_arid),
	.m_axi_araddr(m_axi_araddr),
	//~ .m_axi_arregion(m_axi_arregion),
	.m_axi_arlen(m_axi_arlen),
	.m_axi_arsize(m_axi_arsize),
	.m_axi_arburst(m_axi_arburst),
	//~ .m_axi_arlock(m_axi_arlock),
	.m_axi_arcache(m_axi_arcache),
	//~ .m_axi_arprot(m_axi_arprot),
	//~ .m_axi_arqos(m_axi_arqos),

	.m_axi_rvalid(m_axi_rvalid),
	.m_axi_rready(m_axi_rready),
	.m_axi_rid(m_axi_rid),
	.m_axi_rdata(m_axi_rdata),
	.m_axi_rresp(m_axi_rresp),
	.m_axi_rlast(m_axi_rlast),

	// AXI Cache
	.axi_awvalid(m_axi_cache_awvalid),
	.axi_awready(m_axi_cache_awready),
	.axi_awid(m_axi_cache_awid),
	.axi_awaddr(m_axi_cache_awaddr),
	//~ .axi_awregion(m_axi_cache_awregion),
	.axi_awlen(m_axi_cache_awlen),
	.axi_awsize(m_axi_cache_awsize),
	.axi_awburst(m_axi_cache_awburst),
	//~ .axi_awlock(m_axi_cache_awlock),
	.axi_awcache(m_axi_cache_awcache),
	.axi_awprot(m_axi_cache_awprot),
	//~ .axi_awqos(m_axi_cache_awqos),

	.axi_wvalid(m_axi_cache_wvalid),
	.axi_wready(m_axi_cache_wready),
	.axi_wdata(m_axi_cache_wdata),
	.axi_wstrb(m_axi_cache_wstrb),
	.axi_wlast(m_axi_cache_wlast),

	.axi_bvalid(m_axi_cache_bvalid),
	.axi_bready(m_axi_cache_bready),
	.axi_bresp(m_axi_cache_bresp),
	.axi_bid(m_axi_cache_bid),

	.axi_arvalid(m_axi_cache_arvalid),
	.axi_arready(m_axi_cache_arready),
	.axi_arid(m_axi_cache_arid),
	.axi_araddr(m_axi_cache_araddr),
	//~ .axi_arregion(m_axi_cache_arregion),
	.axi_arlen(m_axi_cache_arlen),
	.axi_arsize(m_axi_cache_arsize),
	.axi_arburst(m_axi_cache_arburst),
	//~ .axi_arlock(m_axi_cache_arlock),
	.axi_arcache(m_axi_cache_arcache),
	.axi_arprot(m_axi_cache_arprot),
	//~ .axi_arqos(m_axi_cache_arqos),

	.axi_rvalid(m_axi_cache_rvalid),
	.axi_rready(m_axi_cache_rready),
	.axi_rid(m_axi_cache_rid),
	.axi_rdata(m_axi_cache_rdata),
	.axi_rresp(m_axi_cache_rresp),
	.axi_rlast(m_axi_cache_rlast),

	.timer_interrupt(0),
	.interrupt(0),

	.tr_early_branch_correction(tr_early_branch_correction),
    .tr_operand_stall(tr_operand_stall),
    .tr_unit_stall(tr_unit_stall),
    .tr_no_id_stall(tr_no_id_stall),
    .tr_no_instruction_stall(tr_no_instruction_stall),
    .tr_other_stall(tr_other_stall),
    .tr_branch_operand_stall(tr_branch_operand_stall),
    .tr_alu_operand_stall(tr_alu_operand_stall),
    .tr_ls_operand_stall(tr_ls_operand_stall),
    .tr_div_operand_stall(tr_div_operand_stall),
    .tr_alu_op(tr_alu_op),
    .tr_branch_or_jump_op(tr_branch_or_jump_op),
	.tr_load_op(tr_load_op),
    .tr_store_op(tr_store_op),
    .tr_mul_op(tr_mul_op),
    .tr_div_op(tr_div_op),
    .tr_misc_op(tr_misc_op), 
    .tr_instruction_issued_dec(tr_instruction_issued_dec),
    .tr_instruction_pc_dec(tr_instruction_pc_dec),
    .tr_instruction_data_dec(tr_instruction_data_dec),

    .tr_branch_correct(tr_branch_correct),
    .tr_branch_misspredict(tr_branch_misspredict),
    .tr_return_correct(tr_return_correct),
    .tr_return_misspredict(tr_return_misspredict),
    .tr_load_conflict_delay(tr_load_conflict_delay),
    .tr_rs1_forwarding_needed(tr_rs1_forwarding_needed),
    .tr_rs2_forwarding_needed(tr_rs2_forwarding_needed),
    .tr_rs1_and_rs2_forwarding_needed(tr_rs1_and_rs2_forwarding_needed),
	
	.dexie_stall(dexie_stall),
	.fuzztr_exception_valid(fuzztr_exception_valid),
	.fuzztr_exception_code(fuzztr_exception_code),
	.fuzztr_exception_tval(fuzztr_exception_tval),
	.fuzztr_exception_pc(fuzztr_exception_pc),
	
	.icache_set_invalidate_all(icache_set_invalidate_all),
	.icache_invalidating_all(icache_invalidating_all),
	.bp_set_invalidate_all(bp_set_invalidate_all),
	.bp_invalidating_all(bp_invalidating_all),
	.dcache_set_invalidate_all(dcache_set_invalidate_all),
	.dcache_invalidating_all(dcache_invalidating_all)
);

endmodule
