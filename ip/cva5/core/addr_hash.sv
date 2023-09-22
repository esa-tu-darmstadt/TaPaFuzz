/*
 * Copyright © 2020 Eric Matthews,  Lesley Shannon
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

module addr_hash 

    import taiga_config::*;
    import riscv_types::*;
    import taiga_types::*;

    (
        input logic clk,
        input logic rst,
        input logic [31:0] addr,
        output addr_hash_t addr_hash
    );

    ////////////////////////////////////////////////////
    //Implementation
    //Xor addr in groups of 4-bits, truncating to the virtual/physical address invariant bits (11:0)
    //lower two bits are not used due to complications in determining overlap between byte
    //halfword and word operations.
    assign addr_hash[0] = addr[2] ^ addr[6] ^ addr[10];
    assign addr_hash[1] = addr[3] ^ addr[7] ^ addr[11];
    assign addr_hash[2] = addr[4] ^ addr[8];
    assign addr_hash[3] = addr[5] ^ addr[9];
    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule
