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

module cva5_wrapper
    import taiga_config::*;
    import l2_config_and_types::*;
    import riscv_types::*;
    import taiga_types::*;
 (
	input logic clk,
	input logic rst,

	output wire [29:0] instruction_bram_addr,
	output wire        instruction_bram_en,
	output wire [3:0]  instruction_bram_we,
	output wire [31:0] instruction_bram_din,
	input  wire [31:0] instruction_bram_dout,

	output wire [29:0] data_bram_addr,
	output wire        data_bram_en,
	output wire [3:0]  data_bram_we,
	output wire [31:0] data_bram_din,
	input  wire [31:0] data_bram_dout,

	// AXI Bus
	// AXI Write Channels
	output wire                            m_axi_awvalid,
	input  wire                            m_axi_awready,
	output wire [5:0]                      m_axi_awid,
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
	input  wire [5:0]                      m_axi_bid,

	// AXI Read Channels
	output wire                            m_axi_arvalid,
	input  wire                            m_axi_arready,
	output wire [5:0]                      m_axi_arid,
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
	input  wire [5:0]                      m_axi_rid,
	input  wire [31:0]                     m_axi_rdata,
	input  wire [1:0]                      m_axi_rresp,
	input  wire                            m_axi_rlast,

	// AXI Cache
	// AXI Write Channels
	output wire                            axi_awvalid,
	input  wire                            axi_awready,
	output wire [5:0]                      axi_awid,
	output wire [31:0]                     axi_awaddr,
	//~ output wire [3:0]                      axi_awregion,
	output wire [7:0]                      axi_awlen,
	output wire [2:0]                      axi_awsize,
	output wire [1:0]                      axi_awburst,
	//~ output wire                            axi_awlock,
	output wire [3:0]                      axi_awcache,
	output wire [2:0]                      axi_awprot,
	//~ output wire [3:0]                      axi_awqos,

	output wire                            axi_wvalid,
	input  wire                            axi_wready,
	output wire [31:0]                     axi_wdata,
	output wire [3:0]                      axi_wstrb,
	output wire                            axi_wlast,

	input  wire                            axi_bvalid,
	output wire                            axi_bready,
	input  wire [1:0]                      axi_bresp,
	input  wire [5:0]                      axi_bid,

	// AXI Read Channels
	output wire                            axi_arvalid,
	input  wire                            axi_arready,
	output wire [5:0]                      axi_arid,
	output wire [31:0]                     axi_araddr,
	//~ output wire [3:0]                      axi_arregion,
	output wire [7:0]                      axi_arlen,
	output wire [2:0]                      axi_arsize,
	output wire [1:0]                      axi_arburst,
	//~ output wire                            axi_arlock,
	output wire [3:0]                      axi_arcache,
	output wire [2:0]                      axi_arprot,
	//~ output wire [3:0]                      axi_arqos,

	input  wire                            axi_rvalid,
	output wire                            axi_rready,
	input  wire [5:0]                      axi_rid,
	input  wire [31:0]                     axi_rdata,
	input  wire [1:0]                      axi_rresp,
	input  wire                            axi_rlast,

	input logic timer_interrupt,
	input logic interrupt,

	//Trace Interface Signals
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
	output wire [4:0] fuzztr_exception_code,
	output wire [31:0] fuzztr_exception_tval,
	output wire [31:0] fuzztr_exception_pc,
		
	input wire icache_set_invalidate_all,
	output wire icache_invalidating_all,
	input wire bp_set_invalidate_all,
	output wire bp_invalidating_all,
	input wire dcache_set_invalidate_all,
	output wire dcache_invalidating_all
);

