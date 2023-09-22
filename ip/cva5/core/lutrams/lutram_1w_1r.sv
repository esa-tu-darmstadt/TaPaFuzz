/*
 * Copyright © 2021 Eric Matthews,  Lesley Shannon
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

module lutram_1w_1r
    #(
        parameter WIDTH = 32,
        parameter DEPTH = 32
    )
    (
        input logic clk,

        input logic[$clog2(DEPTH)-1:0] waddr,
        input logic[$clog2(DEPTH)-1:0] raddr,

        input logic ram_write,
        input logic[WIDTH-1:0] new_ram_data,
        output logic[WIDTH-1:0] ram_data_out
    );

    (* ramstyle = "MLAB, no_rw_check", ram_style = "distributed" *) logic [WIDTH-1:0] ram [DEPTH-1:0];

    initial ram = '{default: 0};
	//Workaround: Use always instead of always_ff since the Questa simulator does not like the initial statement otherwise.
    always @ (posedge clk) begin
        if (ram_write)
            ram[waddr] <= new_ram_data;
    end

    assign ram_data_out = ram[raddr];

endmodule
