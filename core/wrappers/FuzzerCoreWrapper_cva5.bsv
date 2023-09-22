package FuzzerCoreWrapper_cva5;
	
	import AXI4_Lite_Slave::*;
	import AXI4_Lite_Types::*;
	import GenericAxi4LiteSlave::*;
	import AXI4_Slave::*;
	import AXI4_Types::*;
	import AXI4_Master::*;
	import AXI4_Stream::*;
	
	import FuzzerCore::*;
	
	import GetPut::*;
	import ClientServer::*;
	import Connectable::*;
	
	interface InvalidationHandler;
		//Interface:
		// request.put - Provides an invalidation request. Value ignored.
		//               Only ready if
		//               -> core reset is active, and
		//               -> 'dirty' flag is set (i.e. not invalidated already since start of reset).
		//               Also ready if an invalidation is still running
		// response.get - Ready for one cycle the invalidation is done. Result value is undefined.
		//               Client should hold the core reset high until the invalidate response arrives.
		//Note: No FIFO semantics; requests do not stack,
		//      only one response is returned even after several requests
		//      and the client must be ready to call response.get in every clock cycle after a request.
		interface Server#(Bool,Bool) invalidate;
		
		//Interface to core.
		// Indicates an invalidation request to the core.
		(* always_ready *)
		method Bool intf_invalidate_req();
		//Interface to core.
		// Acknowledges an invalidation request,
		// and is kept high until the invalidation is done.
		(* always_ready, always_enabled *)
		method Action intf_invalidate_pending(Bool r);
		
		//Must be called each cycle with the core reset signal.
		(* always_ready, always_enabled *)
		method Action set_core_rst(Bool rst);
	endinterface
	
	//Module that interfaces between FuzzerCore's invalidate Clients and CVA5 invalidation signals.
	module mkInvalidationHandler(InvalidationHandler);
		Wire#(Bool) core_rst <- mkBypassWire;
		
		Reg#(Bool) cacheDirty[2] <- mkCReg(2, False);
		rule cacheDirty_set(!core_rst);
			cacheDirty[1] <= True;
		endrule
		
		Reg#(Bool) invalidate_set_req[2] <- mkCReg(2, False);
		
		Reg#(Bool) invalidate_done[2] <- mkCReg(2, False);
		
		Wire#(Bool) cur_put_request_ready <- mkBypassWire;
		rule r_put_request_ready;
			cur_put_request_ready <= (core_rst && cacheDirty[0]);
		endrule
		
		rule r_invalidate_putresp(invalidate_done[0]);
			invalidate_done[0] <= False;
			cacheDirty[0] <= False;
		endrule
		
		Reg#(Bool) invalidate_pending_last <- mkReg(False);
		
		method Bool intf_invalidate_req() = invalidate_set_req[0];
		method Action intf_invalidate_pending(Bool r);
			if (invalidate_set_req[0] && r) begin
				invalidate_set_req[0] <= False;
			end
			if (invalidate_pending_last && !r) begin
				invalidate_done[1] <= True;
			end
			invalidate_pending_last <= r;
		endmethod
		
		method Action set_core_rst(Bool rst);
			core_rst <= rst;
		endmethod
		
		interface Server invalidate;
			interface Put request;
				method Action put(Bool _) if (cur_put_request_ready);
					invalidate_set_req[1] <= True;
				endmethod
			endinterface
			interface Get response;
				method ActionValue#(Bool) get() if (invalidate_done[0]);
					return True;
				endmethod
			endinterface
		endinterface
	endmodule
	
	interface FuzzerIntf_cva5;
		//Passing through the FuzzerIntf of mkFuzzerCore here would not work
		//since some of its always_enabled Action methods are used by the wrapper.
		
		interface GenericAxi4LiteSlave#(16, 32) s_axi_ctrl;			// interface for start and stop of cumputations
		interface AXI4_Slave#(32, 32, 6, 0) 	s_axi_bram; 		// interface for transition table
		interface AXI4_Master#(32, 32, 6, 0)	m_axi_cpu_mem;
		

		(* always_enabled *)
		method Action traceSpecInput(Bool trace_rv_i_valid_ip, Bit#(32) trace_rv_i_address_ip, Bit#(32) trace_rv_i_insn);

		(* always_enabled *)
		method Action exceptionInput(Bool valid, Bit#(5) cause, Bit#(32) tval, Bit#(32) epc);
		
		(* always_ready *)
		method Bool dexie_stall();
		
		(* always_ready *)
		method Bit#(12) setup_sectionid_val();
		(* always_ready *)
		method Bool setup_sectionid_en();
		
		(* always_ready *)
		(* result = "icacheInvalidate_req" *) method Bool picacheInvalidate_req();
		(* always_ready *)
		(* result = "bpInvalidate_req" *) method Bool pbpInvalidate_req();
		(* always_ready *)
		(* result = "dcacheInvalidate_req" *) method Bool pdcacheInvalidate_req();
		(* always_ready, always_enabled *)
		(* prefix = "" *) method Action picacheInvalidate_pending((*port="icacheInvalidate_pending"*)Bool r);
		(* always_ready, always_enabled *)
		(* prefix = "" *) method Action pbpInvalidate_pending((*port="bpInvalidate_pending"*)Bool r);
		(* always_ready, always_enabled *)
		(* prefix = "" *) method Action pdcacheInvalidate_pending((*port="dcacheInvalidate_pending"*)Bool r);
		
		(* always_ready *)
		method Bool rst();
		(* always_ready *)
		method Bool irq();
	endinterface
	
	typedef struct{
		Bit#(32) curPc;
		Bit#(32) curInstr;
	}T_DexTrPkg deriving (Bits, Eq, FShow);

	(* synthesize *)
	module mkFuzzerCoreWrapper_cva5(FuzzerIntf_cva5);
		FuzzerIntf fuzzerCore <- mkFuzzerCore;
		
		Reg#(Bit#(32)) lastPc    <-mkReg(0);
		Reg#(Bit#(32)) lastInstr <-mkReg(0);
		Reg#(Bool)     first <-mkReg(True);
		
		Reg#(Bool)     fuzzer_core_rst_r <- mkReg(True);
		Wire#(Tuple3#(Bool,Bit#(32),Bit#(32))) cur_trace_valid_ip_insn <- mkBypassWire;
		rule r_update_fuzzer_core_rst_r;
			fuzzer_core_rst_r <= fuzzerCore.rst();
		endrule
		rule r_reset_first(fuzzer_core_rst_r);
			first <= True;
		endrule
		rule r_handle_trace(!fuzzer_core_rst_r);
			Bool trace_rv_i_valid_ip = tpl_1(cur_trace_valid_ip_insn);
			Bit#(32) trace_rv_i_address_ip = tpl_2(cur_trace_valid_ip_insn);
			Bit#(32) trace_rv_i_insn = tpl_3(cur_trace_valid_ip_insn);
			if(trace_rv_i_valid_ip)begin
				$display("val %b, addr %h, insn %h", trace_rv_i_valid_ip, trace_rv_i_address_ip, trace_rv_i_insn);
				lastPc	  <= trace_rv_i_address_ip;
				lastInstr <= trace_rv_i_insn;
				first <= False;
			end
			if(!first) begin
				fuzzerCore.cfdata(trace_rv_i_valid_ip, lastInstr, lastPc, trace_rv_i_address_ip);
			end
		endrule
		
		InvalidationHandler icacheInvalidateHandler <- mkInvalidationHandler;
		mkConnection(fuzzerCore.icache_invalidate, icacheInvalidateHandler.invalidate);
		
		InvalidationHandler bpInvalidateHandler <- mkInvalidationHandler;
		mkConnection(fuzzerCore.bp_invalidate, bpInvalidateHandler.invalidate);
		
		InvalidationHandler dcacheInvalidateHandler <- mkInvalidationHandler;
		mkConnection(fuzzerCore.dcache_invalidate, dcacheInvalidateHandler.invalidate);
		
		rule distribute_resets;
			icacheInvalidateHandler.set_core_rst(fuzzerCore.rst());
			bpInvalidateHandler.set_core_rst(fuzzerCore.rst());
			dcacheInvalidateHandler.set_core_rst(fuzzerCore.rst());
		endrule
		
		
		method Action traceSpecInput(Bool trace_rv_i_valid_ip, Bit#(32) trace_rv_i_address_ip, Bit#(32) trace_rv_i_insn);
			cur_trace_valid_ip_insn <= tuple3(trace_rv_i_valid_ip, trace_rv_i_address_ip, trace_rv_i_insn);
		endmethod

		method Action exceptionInput(Bool valid, Bit#(5) cause, Bit#(32) tval, Bit#(32) epc);
			fuzzerCore.excdata(valid, cause, tval, epc);
		endmethod
		
		method Bool rst();
			return fuzzerCore.rst();
		endmethod
		method Bool irq();
			return fuzzerCore.irq();
		endmethod
		method Bool dexie_stall();
			return fuzzerCore.stall();
		endmethod
		
		interface setup_sectionid_val = fuzzerCore.setup_sectionid_val;
		interface setup_sectionid_en = fuzzerCore.setup_sectionid_en;
		
		interface picacheInvalidate_req = icacheInvalidateHandler.intf_invalidate_req;
		interface picacheInvalidate_pending = icacheInvalidateHandler.intf_invalidate_pending;
		
		interface pbpInvalidate_req = bpInvalidateHandler.intf_invalidate_req;
		interface pbpInvalidate_pending = bpInvalidateHandler.intf_invalidate_pending;
		
		interface pdcacheInvalidate_req = dcacheInvalidateHandler.intf_invalidate_req;
		interface pdcacheInvalidate_pending = dcacheInvalidateHandler.intf_invalidate_pending;
		
		interface GenericAxi4LiteSlave s_axi_ctrl = fuzzerCore.s_axi_ctrl;
		interface AXI4_Slave s_axi_bram = fuzzerCore.s_axi_bram;
		interface AXI4_Master m_axi_cpu_mem = fuzzerCore.m_axi_cpu_mem;
	endmodule
	
endpackage