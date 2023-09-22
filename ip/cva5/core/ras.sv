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
 
module ras

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
        input logic early_branch_flush_ras_adjust,
        ras_interface.self ras
    );

    (* ramstyle = "MLAB, no_rw_check" *) logic[31:0] lut_ram [CONFIG.BP.RAS_ENTRIES];

    localparam RAS_DEPTH_W = $clog2(CONFIG.BP.RAS_ENTRIES);
    logic [RAS_DEPTH_W-1:0] read_index;
    logic [RAS_DEPTH_W-1:0] new_index;
    fifo_interface #(.DATA_WIDTH(RAS_DEPTH_W)) ri_fifo();
    ///////////////////////////////////////////////////////
    //For simulation purposes
    initial lut_ram = '{default: 0};
    initial read_index = '{default: 0};
     ///////////////////////////////////////////////////////
    assign ras.addr = lut_ram[read_index];
    
    //On a speculative branch, save the current stack pointer
    //Restored if branch is misspredicted (gc_fetch_flush)
    taiga_fifo #(.DATA_WIDTH(RAS_DEPTH_W), .FIFO_DEPTH(MAX_IDS))
        read_index_fifo (.clk, .rst(rst | gc.fetch_flush | early_branch_flush_ras_adjust), .fifo(ri_fifo));

    assign ri_fifo.data_in = read_index;
    assign ri_fifo.push = ras.branch_fetched;
    assign ri_fifo.potential_push = ras.branch_fetched;
    assign ri_fifo.pop = ras.branch_retired & ri_fifo.valid; //Prevent popping from fifo if reset due to early_branch_flush_ras_adjust

	//Workaround: Use always instead of always_ff since the Questa simulator does not like the initial statement otherwise.
    always @ (posedge clk) begin
        if (ras.push)
            lut_ram[new_index] <= ras.new_addr;
    end
    
    //Rolls over when full, most recent calls will be correct, but calls greater than depth
    //will be lost.
    logic [RAS_DEPTH_W-1:0] new_index_base;
    assign new_index_base = (gc.fetch_flush & ri_fifo.valid) ? ri_fifo.data_out : read_index;
    assign new_index = new_index_base + RAS_DEPTH_W'(ras.push) - RAS_DEPTH_W'(ras.pop);
	//Workaround: Use always instead of always_ff since the Questa simulator does not like the initial statement otherwise.
    always @ (posedge clk) begin
		if (rst) read_index <= 0; //(only relevant for simulation)
		else read_index <= new_index;
    end

endmodule