wire ttr_early_branch_correction;
wire ttr_operand_stall;
wire ttr_unit_stall;
wire ttr_no_id_stall;
wire ttr_no_instruction_stall;
wire ttr_other_stall;
wire ttr_branch_operand_stall;
wire ttr_alu_operand_stall;
wire ttr_ls_operand_stall;
wire ttr_div_operand_stall;
wire ttr_alu_op;
wire ttr_branch_or_jump_op;
wire ttr_load_op;
wire ttr_store_op;
wire ttr_mul_op;
wire ttr_div_op;
wire ttr_misc_op;
wire ttr_instruction_issued_dec;
wire [31:0] ttr_instruction_pc_dec;
wire [31:0] ttr_instruction_data_dec;
wire ttr_branch_correct;
wire ttr_branch_misspredict;
wire ttr_return_correct;
wire ttr_return_misspredict;
wire ttr_load_conflict_delay;
wire ttr_rs1_forwarding_needed;
wire ttr_rs2_forwarding_needed;
wire ttr_rs1_and_rs2_forwarding_needed;

local_memory_interface instruction_bram();
assign instruction_bram_addr = {instruction_bram.addr[27:0],2'b0};
assign instruction_bram_en = instruction_bram.en;
assign instruction_bram_we = instruction_bram.be;
assign instruction_bram_din = instruction_bram.data_in;
assign instruction_bram.data_out = instruction_bram_dout;

local_memory_interface data_bram();
assign data_bram_addr = {data_bram.addr[27:0],2'b0};
assign data_bram_en = data_bram.en;
assign data_bram_we = data_bram.be;
assign data_bram_din = data_bram.data_in;
assign data_bram.data_out = data_bram_dout;

axi_interface m_axi();
assign m_axi_awvalid = m_axi.awvalid;
assign m_axi.awready = m_axi_awready;
assign m_axi_awid = m_axi.awid;
assign m_axi_awaddr = m_axi.awaddr;
assign m_axi_awlen = m_axi.awlen;
assign m_axi_awsize = m_axi.awsize;
assign m_axi_awburst = m_axi.awburst;
assign m_axi_awcache = m_axi.awcache;

assign m_axi_wvalid = m_axi.wvalid;
assign m_axi.wready = m_axi_wready;
assign m_axi_wdata = m_axi.wdata;
assign m_axi_wstrb = m_axi.wstrb;
assign m_axi_wlast = m_axi.wlast;

assign m_axi.bvalid = m_axi_bvalid;
assign m_axi_bready = m_axi.bready;
assign m_axi.bresp = m_axi_bresp;
assign m_axi.bid = m_axi_bid;

assign m_axi_arvalid = m_axi.arvalid;
assign m_axi.arready = m_axi_arready;
assign m_axi_arid = m_axi.arid;
assign m_axi_araddr = m_axi.araddr;
assign m_axi_arlen = m_axi.arlen;
assign m_axi_arsize = m_axi.arsize;
assign m_axi_arburst = m_axi.arburst;
assign m_axi_arcache = m_axi.arcache;

assign m_axi.rvalid = m_axi_rvalid;
assign m_axi_rready = m_axi.rready;
assign m_axi.rid = m_axi_rid;
assign m_axi.rdata = m_axi_rdata;
assign m_axi.rresp = m_axi_rresp;
assign m_axi.rlast = m_axi_rlast;

avalon_interface m_avalon();
wishbone_interface m_wishbone();

l2_requester_interface l2[L2_NUM_PORTS-1:0]();
assign l2[1].request_push = 0;
assign l2[1].wr_data_push = 0;
assign l2[1].inv_ack = l2[1].inv_valid;
assign l2[1].rd_data_ack = l2[1].rd_data_valid;

l2_memory_interface arb_mem();

assign tr_instruction_pc_dec = ttr_instruction_pc_dec;
assign tr_instruction_data_dec = ttr_instruction_data_dec;
assign tr_early_branch_correction = ttr_early_branch_correction;
assign tr_operand_stall = ttr_operand_stall;
assign tr_unit_stall = ttr_unit_stall;
assign tr_no_id_stall = ttr_no_id_stall;
assign tr_no_instruction_stall = ttr_no_instruction_stall;
assign tr_other_stall = ttr_other_stall;
assign tr_branch_operand_stall = ttr_branch_operand_stall;
assign tr_alu_operand_stall = ttr_alu_operand_stall;
assign tr_ls_operand_stall = ttr_ls_operand_stall;
assign tr_div_operand_stall = ttr_div_operand_stall;
assign tr_alu_op = ttr_alu_op;
assign tr_branch_or_jump_op = ttr_branch_or_jump_op;
assign tr_load_op = ttr_load_op;
assign tr_store_op = ttr_store_op;
assign tr_mul_op = ttr_mul_op;
assign tr_div_op = ttr_div_op;
assign tr_misc_op = ttr_misc_op;
assign tr_instruction_issued_dec = ttr_instruction_issued_dec;
assign tr_branch_correct = ttr_branch_correct;
assign tr_branch_misspredict = ttr_branch_misspredict;
assign tr_return_correct = ttr_return_correct;
assign tr_return_misspredict = ttr_return_misspredict;
assign tr_load_conflict_delay = ttr_load_conflict_delay;
assign tr_rs1_forwarding_needed = ttr_rs1_forwarding_needed;
assign tr_rs2_forwarding_needed = ttr_rs2_forwarding_needed;
assign tr_rs1_and_rs2_forwarding_needed = ttr_rs1_and_rs2_forwarding_needed;

taiga taiga (
	.clk(clk),
	.rst(rst),

	.instruction_bram(instruction_bram),
	.data_bram(data_bram),

	.m_axi(m_axi),
	.m_avalon(m_avalon),
	.m_wishbone(m_wishbone),
	.l2(l2[0]),

	.s_interrupt(0),
	.m_interrupt(0),
	.ttr_instruction_pc_dec(ttr_instruction_pc_dec),
	.ttr_instruction_data_dec(ttr_instruction_data_dec),
	.ttr_early_branch_correction(ttr_early_branch_correction),
	.ttr_operand_stall(ttr_operand_stall),
	.ttr_unit_stall(ttr_unit_stall),
	.ttr_no_id_stall(ttr_no_id_stall),
	.ttr_no_instruction_stall(ttr_no_instruction_stall),
	.ttr_other_stall(ttr_other_stall),
	.ttr_branch_operand_stall(ttr_branch_operand_stall),
	.ttr_alu_operand_stall(ttr_alu_operand_stall),
	.ttr_ls_operand_stall(ttr_ls_operand_stall),
	.ttr_div_operand_stall(ttr_div_operand_stall),
	.ttr_alu_op(ttr_alu_op),
	.ttr_branch_or_jump_op(ttr_branch_or_jump_op),
	.ttr_load_op(ttr_load_op),
	.ttr_store_op(ttr_store_op),
	.ttr_mul_op(ttr_mul_op),
	.ttr_div_op(ttr_div_op),
	.ttr_misc_op(ttr_misc_op),
	.ttr_instruction_issued_dec(ttr_instruction_issued_dec),
	.ttr_branch_correct(ttr_branch_correct),
	.ttr_branch_misspredict(ttr_branch_misspredict),
	.ttr_return_correct(ttr_return_correct),
	.ttr_return_misspredict(ttr_return_misspredict),
	.ttr_load_conflict_delay(ttr_load_conflict_delay),
	.ttr_rs1_forwarding_needed(ttr_rs1_forwarding_needed),
	.ttr_rs2_forwarding_needed(ttr_rs2_forwarding_needed),
	.ttr_rs1_and_rs2_forwarding_needed(ttr_rs1_and_rs2_forwarding_needed),
	
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

l2_arbiter l2_arb (
	.clk(clk),
	.rst(rst),
	.request(l2),
	.mem(arb_mem)
);

axi_to_arb l2_to_mem (
	.clk(clk),
	.rst(rst),
	.l2(arb_mem),
	.* // e.g. axi_*
);

endmodule
