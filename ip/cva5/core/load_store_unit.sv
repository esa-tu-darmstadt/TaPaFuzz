/*
 * Copyright © 2017-2019 Eric Matthews,  Lesley Shannon
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
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Eric Matthews <ematthew@sfu.ca>
 */

module load_store_unit

    import taiga_config::*;
    import riscv_types::*;
    import taiga_types::*;

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG
    )

    (
        input logic clk,
        input logic rst,
        input gc_outputs_t gc,

        input load_store_inputs_t ls_inputs,
        unit_issue_interface.unit issue,

        input logic dcache_on,
        input logic clear_reservation,
        tlb_interface.requester tlb,
        input logic tlb_on,

        l1_arbiter_request_interface.master l1_request,
        l1_arbiter_return_interface.master l1_response,
        input sc_complete,
        input sc_success,

        axi_interface.master m_axi,
        avalon_interface.master m_avalon,
        wishbone_interface.master m_wishbone,

        local_memory_interface.master data_bram,

        //Writeback-Store Interface
        input wb_packet_t wb_snoop,

        //Retire release
        input id_t retire_ids [RETIRE_PORTS],
        input logic retire_port_valid [RETIRE_PORTS],

        exception_interface.unit exception,
        output logic sq_empty,
        output logic no_released_stores_pending,
        output logic load_store_idle,
        unit_writeback_interface.unit wb,

        output logic tr_load_conflict_delay,
        
        //Custom
        input logic dcache_set_invalidate_all, //Only used during rst.
        output logic dcache_invalidating_all //Set in response to dcache_set_invalidate_all, reset on completion.
    );

    localparam NUM_SUB_UNITS = int'(CONFIG.INCLUDE_DLOCAL_MEM) + int'(CONFIG.INCLUDE_PERIPHERAL_BUS) + int'(CONFIG.INCLUDE_DCACHE);
    localparam NUM_SUB_UNITS_W = (NUM_SUB_UNITS == 1) ? 1 : $clog2(NUM_SUB_UNITS);

    localparam BRAM_ID = 0;
    localparam BUS_ID = int'(CONFIG.INCLUDE_DLOCAL_MEM);
    localparam DCACHE_ID = int'(CONFIG.INCLUDE_DLOCAL_MEM) + int'(CONFIG.INCLUDE_PERIPHERAL_BUS);

    //Should be equal to pipeline depth of longest load/store subunit 
    localparam ATTRIBUTES_DEPTH = CONFIG.INCLUDE_DCACHE ? 2 : 1;

    data_access_shared_inputs_t shared_inputs;
    ls_sub_unit_interface #(.BASE_ADDR(CONFIG.DLOCAL_MEM_ADDR.L), .UPPER_BOUND(CONFIG.DLOCAL_MEM_ADDR.H)) bram();
    ls_sub_unit_interface #(.BASE_ADDR(CONFIG.PERIPHERAL_BUS_ADDR.L), .UPPER_BOUND(CONFIG.PERIPHERAL_BUS_ADDR.H)) bus();
    ls_sub_unit_interface #(.BASE_ADDR(CONFIG.DCACHE_ADDR.L), .UPPER_BOUND(CONFIG.DCACHE_ADDR.H)) cache();

    logic units_ready;
    logic unit_switch_stall;
    logic ready_for_issue_from_lsq;
    logic issue_request;
    logic load_complete;

    logic [31:0] virtual_address;

    logic [31:0] unit_muxed_load_data;
    logic [31:0] aligned_load_data;
    logic [31:0] final_load_data;

    logic [31:0] unit_data_array [NUM_SUB_UNITS-1:0];
    logic [NUM_SUB_UNITS-1:0] unit_ready;
    logic [NUM_SUB_UNITS-1:0] unit_data_valid;
    logic [NUM_SUB_UNITS-1:0] last_unit;
    logic [NUM_SUB_UNITS-1:0] current_unit;

    logic unaligned_addr;
    logic mem_access_fault;
    logic load_exception_complete;
    //Added: Pre-LSQ address match check for access fault detection.
    logic [NUM_SUB_UNITS-1:0] sub_unit_address_match_early;
    logic [NUM_SUB_UNITS-1:0] sub_unit_address_match;
    logic fence_hold;
    logic unit_stall;

    typedef struct packed{
        logic [2:0] fn3;
        logic [1:0] byte_addr;
        id_t id;
        logic [NUM_SUB_UNITS_W-1:0] subunit_id;
    } load_attributes_t;
    load_attributes_t  load_attributes_in, stage2_attr;

    logic [3:0] be;
    //FIFOs
    fifo_interface #(.DATA_WIDTH($bits(load_attributes_t))) load_attributes();

    load_store_queue_interface lsq();
    logic tr_possible_load_conflict_delay;

    ////////////////////////////////////////////////////
    //Implementation
    ////////////////////////////////////////////////////


    ////////////////////////////////////////////////////
    //Alignment Exception
