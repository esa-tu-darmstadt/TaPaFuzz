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
 
//Custom module to ensure read requests overlapping with a pending write are delayed.
//Treats each write and read like a full burst over the naturally aligned address range (by maximum burst length).
module l2_write_read_ordering_logic

    import l2_config_and_types::*;
    import taiga_config::*;
    
    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG
    )

    (
        input logic clk,
        input logic rst,
        
        input logic [31:2] addr, //Address for the current write or read request.
        input logic is_write, //Set if a valid, not already pushed write request arrives.
        input logic is_read, //Set if a read request is in the stage, only used for debug $display.
        
        input logic bus_write_done, //Set if the bus confirmed completion of a previous write request.
        
        output logic write_pushed, //Helper: Set if a write is pushed to the FIFO (i.e. is_write and FIFO not full).
        output logic stall //If set, the stage should stall and not pass on the request yet.
    );
    
    localparam int unsigned BURST_LEN_W = get_max_burst_range_w(CONFIG);

    typedef struct packed{
        logic valid;
        logic [31:2+BURST_LEN_W] addr;
    } write_entry;
    
    //'FIFO' entries.
    write_entry write_tracker_buf [CONFIG.L2_WRITE_TRACK_DEPTH-1:0];
    //Front index
    logic [$clog2(CONFIG.L2_WRITE_TRACK_DEPTH)-1:0] write_tracker_pop_idx;
    //Past-back index
    logic [$clog2(CONFIG.L2_WRITE_TRACK_DEPTH)-1:0] write_tracker_push_idx;
    
    logic write_tracker_push;
    logic write_tracker_pop;
    
    //Overall FIFO count if not empty: write_tracker_pop_idx - write_tracker_push_idx
    //-> empty if: !write_tracker_buf[write_tracker_pop_idx].valid
    
    initial write_tracker_buf = '{default: 0};
    initial write_tracker_pop_idx = '{default: 0};
    initial write_tracker_push_idx = '{default: 0};
    
    logic write_tracker_full;
    assign write_tracker_full = (write_tracker_pop_idx == write_tracker_push_idx) & write_tracker_buf[write_tracker_pop_idx].valid;
    
    logic [CONFIG.L2_WRITE_TRACK_DEPTH-1:0] is_addr_match;

    always_comb begin
        for (int i = 0; i < CONFIG.L2_WRITE_TRACK_DEPTH; i++) begin
            //Compare the entry address with the current request address.
            is_addr_match[i] = write_tracker_buf[i].valid & (addr[31:2+BURST_LEN_W] == write_tracker_buf[i].addr);
        end
    end
    
    //Stall if:
    //- New write appears and FIFO is full (wait for previous write confirmation).
    //- Read request address overlaps with pending write.
    assign stall = is_write ? (write_tracker_full) : (|is_addr_match);
    //Set if the current write will be added to the FIFO.
    assign write_pushed = write_tracker_push;
    
    //Debug
    always @(posedge clk) begin
        for (int i = 0; i < CONFIG.L2_WRITE_TRACK_DEPTH; i++) begin
            if (is_read & is_addr_match[i])
                $display("Stalling l2 due to pending write addr=%x (req addr = %x)", {write_tracker_buf[i].addr, {BURST_LEN_W{1'b0}}, 2'b00}, {addr, 2'b00});
        end
        if (is_write & write_tracker_full) $display("Stalling l2: is_write & write_tracker_full");
    end
    
    assign write_tracker_push = ~write_tracker_full & is_write;
    assign write_tracker_pop = bus_write_done;
    
    //FIFO logic (push, pop, reset).
    always @(posedge clk) begin
        if (rst) begin
            //Invalidate entries, reset indices to 0.
            for (int unsigned i = 0; i < CONFIG.L2_WRITE_TRACK_DEPTH; i++) begin
                write_tracker_buf[i].valid <= 0;
            end
            write_tracker_pop_idx <= '0;
            write_tracker_push_idx <= '0;
        end
        else begin
            if (write_tracker_pop) begin
                assert(write_tracker_buf[write_tracker_pop_idx].valid) else $error("Write tracker underflow");
                //Invalidate entry.
                write_tracker_buf[write_tracker_pop_idx].valid <= 0;
                //Increment index with wrap around to 0.
                write_tracker_pop_idx <= (write_tracker_pop_idx == CONFIG.L2_WRITE_TRACK_DEPTH-1) ? '0 : (write_tracker_pop_idx + 1);
            end
            if (write_tracker_push) begin
                assert(~write_tracker_buf[write_tracker_push_idx].valid) else $error("Write tracker overflow");
                //Assign entry.
                write_tracker_buf[write_tracker_push_idx].valid <= 1;
                write_tracker_buf[write_tracker_push_idx].addr <= addr[31:2+BURST_LEN_W];
                //Increment index with wrap around to 0.
                write_tracker_push_idx <= (write_tracker_push_idx == CONFIG.L2_WRITE_TRACK_DEPTH-1) ? '0 : (write_tracker_push_idx + 1);
            end
        end
    end
    
endmodule


