package FuzzerCore;
	import Logging::*;
	
	import AXI4_Lite_Slave::*;
	import AXI4_Lite_Types::*;
	import GenericAxi4LiteSlave::*;
	import AXI4_Slave::*;
	import AXI4_Types::*;
	import AXI4_Master::*;
	import AXI4_Stream::*;
	
	import Connectable::*;
	import FIFOF::*;
	import FIFO::*;
	import SpecialFIFOs::*;
	import DReg::*;
	import Vector::*;

	import BRAM::*;
	import BRAMCore::*;
	
	import RegFile::*;
	import GetPut::*;
	import ClientServer::*;
	import FuzzerTypes::*;
	import FuzzerCF_Hasher::*;
	import FuzzerCF_BitmapCore::*;
	
	
	interface FuzzerIntf;
		interface GenericAxi4LiteSlave#(16, 32) s_axi_ctrl;			// interface for start and stop of cumputations
		interface AXI4_Slave#(32, 32, 6, 0) 	s_axi_bram; 		// interface for transition table
		interface AXI4_Master#(32, 32, 6, 0)	m_axi_cpu_mem;
		
		(* always_ready *)
		method Bit#(12) setup_sectionid_val();                      // Section ID that defines the physical location of the program memory (12 msbs of the 32bit address, 1M per section).
		(* always_ready *)
		method Bool setup_sectionid_en();                           // Enable for the axi_offset_reset setup method.

		(* always_enabled *)
		method Action cfdata(Bool cf_valid, Bit#(32) cf_curInst, Bit#(32) cf_curPC, Bit#(32) cf_nextPC);

		(* always_enabled *)
		method Action excdata(Bool valid, Bit#(5) cause, Bit#(32) tval, Bit#(32) epc);
		
		(* always_ready *)
		method Bool rst();											// return rst, rstn and irq
		(* always_ready *)
		method Bool rstn();
		(* always_ready *)
		method Bool irq();
		(* always_ready *)											// Allow fuzzer to stall the core. Must not combinationally depend on cfdata signals.
		method Bool stall();
		
		interface Client#(Bool,Bool) icache_invalidate;             // Allow Fuzzer PE to invalidate the core's icache during a core reset.
		interface Client#(Bool,Bool) bp_invalidate;                 // Allow Fuzzer PE to invalidate the core's branch predictor during a core reset.
		interface Client#(Bool,Bool) dcache_invalidate;             // Allow Fuzzer PE to invalidate the core's dcache during a core reset.
	endinterface
	
	module mkFuzzerCore(FuzzerIntf);
		// AXI MEM
		AXI4_Slave_Wr#(32, 32, 6, 0) wrs <- mkAXI4_Slave_Wr(32, 32, 32);
		AXI4_Slave_Rd#(32, 32, 6, 0) rds <- mkAXI4_Slave_Rd(32, 32);

		// AXI to CPU
		AXI4_Master_Wr#(32, 32, 6, 0) wrm <- mkAXI4_Master_Wr(4, 32, 32, False);
		AXI4_Master_Rd#(32, 32, 6, 0) rdm <- mkAXI4_Master_Rd(32, 32, False);
		// Buffers for wrm.response, rdm.response. Used for id comparisons in rule guards.
		FIFO#(AXI4_Write_Rs#(6, 0)) wrm_response_buf <- mkBypassFIFO;
		FIFO#(AXI4_Read_Rs#(32, 6, 0)) rdm_response_buf <- mkBypassFIFO;

		Reg#(Bool) started 			<- mkReg(False);
		Reg#(Bool) start_req		<- mkReg(False);
		Reg#(Bit#(3)) cacheFlushReq[2] <- mkCReg(2, {1'b0, 1'b0, 1'b0});
		Reg#(Bit#(3)) cacheFlushReqPending[2] <- mkCReg(2, {1'b0, 1'b0, 1'b0});
		Reg#(Bool) irq_ack 			<- mkReg(False);
		
		//Execution complete interrupt, set by the application processor.
		Reg#(Bool) setIntr_prog 	<- mkReg(False);
		//Request to set the interrupt after all fuzzer data is flushed.
		Reg#(Bool) setIntr_internal	<- mkReg(False);

		// CSRs
		Reg#(Bit#(32)) 	retLo 		<- mkReg(0); // exit
		Reg#(Bit#(32)) 	retHi 		<- mkReg(0); // hash
		Reg#(Bit#(32))  timeoutLo   <- mkReg(0);
		Reg#(Bit#(32))  timeoutHi   <- mkReg(0);
		Reg#(Bit#(32))  counterLo   <- mkReg(0);
		Reg#(Bit#(32))  counterHi   <- mkReg(0);
		Reg#(Bit#(32))	arg0	 	<- mkReg(0);
		Reg#(Bit#(32))	arg1	 	<- mkReg(0);
		Reg#(Bit#(32)) 	arg2 		<- mkReg(0);
		Reg#(Bit#(32)) 	arg3 		<- mkReg(0);
		Reg#(Bit#(32)) 	arg4Lo 		<- mkReg(0);
		Reg#(Bit#(32)) 	arg4Hi 		<- mkReg(0);
		Reg#(Bit#(32)) 	hashResult	<- mkReg(0);
		
		Reg#(Bit#(12))  progmemSection <- mkReg(0);
		Reg#(Bit#(32))  ignore_min <- mkReg(32'hFFFFFFFF);
		Reg#(Bool)      skip_stalls <- mkReg(False);

		// Output wires for reset and interrupt
		Reg#(Bool) 	intr 	<- mkReg(False);
		Reg#(Bool) 	reset 	<- mkReg(True);
		Reg#(Bool) 	resetn 	<- mkReg(False);
		
		Wire#(Bool) resetBypass <- mkDWire(False);
		Wire#(Bool) resetGet <- mkDWire(True);
		Wire#(Bool) resetnGet <- mkDWire(False);
		
		// AXI CTRL
		List#(RegisterOperator#(16, 32)) operators = Nil;
		operators = registerHandler('h00, start_req, operators);
		operators = registerHandler('h0c, irq_ack, operators);
		// retLo: [0] exc occured, [5:1] exc cause (if occured), [6] bitmap size invalid, [7] timeout occured
		operators = registerHandler('h10, retLo, operators);
		operators = registerHandler('h14, retHi, operators);      // Hash Result
		operators = registerHandler('h20, arg0, operators);       // arg0: Job ID
		operators = registerHandler('h30, arg1, operators);       // arg1: Program input size
		operators = registerHandler('h40, arg2, operators);	      // arg2: Program input data
		operators = registerHandler('h50, arg3, operators);       // arg3: Bitmap size
		operators = registerHandlerRO('h60, arg4Lo, operators);   // arg4 (ret): if retLo[0]: [31:0] exc epc, 
		operators = registerHandlerRO('h64, arg4Hi, operators);   //             if retLo[0]: [63:32] exc tval
		operators = registerHandler('h70, timeoutLo, operators);// arg5: Timeout in cycles. 0: no timeout.
		operators = registerHandler('h74, timeoutHi, operators);
		operators = registerHandler('h80, setIntr_prog, operators); // (arg6): Set an interrupt for successful program execution.
		operators = registerHandlerRO('h90, counterLo, operators); // arg7: Execution timer, set to 0 after starting the core.
		operators = registerHandlerRO('h94, counterHi, operators);
		operators = registerHandler('hA0, progmemSection, operators); // arg8: Program memory section ID (upper 12 address bits).
		operators = registerHandler('hB0, cacheFlushReq[1], operators); // arg9: [0]: Flush instruction cache. [1]: Flush data cache.
		                                                              // If set, will be applied in the next core reset cycle (i.e. once the PE is idle).
																	  // PE start request will be delayed if flush is still in progress.
		operators = registerHandler('hC0, ignore_min, operators); //arg10: Address above which everything will be ignored.
		operators = registerHandler('hD0, skip_stalls, operators); //arg11: Flag for evaluation; If set, no core stalls are issued.
		GenericAxi4LiteSlave#(16, 32) a4sl <- mkGenericAxi4LiteSlave(operators, 4, 4);
		

		/* AXI4 Handling */
		Reg#(Bool) wrs_active <- mkReg(False);
		Reg#(Bit#(6)) wrs_id <- mkRegU;
		Reg#(Bool) rds_active <- mkReg(False);
		Reg#(Bit#(6)) rds_id <- mkRegU;
		FIFOF#(Bit#(6)) wrm_id_queue <- mkSizedBypassFIFOF(4);

		// cf wires
		Wire#(Bit#(32)) next_pc 			<- mkDWire(0);
		Wire#(Bool)		next_pc_Valid	 	<- mkDWire(False);
		Wire#(Bit#(32)) curr_instr 			<- mkDWire(0);
		Wire#(Bit#(32)) curr_instr_pc		<- mkDWire(0);
		Wire#(Bool)		curr_instr_Valid 	<- mkDWire(False);
		
		Wire#(Bool)     exc_valid       	<- mkDWire(False);
		Wire#(Bit#(5))  exc_cause       	<- mkDWire(0);
		Wire#(Bit#(32)) exc_tval        	<- mkDWire(0);
		Wire#(Bit#(32)) exc_epc         	<- mkDWire(0);
		
		
		Reg#(Bool) prev_started		<- mkReg(False);
		rule updatePrevStarted_set(started && !prev_started);
			prev_started <= True;
		endrule
		rule updatePrevStarted_reset(!started);
			prev_started <= False;
		endrule

		// ------------------------- Counter Handling --------------------------
		Reg#(Bool) timeout_pending <- mkReg(False);
		rule resetCounter(started && !prev_started);
			counterHi <= 0;
			counterLo <= 1;
			timeout_pending <= False;
		endrule
		rule increaseCounter(started && prev_started);
			Bit#(64) counterIn = {counterHi, counterLo};
			Bit#(64) counterOut = counterIn + 1;
			counterHi <= counterOut[63:32];
			counterLo <= counterOut[31:0];
		endrule
		rule detectTimeout(started && prev_started && !timeout_pending);
			Bit#(64) counter = {counterHi, counterLo};
			Bit#(64) timeoutVal = {timeoutHi, timeoutLo};
			if (timeoutVal == counter) begin
				//Timeout: Initiate interrupt.
				$display("Timeout detected.");
				timeout_pending <= True;
			end
		endrule
		rule intrOnTimeout(started && prev_started && timeout_pending && !setIntr_prog);
			$display("Setting timeout interrupt.");
			retLo <= 1 << 7;
			setIntr_prog <= True;
			timeout_pending <= False;
		endrule
		
		// ------------------- Interrupt and evilIRQ Handling ------------------
		function Action sendIRQ();
			action
				feature_log($format("Sending IRQ - Success"), L_IRQ);
				intr 		<= True;
				started 	<= False;
				//reset/resetn handled by setResets
			endaction
		endfunction
				
		rule r_setIntr(setIntr_internal);
			if (!intr) sendIRQ();
			setIntr_internal <= False;
			setIntr_prog <= False;
		endrule
		
		(* descending_urgency = "r_setIntr, r_resetIntr" *)
		rule r_resetIntr(irq_ack);
			intr <= False;
			irq_ack <= False;
		endrule

		/**
		* Forwards AXI4 write requests to the external BRAM for storage into processor local memory.
		* @param addr: The AXI4 write request package accepted by the slave.
		*/
		function Action forwardWriteRequest(AXI4_Write_Rq_Addr#(32, 6, 0) addr);
			return action
				wrm.request_addr.put(addr);
				wrm_id_queue.enq(addr.id);
			endaction;
		endfunction

		/**
		* Forwards AXI4 write data packages to the external BRAM storage.
		* @param data: The package to forward
		*/
		function Action forwardWriteData(AXI4_Write_Rq_Data#(32, 0) data);
			return action
				wrm.request_data.put(data);
				if (data.last)
					wrm_id_queue.deq();
			endaction;
		endfunction
		
		rule get_wrm_response;
			let resp <- wrm.response.get();
			wrm_response_buf.enq(resp);
		endrule
		
		rule get_rdm_response;
			let resp <- rdm.response.get();
			rdm_response_buf.enq(resp);
		endrule
		
		// -------------------------- Fuzzer CF --------------------------------------------------
		
		let cf <- mkFuzzerCF_Hasher;
		FuzzerBitmapCoreIfc#(32,32,6,0) bitmap_handler <- mkFuzzerCF_BitmapCore(B128);
		mkConnection(cf.fuzzBitmapReq_ifc, bitmap_handler.fuzzBitmapReq_ifc);
		
		// Perform interaction between bitmap_handler and the BRAM master interface.
		// For write data requests, the current 'writer unit' is determined
		//  by the ID from the oldest write address request (stored in wrm_id_queue).
		// The rules for get and put interfaces of bitmap_handler have guards checking the ID wherever needed.
		
		rule bitmap_set_ignore;
			cf.ignoreRange_ifc.put(tagged Valid unpack(ignore_min));
		endrule
		
		/**
		* Forwards a write address request by the bitmap handler.
		*/
		rule bitmap_redir_waddr;
			let req <- bitmap_handler.bitmap_waddr_ifc.get();
			forwardWriteRequest(req);
		endrule
		/**
		* Forwards a write data request by the bitmap handler,
		*  only if the latest write address request ID matches the bitmap handler's ID.
		*/
		(* descending_urgency = "bitmap_redir_waddr, bitmap_redir_wdata" *)
		rule bitmap_redir_wdata(wrm_id_queue.notEmpty && bitmap_handler.bitmap_wdata_ifc.for_id(wrm_id_queue.first));
			let req <- bitmap_handler.bitmap_wdata_ifc.get();
			forwardWriteData(req);
		endrule
		/**
		* Forwards the write result to the bitmap handler,
		*  only if the ID matches the bitmap handler's ID.
		*/
		rule bitmap_redir_wrs(bitmap_handler.bitmap_wrs_ifc.accepts_id(wrm_response_buf.first.id));
			bitmap_handler.bitmap_wrs_ifc.put(wrm_response_buf.first);
			wrm_response_buf.deq();
		endrule
		/**
		* Forwards a read request by the bitmap handler.
		*/
		rule bitmap_redir_raddr;
			let req <- bitmap_handler.bitmap_raddr_ifc.get();
			rdm.request.put(req);
		endrule
		/**
		* Forwards the read data to the bitmap handler,
		*  only if the response ID matches the bitmap handler's ID.
		*/
		rule bitmap_redir_rdata(bitmap_handler.bitmap_rdata_ifc.accepts_id(rdm_response_buf.first.id));
			bitmap_handler.bitmap_rdata_ifc.put(rdm_response_buf.first);
			rdm_response_buf.deq();
		endrule

		// Delays, then forwards per-cycle riscv-core information
		Reg#(Bit#(32)) pcToForward 		<- mkReg(0);
		Reg#(Bit#(32)) instrToForward 	<- mkReg(0);

		rule assertInstrAndNextPCValid(curr_instr_Valid != next_pc_Valid);
			if (curr_instr_Valid) begin
				feature_log($format("curr_instr_Valid %h is set but next_pc_Valid %h is not", curr_instr, next_pc), L_ERROR);
			end
			if (next_pc_Valid) begin
				feature_log($format("next_pc_Valid %h is set but curr_instr_Valid %h is not", next_pc, curr_instr), L_ERROR);
			end
		endrule
		
		rule forwardCoreState2ToFuzzerCF(curr_instr_Valid && next_pc_Valid && started && !setIntr_prog); // && !cf.getStallSignal()
			feature_log($format("Forwarding CF curr_pc %h curr_instr %h next_pc %h", curr_instr_pc, curr_instr, next_pc), L_CORE_CF);
			cf.coreState_ifc2.put(T_RiscCoreState2{curr_pc:curr_instr_pc, next_pc:next_pc, curr_instr:curr_instr});
		endrule
		
		(* descending_urgency = "forwardExceptionToFuzzerCF, intrOnTimeout" *)
		rule forwardExceptionToFuzzerCF(exc_valid && started && !setIntr_prog);
			feature_log($format("Got Exception cause %h tval %h epc %h", exc_cause, exc_tval, exc_epc), L_CORE_EXC);
			//-> Ignore 8,9,11: Environment call from U/S/M-mode (-> riscv-privileged 3.1.15 Machine Cause Register).
			//   Same for supervisor mode, where cause 11 is reserved (Environment call from M-mode not possible).
			if (exc_cause != 8 && exc_cause != 9 && exc_cause != 11) begin
				feature_log($format("Terminating program with failure status"), L_CORE_EXC);
				//retLo: [0] exc occured, [5:1] exc cause (if occured)
				retLo <= {26'd0, exc_cause, 1'd1};
				arg4Lo <= exc_epc;
				arg4Hi <= exc_tval;
				setIntr_prog <= True;
			end
		endrule

		rule forwardFuzzerToCfState;
			cf.fuzzState_ifc.put(T_FuzzerToCfState{started:started, reset:reset});
		endrule

		/**
		* Forwards writes to the instruction/data memory bus.
		*/
		(* descending_urgency = "handleAXIBramWr, bitmap_redir_waddr" *)
		rule handleAXIBramWr (!wrs_active);
			let req <- wrs.request_addr.get();
			forwardWriteRequest(AXI4_Write_Rq_Addr{
				id:  			pack(AXIID_ExtWrite),
				addr: 			req.addr,
				burst_length: 	req.burst_length,
				burst_size: 	req.burst_size,
				burst_type: 	req.burst_type,
				lock: 			req.lock,
				cache: 			req.cache,
				prot: 			req.prot,
				qos: 			req.qos,
				region: 		req.region,
				user: 			req.user
			});
			wrs_id <= req.id;
			wrs_active <= True;
			feature_log($format("Writing into Program Memory, Address %h", req.addr), L_CORE_MemWr);
		endrule

		/**
		* Distributes the data of the S_AXI_BRAM data channel
		*/
		(* mutually_exclusive = "handleAXI4BramData, bitmap_redir_wdata" *)
		rule handleAXI4BramData ( // Wait for other units currently writing through the master interface.
				wrm_id_queue.notEmpty && wrm_id_queue.first == pack(AXIID_ExtWrite)
				&& wrs_active); 
			let reqD <- wrs.request_data.get();
			let data = reqD.data;
			forwardWriteData(reqD);
		endrule
		
		/**
		* Returns the write response from the instruction/data memory bus.
		*/
		rule returnWriteResp(wrm_response_buf.first.id == pack(AXIID_ExtWrite)
				&& wrs_active);
			feature_log($format("Finished BRAM write transfer"), L_CORE_MemWr);
			let resp = wrm_response_buf.first;
			wrs.response.put(AXI4_Write_Rs{
				id: wrs_id,
				resp: resp.resp,
				user: resp.user
			});
			wrm_response_buf.deq();
			wrs_active <= False;
		endrule
		

		/**
		* Forwards reads to the instruction/data memory bus.
		*/
		rule handleAXIBramRdReq (!rds_active);
			let req <- rds.request.get();
			rdm.request.put(AXI4_Read_Rq{
				id:  			pack(AXIID_ExtRead),
				addr: 			req.addr,
				burst_length: 	req.burst_length,
				burst_size: 	req.burst_size,
				burst_type: 	req.burst_type,
				lock: 			req.lock,
				cache: 			req.cache,
				prot: 			req.prot,
				qos: 			req.qos,
				region: 		req.region,
				user: 			req.user
			});
			rds_active <= True;
			rds_id <= req.id;
		endrule
		
		/**
		* Returns the result from the instruction/data memory bus.
		*/
		rule handleAXIBramRdRes (rdm_response_buf.first.id == pack(AXIID_ExtRead)
				&& rds_active);
			let res = rdm_response_buf.first;
			rds.response.put(AXI4_Read_Rs{
				id:  			rds_id, 
				data: 			res.data,
				resp: 			res.resp,
				last: 			res.last,
				user: 			res.user
			});
			rdm_response_buf.deq();
			if (res.last) rds_active <= False;
		endrule

		// ------ Forward hash result ------
		//(Stream interface writing commented out for now)
		Reg#(Bool) hashTransferred <- mkDReg(False);
		
		rule initBitmapHandler(started && !prev_started);
			Bit#(32) retLo_new = 0;
			UInt#(32) bitmap_size = unpack(arg3);
			//Check the bitmap size: Must be a power of two in [4, 0x2000].
			if (!bitmap_handler.isValidSize(bitmap_size) || bitmap_size > 32'h00002000) begin
				retLo_new[6] = 1; //Bitmap size error.
				setIntr_internal <= True;
			end
			else begin
				//bitmap_handler.clear(32'h00020000, 32'h00002000);
				bitmap_handler.clear((`LOCALMEM_RANGE_EXTENDED == 1) ? 32'h01000000 : 32'h00020000, bitmap_size);  //always_ready
			end
			
			retLo <= retLo_new;
			hashTransferred <= False;
		endrule
		
		rule onBitmapReady(started && prev_started //Program has started, and bitmap handler has started.
				&& bitmap_handler.isFlushed() && !cf.not_empty //No CF event/hash left in the pipeline.
				&& setIntr_prog && !setIntr_internal); //Program is done, core interrupt not set yet.
			//Core finished, bitmap updates applied.
			feature_log($format("Setting IRQ."), L_Bitmap);
			setIntr_internal	<= True;
		endrule


		// ---------------------------- RESET HANDLING --------------------------------------------
		rule setResets;
			reset <= !started;
			resetn <= started;
		endrule

		//Resolves conflict between setResets, evilIRQ_Bypass and rst/rstn.
		rule setResetGet;
			resetGet <= reset;
			resetnGet <= resetn;
		endrule
		
		function Bool resetting();
			return resetGet || resetBypass;
		endfunction
		
		function Bool nresetting();
			return resetnGet && !resetBypass;
		endfunction
		
		rule startAfterFlush(start_req && cacheFlushReqPending[1] == '0);
			started <= True;
			start_req <= False;
		endrule
		
		function m#(Wire#(Bool)) mk_cacheFlushReq_set(Integer i)
			provisos(Monad#(m), IsModule#(m, a__)) = mkDWire(cacheFlushReq[0][i] == 1'b1);
		Vector#(3, Wire#(Bool)) cacheFlushReq_set <- genWithM(mk_cacheFlushReq_set);
		
		function m#(Wire#(Bool)) mk_cacheFlushReqPending_set0(Integer i)
			provisos(Monad#(m), IsModule#(m, a__)) = mkDWire(cacheFlushReqPending[0][i] == 1'b1);
		Vector#(3, Wire#(Bool)) cacheFlushReqPending_set0 <- genWithM(mk_cacheFlushReqPending_set0);
		function m#(Wire#(Bool)) mk_cacheFlushReqPending_set1(Integer i)
			provisos(Monad#(m), IsModule#(m, a__)) = mkDWire(cacheFlushReqPending_set0[i]);
		Vector#(3, Wire#(Bool)) cacheFlushReqPending_set1 <- genWithM(mk_cacheFlushReqPending_set1);
		
		rule r_cacheFlushReq_set;
			Bit#(3) cacheFlushReq_new = '0;
			for (Integer i = 0; i < 3; i=i+1) begin
				cacheFlushReq_new[i] = cacheFlushReq_set[i] ? 1'b1 : 1'b0;
			end
			cacheFlushReq[0] <= cacheFlushReq_new;
		endrule
		rule r_cacheFlushReqPending_set;
			Bit#(3) cacheFlushReqPending_new = '0;
			for (Integer i = 0; i < 3; i=i+1) begin
				cacheFlushReqPending_new[i] = cacheFlushReqPending_set1[i] ? 1'b1 : 1'b0;
			end
			cacheFlushReqPending[0] <= cacheFlushReqPending_new;
		endrule
		
		// --------------------------------- STALL HANDLING ---------------------------------------
		Reg#(Bool)      skip_stalls2 <- mkReg(False);
		rule set_skip_stalls2;
			skip_stalls2 <= skip_stalls;
		endrule
		
		Wire#(Bool) doStall <- mkDWire(cf.getStallSignal() || bitmap_handler.getStallSignal());
		
		rule setStall;
			Bool _doStall = cf.getStallSignal() || bitmap_handler.getStallSignal();
			`ifdef NOSTALLS
			_doStall = False;
			`endif
			doStall <= _doStall && !skip_stalls2;
			if (_doStall)
				feature_log($format("Stalling core"), L_CORE_STALLS);
		endrule

		// ----------------------------- METHODS AND INTERFACES ----------------------------------- 
		
		method Action cfdata(Bool cf_valid, Bit#(32) cf_curInst, Bit#(32) cf_curPC, Bit#(32) cf_nextPC);
			curr_instr_Valid <= cf_valid;
			curr_instr <= cf_curInst;
			curr_instr_pc <= cf_curPC;
			next_pc_Valid <= cf_valid;
			next_pc <= cf_nextPC;
		endmethod
		
		method Action excdata(Bool valid, Bit#(5) cause, Bit#(32) tval, Bit#(32) epc);
			exc_valid <= valid;
			exc_cause <= cause;
			exc_tval <= tval;
			exc_epc <= epc;
		endmethod

		method Bool rst();
			return resetting();
		endmethod

		method Bool rstn();
			return nresetting();
		endmethod

		method Bool irq();
			return intr;
		endmethod
		
		method Bool stall();
			return doStall;
		endmethod

		interface GenericAxi4LiteSlave s_axi_ctrl = a4sl;

		interface AXI4_Slave s_axi_bram;
			interface AXI4_Slave_Rd_Fab rd = rds.fab;
			interface AXI4_Slave_Wr_Fab wr = wrs.fab;
		endinterface
		
		interface AXI4_Master m_axi_cpu_mem;
			interface AXI4_Master_Rd_Fab rd = rdm.fab;
			interface AXI4_Master_Wr_Fab wr = wrm.fab;
		endinterface
		
		interface Client icache_invalidate;
			interface Get request;
				method ActionValue#(Bool) get() if (!started && cacheFlushReq[0][0] == 1'b1);
					cacheFlushReq_set[0] <= False;
					cacheFlushReqPending_set0[0] <= True;
					return True;
				endmethod
			endinterface
			interface Put response;
				method Action put(Bool _);
					cacheFlushReqPending_set1[0] <= False;
				endmethod
			endinterface
		endinterface
		interface Client bp_invalidate;
			interface Get request;
				method ActionValue#(Bool) get() if (!started && cacheFlushReq[0][1] == 1'b1);
					cacheFlushReq_set[1] <= False;
					cacheFlushReqPending_set0[1] <= True;
					return True;
				endmethod
			endinterface
			interface Put response;
				method Action put(Bool _);
					cacheFlushReqPending_set1[1] <= False;
				endmethod
			endinterface
		endinterface
		interface Client dcache_invalidate;
			interface Get request;
				method ActionValue#(Bool) get() if (!started && cacheFlushReq[0][2] == 1'b1);
					cacheFlushReq_set[2] <= False;
					cacheFlushReqPending_set0[2] <= True;
					return True;
				endmethod
			endinterface
			interface Put response;
				method Action put(Bool _);
					cacheFlushReqPending_set1[2] <= False;
				endmethod
			endinterface
		endinterface
		
		method Bit#(12) setup_sectionid_val() = progmemSection;
		method Bool setup_sectionid_en() = True;

	endmodule

endpackage