generate if (CONFIG.INCLUDE_M_MODE) begin : gen_ls_exceptions
    logic new_alignment_exception;
    logic new_exception;
    always_comb begin
        case(ls_inputs.fn3)
            LS_H_fn3, L_HU_fn3 : unaligned_addr = virtual_address[0];
            LS_W_fn3 : unaligned_addr = |virtual_address[1:0];
            default : unaligned_addr = 0;
        endcase
    end

    assign new_exception = (unaligned_addr | mem_access_fault) & issue.new_request & ~ls_inputs.fence;
    always_ff @(posedge clk) begin
        if (rst)
            exception.valid <= 0;
        else
            exception.valid <= (exception.valid & ~exception.ack) | new_exception;
    end

    always_ff @(posedge clk) begin
        if (new_exception & ~exception.valid) begin
            if (mem_access_fault) begin
                exception.code <= ls_inputs.store ? STORE_AMO_FAULT : LOAD_FAULT;
            end
            else begin //unaligned_addr
                exception.code <= ls_inputs.store ? STORE_AMO_ADDR_MISSALIGNED : LOAD_ADDR_MISSALIGNED;
            end
            exception.tval <= virtual_address;
            exception.id <= issue.id;
        end
    end

    always_ff @(posedge clk) begin
        if (rst)
            load_exception_complete <= 0;
        else
            load_exception_complete <= exception.valid & exception.ack &
                ((exception.code == LOAD_ADDR_MISSALIGNED) | (exception.code == LOAD_FAULT));
    end
