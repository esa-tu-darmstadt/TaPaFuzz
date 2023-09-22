/*
 * Copyright © 2019 Eric Matthews,  Lesley Shannon
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

#include <iostream>
#include "TaigaTracer.h"

//#define TRACE_ON

bool TaigaTracer::check_if_instruction_retired(uint32_t instruction) {
    bool result = false;
    for (int i =0; i < tb->NUM_RETIRE_PORTS; i++) {
        result |= (tb->retire_ports_instruction[i] == instruction) && tb->retire_ports_valid[i];
    }
    return result;
}


bool TaigaTracer::has_terminated() {

    if (check_if_instruction_retired(ERROR_TERMINATION_NOP)) {
        std::cout << "\n\nError!!!!\n\n";
        return true;
    }
    //Custom nop for regular termination
    program_complete |= check_if_instruction_retired(SUCCESS_TERMINATION_NOP);

    if (program_complete && tb->store_queue_empty)
        return true;

    return false;
}


bool TaigaTracer::has_stalled() {
    if (!tb->instruction_issued) {
        if (stall_count > stall_limit) {
            stall_count = 0;
            std::cout << "\n\nError!!!!\n";
            std::cout << "Stall of " << stall_limit << " cycles detected!\n\n";
            return true;
		} else {
			stall_count++;
		}
	}
    else 
        stall_count=0;
	return false;
}

bool TaigaTracer::store_queue_empty() {
    return tb->store_queue_empty;
}

void TaigaTracer::reset_stats() {
    for (int i=0; i < numEvents; i++)
         event_counters[i] = 0;
}


void TaigaTracer::update_stats() {
    if (collect_stats) {
        for (int i=0; i < numEvents; i++)
            event_counters[i] += tb->taiga_events[i];
    }
}


void TaigaTracer::print_stats() {
	std::cout << "   Taiga trace stats\n";
	std::cout << "--------------------------------------------------------------\n";
    for (int i=0; i < numEvents; i++)
       std::cout << "    " << eventNames[i] << ":" << event_counters[i] << std::endl;

	std::cout << "--------------------------------------------------------------\n\n";
}



void TaigaTracer::reset() {
    tb->clk = 0;
    tb->rst = 1;
    for (int i=0; i <reset_length; i++){
        tick();
    }

    tb->rst = 0;
    reset_stats();
    std::cout << "DONE System reset \n" << std::flush;


}

void TaigaTracer::set_log_file(std::ofstream* logFile) {
    this->logFile = logFile;
}


void TaigaTracer::update_UART() {
	if (tb->write_uart) {
		std::cout <<  tb->uart_byte << std::flush;
		*logFile << tb->uart_byte;
	}
}


void TaigaTracer::update_memory() {
    tb->instruction_bram_data_out = instruction_r;
    if (tb->instruction_bram_en)
        instruction_r = mem->read(tb->instruction_bram_addr);

    tb->data_bram_data_out = data_out_r;
    if (tb->data_bram_en) {
        data_out_r = mem->read(tb->data_bram_addr);
        mem->write(tb->data_bram_addr, tb->data_bram_data_in, tb->data_bram_be);
    }
}


void TaigaTracer::tick() {
        cycle_count++;

		tb->clk = 1;
		tb->eval();
        #ifdef TRACE_ON
            verilatorWaveformTracer->dump(vluint32_t(cycle_count));
        #endif
        cycle_count++;

        tb->clk = 0;
        tb->eval();
        #ifdef TRACE_ON
            verilatorWaveformTracer->dump(vluint32_t(cycle_count));
        #endif


        if (check_if_instruction_retired(BENCHMARK_START_COLLECTION_NOP)) {
            reset_stats();
            collect_stats = true;
        }
        else if (check_if_instruction_retired(BENCHMARK_RESUME_COLLECTION_NOP)) {
            collect_stats = true;
        }
        else if (check_if_instruction_retired(BENCHMARK_END_COLLECTION_NOP)) {
            collect_stats = false;
        }


        tb->clk = 1;
        tb->eval();
        axi_ddr->step();
        update_stats();
        update_UART();
        update_memory();
}


void TaigaTracer::start_tracer(const char *trace_file) {
	#ifdef TRACE_ON
		verilatorWaveformTracer = new VerilatedVcdC;
		tb->trace(verilatorWaveformTracer, 99);
		verilatorWaveformTracer->open(trace_file);
	#endif
}



uint64_t TaigaTracer::get_cycle_count() {
    return cycle_count;
}


TaigaTracer::TaigaTracer(std::ifstream& programFile) {
	#ifdef TRACE_ON
		Verilated::traceEverOn(true);
	#endif


    tb = new Vtaiga_sim;

   #ifdef DDR_LOAD_FILE
        axi_ddr = new axi_ddr_sim(DDR_INIT_FILE,DDR_FILE_STARTING_LOCATION,DDR_FILE_NUM_BYTES);
    #else
        axi_ddr = new axi_ddr_sim(programFile, tb);
        
    #endif
    programFile.clear();
    programFile.seekg(0, ios::beg);
    mem = new SimMem(programFile, 128);

    instruction_r = mem->read(tb->instruction_bram_addr);
    data_out_r = 0;
}


TaigaTracer::~TaigaTracer() {
	#ifdef TRACE_ON
		verilatorWaveformTracer->flush();
		verilatorWaveformTracer->close();
	#endif
	delete mem;
	delete tb;
}
