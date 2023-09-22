package FuzzerCF_Hasher;
	import FIFO::*;
	import FIFOF::*;
	import SpecialFIFOs::*;
	import BRAM::*;
	import BRAMCore::*;
	import Vector::*;
	import DReg::*;
	import FuzzerTypes::*;
	import FuzzerCF_CfDetectors::*;
	import Logging::*;

	interface FuzzerCfIfc;
		//Returns True if the pipeline is processing at least one element.
		//-> Does not include elements to be added (i.e. combinatorial coreState_ifc2.put calls),
		//   and does not exclude elements to be taken (i.e. combinatorial fuzzBitmapReq_ifc.get calls).
		method Bool not_empty;
		method Bool getStallSignal();
		interface Put#(T_RiscCoreState2) 	coreState_ifc2;			// Interface write core state
		(* always_ready, always_enabled *)
		interface Put#(T_FuzzerToCfState) 	fuzzState_ifc;
		interface Get#(T_Fuzzer_BitmapUpdateReq) fuzzBitmapReq_ifc;	// Interface return CF event hash
		interface Put#(Maybe#(UInt#(32))) ignoreRange_ifc;
	endinterface
	
	module mkFuzzerCF_Hasher(FuzzerCfIfc);
		// -------------------------------------------- INTERFACE FIFOS -----------------------------------------------------------------------------
		FIFOF#(T_RiscCoreState2) 	fuzzcoreToFuzzCf_CoreState2 <- mkFIFOF();		// Create interface fifo
		FIFO#(T_FuzzerToCfState)	fuzzcoreToFuzzCf_State	<- mkFIFO();
		
		FIFOF#(T_Fuzzer_BitmapUpdateReq) fuzzBitmapReq 			<- mkFIFOF();
		
		FIFOF#(Bit#(32)) 	toHash 				<- mkSizedFIFOF(5);
		FIFOF#(Bit#(32)) 	intermResult1		<- mkSizedFIFOF(1);
		FIFOF#(Bit#(32)) 	intermResult2		<- mkSizedFIFOF(1);
		FIFOF#(Bit#(32)) 	intermResult3		<- mkSizedFIFOF(1);
		FIFOF#(Bit#(32)) 	intermResult4		<- mkSizedFIFOF(1);
		FIFOF#(Bit#(32)) 	intermResult5		<- mkSizedFIFOF(1);
		FIFOF#(Bit#(32)) 	intermResult6		<- mkSizedFIFOF(1);

		// -----------------------------------CORE STATE VARIABLES ---------------------------------------------------------------------------------
		Wire#(Bool) 	started 	<- mkDWire(False);
		Reg#(Bool)      prev_started <-mkReg(False);
		
		Reg#(Bool)      include_prev_state <- mkReg(False); // Set if the hash should be continuously updated - to generate a hash over all branches.
		
		Reg#(Bool)      has_exclude_range <- mkReg(False);
		Reg#(UInt#(32)) exclude_range_min <- mkRegU();
		
		Reg#(Bool)      r_not_empty <- mkReg(False);
		(* no_implicit_conditions *)
		rule update_not_empty;
			Bool _not_empty = False;
			if (fuzzcoreToFuzzCf_CoreState2.notEmpty) _not_empty = True;
			if (toHash.notEmpty) _not_empty = True;
			if (intermResult1.notEmpty) _not_empty = True;
			if (intermResult2.notEmpty) _not_empty = True;
			if (intermResult3.notEmpty) _not_empty = True;
			if (intermResult4.notEmpty) _not_empty = True;
			if (intermResult5.notEmpty) _not_empty = True;
			if (fuzzBitmapReq.notEmpty) _not_empty = True;
			r_not_empty <= _not_empty;
		endrule
		
		rule computeHash1;
			let x = toHash.first;
			toHash.deq();
			x = x ^ (x >> 16);
			intermResult1.enq(x);
			$display("computeHash1");
		endrule

		rule computeHash2;
			let x = intermResult1.first;
			intermResult1.deq;
			x = x * 'h7feb352d;
			intermResult2.enq(x);
			$display("computeHash2");
		endrule

		rule computeHash3;
			let x = intermResult2.first;
			intermResult2.deq;
			x = x ^ (x >> 15);
			intermResult3.enq(x);
			$display("computeHash3");
		endrule

		rule computeHash4;
			let x = intermResult3.first;
			intermResult3.deq;
			x = x * 'h846ca68b;
			intermResult4.enq(x);
			$display("computeHash4");
		endrule

		rule computeHash5;
			let x = intermResult4.first;
			intermResult4.deq;
			x = x ^ (x >> 16);
			intermResult5.enq(x);
			$display("computeHash5");
		endrule

		rule computeHash6;
			let x = intermResult5.first;
			intermResult5.deq;
			
			fuzzBitmapReq.enq(T_Fuzzer_BitmapUpdateReq{hash:x});
			
			$display("hash %b", x);
			$display("computeHash6");
		endrule

		// ----------------------------- STATE INFO FROM Fuzzer CORE ----------------------------------
		rule stateInfoFromFuzzerCore;
			let stateFromFuzzCore = fuzzcoreToFuzzCf_State.first;
			started		<= stateFromFuzzCore.started;
			fuzzcoreToFuzzCf_State.deq;
		endrule
		
		rule updatePrevStarted;
			prev_started <= started;
		endrule

		// ------------ Reset ----------------
		Reg#(Bool) wantToReset <- mkReg(False);

		rule wantReset(!started && prev_started);
			wantToReset <= True;
			$display("want to reset fuzzer");
		endrule

		rule resetRegs(wantToReset && !toHash.notEmpty && !intermResult1.notEmpty && !intermResult2.notEmpty && !intermResult3.notEmpty && !intermResult4.notEmpty && !intermResult5.notEmpty && !intermResult6.notEmpty);
			wantToReset <= False;
			$display("Resetting fuzzer :)");
		endrule

		// ------------------------------- INITIAL RULE ---------------------------------
		// Checks if started is set and initializes the specific CF update flow
		function Action startFlows(Bit#(32) curr_instr, Bit#(32) curr_pc, Bit#(32) next_pc);
			action
				feature_log($format("startFlows") ,L_CF_Flows);
				if(!wantToReset && (isLoopStartBranch(curr_instr) || isConditionalBranch(curr_instr) || isJ(curr_instr) || isJAL(curr_instr) || isJALR(curr_instr))) begin
					feature_log($format("curr_pc is %h curr_instr is %h next_pc is %h", curr_pc, curr_instr, next_pc),L_CF_Flows);
					toHash.enq(next_pc + curr_pc);
				end
			endaction
		endfunction

		// ---------------------------------------- STATE INFORMATION IMPORT -------------------------------------------------------------------
		//(* mutually_exclusive = "stateInfoFromCore2, init, writeCfConfiguration" *)
		(*descending_urgency = "resetRegs, stateInfoFromCore2"*)
		rule stateInfoFromCore2;
			feature_log($format("core -> nested"), L_CF_Flows);
			let stateFromCore2 = fuzzcoreToFuzzCf_CoreState2.first;
			if (!has_exclude_range || (unpack(stateFromCore2.curr_pc) < exclude_range_min && unpack(stateFromCore2.next_pc) < exclude_range_min)) begin
				startFlows(stateFromCore2.curr_instr, unpack(truncate(stateFromCore2.curr_pc)), unpack(truncate(stateFromCore2.next_pc)) );
			end
			fuzzcoreToFuzzCf_CoreState2.deq;
		endrule
		
		method Bool not_empty = r_not_empty || fuzzcoreToFuzzCf_CoreState2.notEmpty;
		
		method Bool getStallSignal();
			return False;
		endmethod

		interface Put coreState_ifc2;
			method Action put(T_RiscCoreState2 state); // Connect fifof to interface
				fuzzcoreToFuzzCf_CoreState2.enq(state);
			endmethod
		endinterface
		interface fuzzState_ifc			= fifoToPut(fuzzcoreToFuzzCf_State);	// Connect fifo to interface
		interface Get fuzzBitmapReq_ifc;
			method ActionValue#(T_Fuzzer_BitmapUpdateReq) get(); // Connect fifof to interface
				let req = fuzzBitmapReq.first;
				fuzzBitmapReq.deq();
				return req;
			endmethod
		endinterface
		interface Put ignoreRange_ifc;
			method Action put(Maybe#(UInt#(32)) range);
				case (range) matches
					tagged Valid { .range_begin} : begin
						has_exclude_range <= True;
						exclude_range_min <= range_begin;
					end
					tagged Invalid : begin
						has_exclude_range <= False;
						exclude_range_min <= ?;
					end
				endcase
			endmethod
		endinterface
	endmodule
endpackage
