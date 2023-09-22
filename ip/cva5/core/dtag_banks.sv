/*
 * Copyright © 2017 Eric Matthews,  Lesley Shannon
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

module dtag_banks 

    import taiga_config::*;
    import taiga_types::*;

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG,
        parameter derived_cache_config_t SCONFIG = '{default: 0}
    )

    (
        input logic clk,
        input logic rst,

        input logic[31:0] stage1_addr,
        input logic[31:0] stage2_addr,
        input logic[31:0] inv_addr,

        input logic[CONFIG.DCACHE.WAYS-1:0] update_way,
        input logic update,

        input logic stage1_adv,
        input logic stage1_inv,

        input logic inv_all_ways,
        input logic extern_inv,
        output logic extern_inv_complete,

        output tag_hit,
        output logic[CONFIG.DCACHE.WAYS-1:0] tag_hit_way
        );

    typedef struct packed{
        logic valid;
        logic [SCONFIG.TAG_W-1:0] tag;
    } dtag_entry_t;

    function logic[SCONFIG.TAG_W-1:0] getTag(logic[31:0] addr);
        return addr[2+SCONFIG.SUB_LINE_ADDR_W+SCONFIG.LINE_ADDR_W +: SCONFIG.TAG_W];
    endfunction

    function logic[SCONFIG.LINE_ADDR_W-1:0] getLineAddr(logic[31:0] addr);
        return addr[SCONFIG.LINE_ADDR_W + SCONFIG.SUB_LINE_ADDR_W + 1 : SCONFIG.SUB_LINE_ADDR_W + 2];
    endfunction

    dtag_entry_t  tag_line [CONFIG.DCACHE.WAYS - 1:0];
    dtag_entry_t  inv_tag_line [CONFIG.DCACHE.WAYS - 1:0];

    dtag_entry_t new_tagline;

    logic miss_or_extern_invalidate;
    logic [CONFIG.DCACHE.WAYS - 1:0] update_tag_way;

    logic inv_tags_accessed;

    logic[CONFIG.DCACHE.WAYS-1:0] inv_hit_way;
    logic[CONFIG.DCACHE.WAYS-1:0] inv_hit_way_r;

    logic [SCONFIG.LINE_ADDR_W-1:0] update_port_addr;
    ////////////////////////////////////////////////////
    //Implementation


    ////////////////////////////////////////////////////
    //Muxing of cache miss or invalidation control logic and tags
    assign miss_or_extern_invalidate = update | (extern_inv | inv_all_ways);
    assign update_port_addr = ((extern_inv | inv_all_ways) & ~update) ? getLineAddr(inv_addr) : getLineAddr(stage2_addr);

    assign new_tagline.valid = update;//If not update then an invalidation is being performed
    assign new_tagline.tag = getTag(stage2_addr);

    always_ff @ (posedge clk) begin
        if (rst)
            inv_tags_accessed <= inv_all_ways;
        else
            inv_tags_accessed <= (extern_inv | inv_all_ways) & ~update;
    end

    assign extern_inv_complete = ((extern_inv | inv_all_ways) & ~update) & inv_tags_accessed;

    ////////////////////////////////////////////////////
    //Memory instantiation and hit detection
    generate
        genvar i;
        dtag_entry_t stage2_hit_comparison_tagline;
        dtag_entry_t inv_hit_comparison_tagline;

        assign stage2_hit_comparison_tagline.valid = 1;
        assign stage2_hit_comparison_tagline.tag = getTag(stage2_addr);
        assign inv_hit_comparison_tagline.valid = 1;
        assign inv_hit_comparison_tagline.tag = getTag(inv_addr);

        for (i=0; i < CONFIG.DCACHE.WAYS; i=i+1) begin : dtag_bank_gen
            assign update_tag_way[i] = update_way[i] | ((inv_all_ways | inv_hit_way[i]) & extern_inv_complete);

            tag_bank #($bits(dtag_entry_t), CONFIG.DCACHE.LINES) dtag_bank ( 
                .clk            (clk),
                .rst            (rst),
                .en_a           (stage1_adv), 
                .wen_a          (stage1_inv),
                .addr_a         (getLineAddr(stage1_addr)),
                .data_in_a      ('0), 
                .data_out_a     (tag_line[i]),
                .en_b           (miss_or_extern_invalidate), 
                .wen_b          (update_tag_way[i]),
                .addr_b         (update_port_addr),
                .data_in_b      (new_tagline), .data_out_b(inv_tag_line[i])
            );

            assign inv_hit_way[i] = (inv_hit_comparison_tagline == inv_tag_line[i]);
            assign tag_hit_way[i] = (stage2_hit_comparison_tagline == tag_line[i]);

        end
    endgenerate

    assign tag_hit = |tag_hit_way;
    ////////////////////////////////////////////////////
    //Assertions

endmodule