end
endgenerate
    ////////////////////////////////////////////////////
    //TLB interface
    assign virtual_address = ls_inputs.rs1 + 32'(signed'(ls_inputs.offset));

    assign tlb.virtual_address = virtual_address;
    assign tlb.new_request = tlb_on & issue_request;
    assign tlb.execute = 0;
    assign tlb.rnw = ls_inputs.load & ~ls_inputs.store;

    ////////////////////////////////////////////////////
    //Byte enable generation
    //Only set on store
    //  SW: all bytes
    //  SH: upper or lower half of bytes
    //  SB: specific byte
    always_comb begin
        be = 0;
        case(ls_inputs.fn3[1:0])
            LS_B_fn3[1:0] : be[virtual_address[1:0]] = 1;
            LS_H_fn3[1:0] : begin
                be[virtual_address[1:0]] = 1;
                be[{virtual_address[1], 1'b1}] = 1;
            end
            default : be = '1;
        endcase
    end

    ////////////////////////////////////////////////////
    //Load Store Queue
    assign lsq.addr = tlb_on ? tlb.physical_address : virtual_address;
    assign lsq.fn3 = ls_inputs.fn3;
    assign lsq.be = be;
    assign lsq.data_in = ls_inputs.rs2;
    assign lsq.load = ls_inputs.load;
    assign lsq.store = ls_inputs.store;
    assign lsq.id = issue.id;
    assign lsq.forwarded_store = ls_inputs.forwarded_store;
    assign lsq.data_id = ls_inputs.store_forward_id;
    
    //Access fault detection (is optional: RISC-V Instruction Set Manual Volume II, 3.6 Physical Memory Attributes).
    assign mem_access_fault = (CONFIG.INCLUDE_M_MODE) & (~tlb_on | tlb.done) & ~(|sub_unit_address_match_early);

    assign lsq.possible_issue = issue.possible_issue;
    assign lsq.new_issue = issue.new_request & ~unaligned_addr & ~mem_access_fault & (~tlb_on | tlb.done) & ~ls_inputs.fence;

    load_store_queue lsq_block (
        .clk (clk),
        .rst (rst),
        .gc (gc),
        .lsq (lsq),
        .wb_snoop (wb_snoop),
        .retire_ids (retire_ids),
        .retire_port_valid (retire_port_valid),
        .tr_possible_load_conflict_delay (tr_possible_load_conflict_delay)
    );
    assign shared_inputs = lsq.transaction_out;
    assign lsq.accepted = issue_request;


    ////////////////////////////////////////////////////
    //Unit tracking
    assign current_unit = sub_unit_address_match;

    initial last_unit = BRAM_ID;
    //Workaround: Use always instead of always_ff since the Questa simulator does not like the initial statement otherwise.
    always @ (posedge clk) begin
        if (load_attributes.push)
            last_unit <= sub_unit_address_match;
    end

    //When switching units, ensure no outstanding loads so that there can be no timing collisions with results
    assign unit_stall = (current_unit != last_unit) && load_attributes.valid;
    set_clr_reg_with_rst #(.SET_OVER_CLR(1), .WIDTH(1), .RST_VALUE(0)) unit_switch_stall_m (
      .clk, .rst,
      .set(issue_request && (current_unit != last_unit) && load_attributes.valid),
      .clr(~load_attributes.valid),
      .result(unit_switch_stall)
    );

    ////////////////////////////////////////////////////
    //Primary Control Signals
    assign units_ready = &unit_ready;
    assign load_complete = |unit_data_valid;

    assign ready_for_issue_from_lsq = units_ready & (~unit_switch_stall);

    assign issue.ready = (~tlb_on | tlb.ready) & lsq.ready & ~fence_hold & ~exception.valid;
    assign issue_request = lsq.transaction_ready & ready_for_issue_from_lsq;

    assign sq_empty = lsq.sq_empty;
    assign no_released_stores_pending = lsq.no_released_stores_pending;
    assign load_store_idle = lsq.empty & units_ready;

    always_ff @ (posedge clk) begin
        if (rst)
            fence_hold <= 0;
        else
            fence_hold <= (fence_hold & ~load_store_idle) | (issue.new_request & ls_inputs.fence);
    end

    ////////////////////////////////////////////////////
    //Load attributes FIFO
    one_hot_to_integer #(NUM_SUB_UNITS)
    sub_unit_select (
        .one_hot (sub_unit_address_match), 
        .int_out (load_attributes_in.subunit_id)
    );
    taiga_fifo #(.DATA_WIDTH($bits(load_attributes_t)), .FIFO_DEPTH(ATTRIBUTES_DEPTH)) attributes_fifo (
        .clk        (clk),
        .rst        (rst), 
        .fifo       (load_attributes)
    );
    assign load_attributes_in.fn3 = shared_inputs.fn3;
    assign load_attributes_in.byte_addr = shared_inputs.addr[1:0];
    assign load_attributes_in.id = shared_inputs.id;

    assign load_attributes.data_in = load_attributes_in;
    assign load_attributes.push = issue_request & shared_inputs.load;
    assign load_attributes.potential_push = issue_request & shared_inputs.load;
    assign load_attributes.pop = load_complete;

    assign stage2_attr = load_attributes.data_out;

    ////////////////////////////////////////////////////
    //Unit Instantiation
    generate if (CONFIG.INCLUDE_DLOCAL_MEM) begin : gen_ls_local_mem
            assign sub_unit_address_match_early[BRAM_ID] = bram.address_range_check(lsq.addr);
            assign sub_unit_address_match[BRAM_ID] = bram.address_range_check(shared_inputs.addr);
            assign bram.new_request = sub_unit_address_match[BRAM_ID] & issue_request;

            assign unit_ready[BRAM_ID] = bram.ready;
            assign unit_data_valid[BRAM_ID] = bram.data_valid;

            dbram d_bram (
                .clk        (clk),
                .rst        (rst),  
                .ls_inputs  (shared_inputs), 
                .ls         (bram), 
                .data_out   (unit_data_array[BRAM_ID]),
                .data_bram  (data_bram)
            );
        end
    endgenerate

    generate if (CONFIG.INCLUDE_PERIPHERAL_BUS) begin : gen_ls_pbus
            assign sub_unit_address_match_early[BUS_ID] = bus.address_range_check(lsq.addr);
            assign sub_unit_address_match[BUS_ID] = bus.address_range_check(shared_inputs.addr);
            assign bus.new_request = sub_unit_address_match[BUS_ID] & issue_request;

            assign unit_ready[BUS_ID] = bus.ready;
            assign unit_data_valid[BUS_ID] = bus.data_valid;

            if(CONFIG.PERIPHERAL_BUS_TYPE == AXI_BUS)
                axi_master axi_bus (
                    .clk            (clk),
                    .rst            (rst),
                    .m_axi          (m_axi),
                    .size           ({1'b0,shared_inputs.fn3[1:0]}),
                    .data_out       (unit_data_array[BUS_ID]),
                    .ls_inputs      (shared_inputs),
                    .ls             (bus)
                ); //Lower two bits of fn3 match AXI specification for request size (byte/halfword/word)

            else if (CONFIG.PERIPHERAL_BUS_TYPE == WISHBONE_BUS)
                wishbone_master wishbone_bus (
                    .clk            (clk),
                    .rst            (rst),
                    .m_wishbone     (m_wishbone),
                    .data_out       (unit_data_array[BUS_ID]),
                    .ls_inputs      (shared_inputs), 
                    .ls             (bus) 
                );
            else if (CONFIG.PERIPHERAL_BUS_TYPE == AVALON_BUS)  begin
                avalon_master avalon_bus (
                    .clk            (clk),
                    .rst            (rst),
                    .ls_inputs      (shared_inputs), 
                    .m_avalon       (m_avalon), 
                    .ls             (bus), 
                    .data_out       (unit_data_array[BUS_ID])
                );
            end
        end
    endgenerate

    generate if (CONFIG.INCLUDE_DCACHE) begin : gen_ls_dcache
            assign sub_unit_address_match_early[DCACHE_ID] = cache.address_range_check(lsq.addr);
            assign sub_unit_address_match[DCACHE_ID] = cache.address_range_check(shared_inputs.addr);
            assign cache.new_request = sub_unit_address_match[DCACHE_ID] & issue_request;

            assign unit_ready[DCACHE_ID] = cache.ready;
            assign unit_data_valid[DCACHE_ID] = cache.data_valid;

            dcache # (.CONFIG(CONFIG))
            data_cache (
                .clk                    (clk),
                .rst                    (rst),
                .dcache_on              (dcache_on),
                .l1_request             (l1_request),
                .l1_response            (l1_response),
                .sc_complete            (sc_complete),
                .sc_success             (sc_success),
                .clear_reservation      (clear_reservation),
                .ls_inputs              (shared_inputs),
                .data_out               (unit_data_array[DCACHE_ID]),
                .amo                    (ls_inputs.amo),
                .ls                     (cache),
                .set_invalidate_all     (dcache_set_invalidate_all),
                .invalidating_all       (dcache_invalidating_all)
            );
        end
    endgenerate

    ////////////////////////////////////////////////////
    //Output Muxing
    assign unit_muxed_load_data = unit_data_array[stage2_attr.subunit_id];

    //Byte/halfword select: assumes aligned operations
    always_comb begin
        aligned_load_data[31:16] = unit_muxed_load_data[31:16];
        aligned_load_data[15:0] = stage2_attr.byte_addr[1] ? unit_muxed_load_data[31:16] : unit_muxed_load_data[15:0];
        //select halfword first then byte
        aligned_load_data[7:0] = stage2_attr.byte_addr[0] ? aligned_load_data[15:8] : aligned_load_data[7:0];
    end

    //Sign extending
    always_comb begin
        case(stage2_attr.fn3)
            LS_B_fn3 : final_load_data = 32'(signed'(aligned_load_data[7:0]));
            LS_H_fn3 : final_load_data = 32'(signed'(aligned_load_data[15:0]));
            LS_W_fn3 : final_load_data = aligned_load_data;
                //unused 011
            L_BU_fn3 : final_load_data = 32'(unsigned'(aligned_load_data[7:0]));
            L_HU_fn3 : final_load_data = 32'(unsigned'(aligned_load_data[15:0]));
                //unused 110
                //unused 111
            default : final_load_data = aligned_load_data;
        endcase
    end

    ////////////////////////////////////////////////////
    //Output bank
    assign wb.rd = final_load_data;
    assign wb.done = load_complete | load_exception_complete;
    assign wb.id = load_exception_complete ? exception.id : stage2_attr.id;

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    spurious_load_complete_assertion:
        assert property (@(posedge clk) disable iff (rst) load_complete |-> (load_attributes.valid && unit_data_valid[stage2_attr.subunit_id]))
        else $error("Spurious load complete detected!");

    // `ifdef ENABLE_SIMULATION_ASSERTIONS
    //     invalid_ls_address_assertion:
    //         assert property (@(posedge clk) disable iff (rst) (issue_request & ~ls_inputs.fence) |-> |sub_unit_address_match)
    //         else $error("invalid L/S address");
    // `endif

    ////////////////////////////////////////////////////
    //Trace Interface
    generate if (ENABLE_TRACE_INTERFACE) begin : gen_ls_trace
        assign tr_load_conflict_delay = tr_possible_load_conflict_delay & ready_for_issue_from_lsq;
    end
    endgenerate

endmodule
