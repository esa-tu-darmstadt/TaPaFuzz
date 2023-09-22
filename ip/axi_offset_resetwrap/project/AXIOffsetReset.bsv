//AXI Shim IP: Offset and Safe Local Reset
// Sits between a processor core's memory interface (or any other supported AXI4 Master) and the actual bus.
// Transparently adds an address offset to all requests,
//  represented as runtime-configurable index inserted into a constant position in the address.
//  actual_addr = (index_val << SECTION_IDX_SHIFT) | (requested_addr & ~({SECTION_IDX_WIDTH{1'b1}} << SECTION_IDX_SHIFT)).
// Safely carries on outstanding bus requests during core-only resets.
//  Without this shim, the bus may crash or become locked up.
// Provides an output core reset signal to ensure the core will be restarted only once all outstanding bus requests are done.
//Author: Florian Meisel
//Based on BlueAXI code (MIT licensed, see axi/LICENSE).
package AXIOffsetReset;
	
	import Assert::*;
	import FIFOF::*;
	import AXI4_Slave::*;
	import AXI4_Types::*;
	import AXI4_Master::*;
	import Clocks :: *;
	
	interface AXIOffsetResetIntf#(numeric type sectionid_width, numeric type axi_id_width);
		(* prefix = "s_axi" *)
		interface AXI4_Slave_Rd_Fab#(32, 32, axi_id_width, 0) s_axi_rd;
		(* prefix = "s_axi" *)
		interface AXI4_Slave_Wr_Fab#(32, 32, axi_id_width, 0) s_axi_wr;
		
		(* prefix = "m_axi" *)
		interface AXI4_Master_Rd_Fab#(32, 32, axi_id_width, 0) m_axi_rd;
		(* prefix = "m_axi" *)
		interface AXI4_Master_Wr_Fab#(32, 32, axi_id_width, 0) m_axi_wr;
		
		//Core reset signal input.
		(* always_ready, always_enabled *)
		(* prefix = "" *) method Action pcore_rst_in((*port="core_rst_in"*)Bool r);
		
		//Core reset signal output.
		// Invariant: (core_rst_in == True) ==> (core_rst() == True).
		//Increases the duration of a reset where necessary to complete all outstanding transactions.
		(* always_ready, always_enabled *)
		method Bool core_rst();
		//Inverse of core_rst (comb.).
		(* always_ready, always_enabled *)
		method Bool core_rstn();
		
		(* always_ready *)
		method Action setup(Bit#(sectionid_width) sectionid);
		
	endinterface
	
	module mkAXIOffsetReset 
		#((* parameter="SECTION_IDX_SHIFT" *) parameter UInt#(5) section_idx_shift)
		(AXIOffsetResetIntf#(sectionid_width, axi_id_width))
		provisos(Add#(a__, sectionid_width, 32));
		
		//Global reset signal.
		let full_rst <- isResetAsserted();
		
		Wire#(Bool) core_rst_in_ <- mkBypassWire();
		Reg#(Bool) core_rst_pending_wburst <- mkReg(False);
		//Stores the core reset from the previous cycle. Set to True initially and on global reset.
		Reg#(Bool) core_rst_r <- mkReg(True);
		//Set if there is a pending AXI handshake with core as the source,
		// where the valid signal has been set already.
		Reg#(Bool) core_rst_pending_handshakes <- mkReg(False);
		//Delay end of reset if responses are still pending.
		//-> Prevents the core from being confronted with responses
		//   to requests it has 'forgotten' due to being reset.
		Reg#(Bool) core_rst_pending_responses <- mkReg(False);
		
		//Store core_rst_pending_* in a BypassWire at the beginning of each cycle,
		// since rule conflicts would otherwise appear with core_rst_r_update
		// (rules that write core_rst_pending_* can read core_rst_r <-> core_rst_r_update reads core_rst_pending_*).
		Wire#(Bool) core_rst_pending_wburst_ <- mkBypassWire;
		Wire#(Bool) core_rst_pending_handshakes_ <- mkBypassWire;
		Wire#(Bool) core_rst_pending_responses_ <- mkBypassWire;
		(* no_implicit_conditions *)
		rule __a;
			core_rst_pending_wburst_ <= core_rst_pending_wburst;
			core_rst_pending_handshakes_ <= core_rst_pending_handshakes;
			core_rst_pending_responses_ <= core_rst_pending_responses;
		endrule
		
		function Bool _core_rst();
			//Some (minimal) combinatorial logic in the reset signal.
			return core_rst_in_ || core_rst_pending_wburst_ || core_rst_r && (core_rst_pending_handshakes_ || core_rst_pending_responses_);
		endfunction
		
		(* no_implicit_conditions *)
		rule core_rst_r_update;
			core_rst_r <= _core_rst();
		endrule
		
		//Stores the 'offset'.
		Reg#(Bit#(sectionid_width)) r_sectionid <- mkReg(0);
		
		//Describes the number of beats (burst length) of the next 0..N bursts.
		FIFOF#(UInt#(8)) burst_length_FIFO <- mkSizedFIFOF(8); //Allow 8 pending requests.
		
		Wire#(Bool) burst_length_FIFO_notFull_ <- mkBypassWire;
		(* no_implicit_conditions *)
		rule __b;
			burst_length_FIFO_notFull_ <= burst_length_FIFO.notFull();
		endrule
		
		//- burst_length_cur, burst_length_cur_valid: Number of remaining beats in the current burst (0 while valid means: 1 beat is remaining).
		//-> If valid, [burst_length_cur, burst_length_FIFO.first, ...] is the logical 'remaining beats per burst' buffer.
		//   Since FIFO entries are not mutable yet the beat count needs to be decreased continuously, these extra registers are used.
		Reg#(Bool) burst_length_cur_valid <- mkReg(False);
		Reg#(UInt#(8)) burst_length_cur <- mkReg(0);
		
		//Applies the offset to a given core-side memory address.
		function Bit#(32) addr_add_offset(Bit#(32) addr);
			Bit#(32) addr_mask_nonshift = (1 << fromInteger(valueOf(sectionid_width))) - 1;
			//Mask to apply to addr (i.e. mask off all Section ID bits).
			let addr_mask = ~(addr_mask_nonshift << pack(UInt#(32)'(extend(section_idx_shift))));
			//The Section ID to apply to the address.
			let id_shifted = Bit#(32)'(zeroExtend(r_sectionid)) << pack(UInt#(32)'(extend(section_idx_shift)));
			
			return (addr & addr_mask) | id_shifted;
		endfunction

		Wire#(Bool) arreadyIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		Wire#(Bool) arvalidIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		Wire#(AXI4_Read_Rq#(32, axi_id_width, 0)) arpkgIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		function Action arChannel(Bit#(axi_id_width) id,
		                          Bit#(32) addr,
		                          UInt#(8) burst_length,
		                          AXI4_BurstSize burst_size,
		                          AXI4_BurstType burst_type,
		                          AXI4_Lock lock,
		                          AXI4_Read_Cache cache,
		                          AXI4_Prot prot,
		                          Bit#(4) qos,
		                          Bit#(4) region,
		                          Bit#(0) user);
			action
				arpkgIn <= AXI4_Read_Rq {id: id, addr: addr_add_offset(addr), burst_length: burst_length, burst_size: burst_size, burst_type: burst_type
								, lock: lock, cache: cache, prot: prot, qos: qos, region: region, user: user};
			endaction
		endfunction
		
		Wire#(Bool) rreadyIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		Wire#(Bool) rvalidIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		Wire#(AXI4_Read_Rs#(32, axi_id_width, 0)) rpkgIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		function Action rChannel(Bit#(axi_id_width) id, Bit#(32) d, AXI4_Response resp, Bool last, Bit#(0) user);
			action
				rpkgIn <= AXI4_Read_Rs {id: id, data: d, last: last, user: user, resp: resp};
			endaction
		endfunction
		
		Wire#(Bool) awreadyIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		Wire#(Bool) awvalidIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		Wire#(AXI4_Write_Rq_Addr#(32, axi_id_width, 0)) awpkgIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		function Action awChannel(Bit#(axi_id_width) id,
		                          Bit#(32) addr,
		                          UInt#(8) burst_length,
		                          AXI4_BurstSize burst_size,
		                          AXI4_BurstType burst_type,
		                          AXI4_Lock lock,
		                          AXI4_Write_Cache cache,
		                          AXI4_Prot prot,
		                          Bit#(4) qos,
		                          Bit#(4) region,
		                          Bit#(0) user);
			action
				awpkgIn <= AXI4_Write_Rq_Addr {id: id, addr: addr_add_offset(addr), burst_length: burst_length, burst_size: burst_size, burst_type: burst_type
										, lock: lock, cache: cache, prot: prot, qos: qos, region: region, user: user};
			endaction
		endfunction
		
		Wire#(Bool) wreadyIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		Wire#(Bool) wvalidIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		Wire#(AXI4_Write_Rq_Data#(32, 0)) wpkgIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		function Action wChannel(Bit#(32) data,
		                         Bit#(TDiv#(32, 8)) strb,
		                         Bool last,
		                         Bit#(0) user
		                         );
			action
				wpkgIn <= AXI4_Write_Rq_Data {data: data, strb: strb, last: last, user: user};
			endaction
		endfunction
		Wire#(Bool) breadyIn <- mkBypassWire(); //bus S<-M AXIOffsetReset S<-M core
		Wire#(Bool) bvalidIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		Wire#(AXI4_Write_Rs#(axi_id_width, 0)) wresppkgIn <- mkBypassWire(); //bus S->M AXIOffsetReset S->M core
		function Action wrespChannel(AXI4_Response r, Bit#(axi_id_width) bid, Bit#(0) buser);
			action
				wresppkgIn <= AXI4_Write_Rs {id: bid, user: buser, resp: r};
			endaction
		endfunction
		
		//The AXI specification says that valid (and the request information) must not be reset before the destination has set ready.
		//Hence, the scenario where a core-only reset occurs during an unfinished core->bus handshake needs to be handled
		// by caching the already started request information and resetting valid only once the handshake is done.
		
		//Set if an ar (address read) request from the core was delayed due to aready not being set by the bus yet,
		// i.e. the core has to repeat its request for at least the next cycle (unless a core reset starts).
		Reg#(Bool) arvalidIn_delayed <- mkReg(False);
		//(See arvalidIn_delayed), but for aw (address write) requests from the core.
		Reg#(Bool) awvalidIn_delayed <- mkReg(False);
		//(See arvalidIn_delayed), but for w (write beat) requests from the core.
		Reg#(Bool) wvalidIn_delayed <- mkReg(False);
		
		//Counts the number of write bursts still awaiting the result (b.. channel)
		Reg#(UInt#(4)) wresp_num_pending <- mkReg(0);
		function Bool wresp_num_pending_notFull() = (wresp_num_pending != 15);
		//Counts the number of requested read bursts where the last beat has not arrived yet (r.. channel).
		// -> Number is only decreased on read responses with rlast set.
		Reg#(UInt#(4)) rresp_num_pending <- mkReg(0);
		function Bool rresp_num_pending_notFull() = (rresp_num_pending != 15);
		
		//w_completed_ticks_before_addr: Number of performed beats not yet carried over to the burst tracker (1 means 1 beat was performed).
		Reg#(UInt#(8)) w_completed_ticks_before_addr[2] <- mkCReg(2, 0);
		function Bool w_completed_ticks_before_addr_notFull() = (w_completed_ticks_before_addr[0] != 255);
		
		//Returns whether a new ar handshake from the core is starting.
		function Bool ar_handshake_isnew() = arvalidIn && rresp_num_pending_notFull() && !arvalidIn_delayed && !core_rst_r;
		//Returns whether a new aw handshake from the core is starting.
		function Bool aw_handshake_isnew() = awvalidIn && burst_length_FIFO_notFull_ && wresp_num_pending_notFull() && !awvalidIn_delayed && !core_rst_r;
		//Returns whether a new w handshake from the core is starting.
		function Bool w_handshake_isnew() = wvalidIn && w_completed_ticks_before_addr_notFull() && !wvalidIn_delayed && !core_rst_r;
		
		//arpkgIn from the last !core_rst_r cycle.
		Reg#(AXI4_Read_Rq#(32, axi_id_width, 0)) arpkgIn_r <- mkRegU();
		//awpkgIn from the last !core_rst_r cycle.
		Reg#(AXI4_Write_Rq_Addr#(32, axi_id_width, 0)) awpkgIn_r <- mkRegU();
		//wpkgIn from the last !core_rst_r cycle.
		Reg#(AXI4_Write_Rq_Data#(32, 0)) wpkgIn_r <- mkRegU();
		
		Wire#(Bool) wresp_num_pending_notFull_ <- mkBypassWire;
		Wire#(Bool) rresp_num_pending_notFull_ <- mkBypassWire;
		Wire#(Bool) w_completed_ticks_before_addr_notFull_ <- mkBypassWire;
		(* no_implicit_conditions *)
		rule __c;
			wresp_num_pending_notFull_ <= wresp_num_pending_notFull();
			rresp_num_pending_notFull_ <= rresp_num_pending_notFull();
			w_completed_ticks_before_addr_notFull_ <= w_completed_ticks_before_addr_notFull();
		endrule
		rule update_slaveIn_r(!core_rst_r);
			dynamicAssert(!arvalidIn_delayed || arvalidIn, "arvalid deasserted before handshake finished");
			dynamicAssert(!awvalidIn_delayed || awvalidIn, "awvalid deasserted before handshake finished");
			dynamicAssert(!wvalidIn_delayed || wvalidIn, "wvalid deasserted before handshake finished");
			
			Bool _arvalidIn_delayed = arvalidIn && rresp_num_pending_notFull_ && !arreadyIn;
			Bool _awvalidIn_delayed = awvalidIn && burst_length_FIFO_notFull_ && wresp_num_pending_notFull_ && !awreadyIn;
			Bool _wvalidIn_delayed = wvalidIn && w_completed_ticks_before_addr_notFull_ && !wreadyIn;
			arvalidIn_delayed <= _arvalidIn_delayed;
			awvalidIn_delayed <= _awvalidIn_delayed;
			wvalidIn_delayed <= _wvalidIn_delayed;
			core_rst_pending_handshakes <= _arvalidIn_delayed || _awvalidIn_delayed || _wvalidIn_delayed;
			awpkgIn_r <= awpkgIn;
			wpkgIn_r <= wpkgIn;
			arpkgIn_r <= arpkgIn;
		endrule
		rule reset_slaveIn_r(core_rst_r);
			Bool _arvalidIn_delayed = arvalidIn_delayed && !arreadyIn;
			Bool _awvalidIn_delayed = awvalidIn_delayed && !awreadyIn;
			Bool _wvalidIn_delayed = wvalidIn_delayed && !wreadyIn;
			arvalidIn_delayed <= _arvalidIn_delayed;
			awvalidIn_delayed <= _awvalidIn_delayed;
			wvalidIn_delayed <= _wvalidIn_delayed;
			core_rst_pending_handshakes <= _arvalidIn_delayed || _awvalidIn_delayed || _wvalidIn_delayed;
		endrule
		
		//Set if an r (read) response from the bus was delayed since the core was not ready,
		// i.e. the bus has to repeat the response for at least the next cycle.
		Reg#(Bool) rvalidIn_delayed <- mkReg(False);
		function Bool r_handshake_isnew() = rvalidIn && !rvalidIn_delayed;
		//(See rvalidIn_delayed), but for b (write) responses from the bus.
		Reg#(Bool) bvalidIn_delayed <- mkReg(False);
		function Bool b_handshake_isnew() = bvalidIn && !bvalidIn_delayed;
		rule update_masterIn_delayed;
			dynamicAssert(!rvalidIn_delayed || rvalidIn, "rvalid deasserted before handshake finished");
			dynamicAssert(!bvalidIn_delayed || bvalidIn, "bvalid deasserted before handshake finished");
			
			Bool _rvalidIn_delayed = rvalidIn && !(core_rst_r || rreadyIn); //rvalidIn && !m_axi_rd.rready
			Bool _bvalidIn_delayed = bvalidIn && !(core_rst_r || breadyIn); //bvalidIn && !m_axi_wr.bready
			
			rvalidIn_delayed <= _rvalidIn_delayed;
			bvalidIn_delayed <= _bvalidIn_delayed;
		endrule
		
		//Selects the aw request 'body' from the core or the buffered variant, depending on whether the core has been reset (/continues to be).
		function AXI4_Write_Rq_Addr#(32, axi_id_width, 0) awpkgSelect() = core_rst_r ? awpkgIn_r : awpkgIn;
		//Analogous to awpkgSelect.
		function AXI4_Write_Rq_Data#(32, 0) wpkgSelect() = core_rst_r ? wpkgIn_r : wpkgIn;
		//Analogous to arpkgSelect.
		function AXI4_Read_Rq#(32, axi_id_width, 0) arpkgSelect() = core_rst_r ? arpkgIn_r : arpkgIn;
		
		rule core_rst_pending_wburst_stop(!core_rst_in_
		                               && w_completed_ticks_before_addr[0] == 0 && !burst_length_cur_valid && !burst_length_FIFO.notEmpty());
			core_rst_pending_wburst <= False;
		endrule
		rule core_rst_pending_wburst_start(core_rst_in_
		                               && (w_completed_ticks_before_addr[0] != 0 || burst_length_cur_valid || burst_length_FIFO.notEmpty() || aw_handshake_isnew()));
			core_rst_pending_wburst <= True;
		endrule
		
		rule count_new_beat(w_handshake_isnew()
			|| (core_rst_r && wreadyIn && !wvalidIn_delayed && burst_length_cur_valid && burst_length_cur >= w_completed_ticks_before_addr[0]));
			//If a new beat handshake is started by the core,
			// or if a dummy beat is about to complete,
			// increase the amount of beats to carry over.
			w_completed_ticks_before_addr[0] <= w_completed_ticks_before_addr[0] + 1;
		endrule
		//Updates the scratch burst length registers by carrying over w_completed_ticks_before_addr[1] to burst_length_cur.
		rule burst_length_cur_update(burst_length_cur_valid);
			UInt#(8) decrease_burstcount = w_completed_ticks_before_addr[1];
			if (decrease_burstcount > burst_length_cur) begin
				//Burst has ended.
				//Note: (burst_length_cur_valid,burst_length_cur) = (True, 0) -> (False, ?)
				// also consumes one beat, e.g. a single-beat burst has a burst length value of 0.
				burst_length_cur_valid <= False;
				decrease_burstcount = decrease_burstcount - (burst_length_cur + 1);
			end
			else begin
				//Burst still has remaining beat(s).
				burst_length_cur <= burst_length_cur - decrease_burstcount;
				decrease_burstcount = 0;
			end
			//Finally, update the counter for 'unapplied' finished beats.
			w_completed_ticks_before_addr[1] <= decrease_burstcount;
		endrule
		//Dequeue from burst_length_FIFO into the scratch burst length register.
		rule burst_length_cur_next(!burst_length_cur_valid);
			burst_length_cur <= burst_length_FIFO.first;
			burst_length_cur_valid <= True;
			burst_length_FIFO.deq();
		endrule
		//Enqueue into burst_length_FIFO if a new aw request arrives.
		rule burst_enqueue(aw_handshake_isnew());
			burst_length_FIFO.enq(awpkgIn.burst_length);
		endrule
		
		//Update the counters for remaining read/write burst responses.
		rule update_resp_num_pending;
			dynamicAssert(!r_handshake_isnew() || rresp_num_pending > 0, "Got a read response with no matching request");
			//The last read result of a burst decreases rresp_num_pending by 1,
			// a new ar request increases it by 1.
			UInt#(4) rresp_num_pending_new = rresp_num_pending;
			if (r_handshake_isnew() && rpkgIn.last && !ar_handshake_isnew()) begin
				dynamicAssert(rresp_num_pending > 0, "rresp_num_pending_new underflow");
				rresp_num_pending_new = rresp_num_pending_new - 1;
			end
			else if (!(r_handshake_isnew() && rpkgIn.last) && ar_handshake_isnew()) begin
				dynamicAssert(rresp_num_pending_notFull(), "rresp_num_pending_new overflow");
				rresp_num_pending_new = rresp_num_pending_new + 1;
			end
			rresp_num_pending <= rresp_num_pending_new;
			
			dynamicAssert(!b_handshake_isnew() || wresp_num_pending > 0, "Got a write response with no matching request");
			//A write result decreases rresp_num_pending by 1,
			// a new aw request increases it by 1.
			UInt#(4) wresp_num_pending_new = wresp_num_pending;
			if (b_handshake_isnew() && !aw_handshake_isnew()) begin
				dynamicAssert(wresp_num_pending > 0, "wresp_num_pending_new underflow");
				wresp_num_pending_new = wresp_num_pending_new - 1;
			end
			else if (!b_handshake_isnew() && aw_handshake_isnew()) begin
				dynamicAssert(wresp_num_pending_notFull(), "wresp_num_pending_new overflow");
				wresp_num_pending_new = wresp_num_pending_new + 1;
			end
			wresp_num_pending <= wresp_num_pending_new;
			
			core_rst_pending_responses <= (rresp_num_pending_new != 0 || wresp_num_pending_new != 0);
		endrule
		
		//Detect unsupported scenario:
		// w.. requests come before aw.. requests.
		//This is not supported, since the shim is not able to compose custom aw.. requests.
		// If a reset occurs before the aw.. request in such a case, the upstream bus will be stuck waiting.
		//At the same time, the shim is designed to allow simultaneous w.. and aw.. requests so as not to increase bus latency.
		continuousAssert(core_rst_r || !w_handshake_isnew() || (aw_handshake_isnew() || burst_length_cur_valid || burst_length_FIFO.notEmpty),
			"Unsupported: Core initiated AXI write before write address");		
		
		method Action pcore_rst_in(Bool r);
			core_rst_in_ <= r;
		endmethod
		method Bool core_rst() = _core_rst();
		method Bool core_rstn() = !_core_rst();
		method Action setup(Bit#(sectionid_width) sectionid);
			r_sectionid <= sectionid;
		endmethod
		
		//The ready signal to the core must be false during the first post-reset cycle,
		// as core_rst_r still is set and the core may potentially start a new handshake already,
		// which this module is not able to redirect immediately.
		//-> If ready is not immediately set for the core,
		//   it will (have to) keep the request signals stable for the following cycle(s).
		
		interface AXI4_Slave_Wr_Fab s_axi_wr;
			interface awready = awreadyIn && !core_rst_r && burst_length_FIFO.notFull && wresp_num_pending_notFull;
			interface pawvalid = awvalidIn._write;
			interface pawchannel = awChannel;

			interface wready = wreadyIn && !core_rst_r && w_completed_ticks_before_addr_notFull();
			interface pwvalid = wvalidIn._write;
			interface pwchannel = wChannel;

			interface pbready = breadyIn._write;
			interface bvalid = !core_rst_r && bvalidIn;
			interface bresp = wresppkgIn.resp;
			interface bid =   wresppkgIn.id;
			interface buser = wresppkgIn.user;
		endinterface
		
		interface AXI4_Master_Wr_Fab m_axi_wr;
			interface pawready  = awreadyIn._write;
			interface awvalid   = !full_rst && (core_rst_r ? awvalidIn_delayed : (awvalidIn && burst_length_FIFO.notFull));
			interface awid      = awpkgSelect().id;
			interface awaddr    = awpkgSelect().addr;
			interface awlen     = awpkgSelect().burst_length;
			interface awsize    = awpkgSelect().burst_size;
			interface awburst   = awpkgSelect().burst_type;
			interface awlock    = awpkgSelect().lock;
			interface awcache   = awpkgSelect().cache;
			interface awprot    = awpkgSelect().prot;
			interface awqos     = awpkgSelect().qos;
			interface awregion  = awpkgSelect().region;
			interface awuser    = awpkgSelect().user;

			interface pwready   = wreadyIn._write;
			//Write requests: Insert dummy beats with wstrb=0 if the core is being reset while writes are pending.
			interface wvalid    = !full_rst && w_completed_ticks_before_addr_notFull() &&
			                               (  (core_rst_r ? wvalidIn_delayed : wvalidIn)
			                               || (core_rst_r && burst_length_cur_valid && burst_length_cur >= w_completed_ticks_before_addr[0]));
			interface wdata     = wpkgSelect().data;
			interface wstrb     = (core_rst_pending_wburst && !wvalidIn_delayed) ? 0 : wpkgSelect().strb;
			interface wlast     = ((core_rst_pending_wburst && !wvalidIn_delayed) ? (burst_length_cur <= w_completed_ticks_before_addr[0]) : wpkgSelect().last);
			interface wuser     = wpkgSelect().user;

			interface pbvalid = bvalidIn._write;
			interface bready = (!full_rst && core_rst_r) || breadyIn;
			interface bin = wrespChannel;
		endinterface
		
		interface AXI4_Slave_Rd_Fab s_axi_rd;
			interface parvalid = arvalidIn._write;
			interface arready = arreadyIn && !core_rst_r;
			interface parchannel = arChannel;

			interface prready = rreadyIn._write;
			interface rvalid = !core_rst_r && rvalidIn;
			interface rid =   rpkgIn.id;
			interface rdata = rpkgIn.data;
			interface rresp = rpkgIn.resp;
			interface rlast = rpkgIn.last;
			interface ruser = rpkgIn.user;
		endinterface
		interface AXI4_Master_Rd_Fab m_axi_rd;
			interface parready = arreadyIn._write;
			interface arvalid = !full_rst && (core_rst_r ? arvalidIn_delayed : arvalidIn);
			interface arid =     arpkgSelect().id;
			interface araddr =   arpkgSelect().addr;
			interface arlen =    arpkgSelect().burst_length;
			interface arsize =   arpkgSelect().burst_size;
			interface arburst =  arpkgSelect().burst_type;
			interface arlock =   arpkgSelect().lock;
			interface arcache =  arpkgSelect().cache ;
			interface arprot =   arpkgSelect().prot;
			interface arqos =    arpkgSelect().qos;
			interface arregion = arpkgSelect().region;
			interface aruser =   arpkgSelect().user;

			interface rready = (!full_rst && core_rst_r) || rreadyIn;
			interface prvalid = rvalidIn._write;
			interface prchannel = rChannel;
		endinterface
		
	endmodule
	
	module mkAXIOffsetReset_12_6(AXIOffsetResetIntf#(12, 6) intf); //Section width: 1M
		AXIOffsetResetIntf#(12, 6) _mod <- mkAXIOffsetReset(truncate(UInt#(6)'(32-12)));
		
		interface AXI4_Slave_Rd_Fab s_axi_rd = _mod.s_axi_rd;
		interface AXI4_Slave_Wr_Fab s_axi_wr = _mod.s_axi_wr;
		
		interface AXI4_Master_Rd_Fab m_axi_rd = _mod.m_axi_rd;
		interface AXI4_Master_Wr_Fab m_axi_wr = _mod.m_axi_wr;
		
		interface pcore_rst_in = _mod.pcore_rst_in;
		interface core_rst = _mod.core_rst;
		interface core_rstn = _mod.core_rstn;
		interface setup = _mod.setup;
	endmodule
	
	module mkAXIOffsetReset_8_6(AXIOffsetResetIntf#(8, 6) intf); //Section width: 16M
		AXIOffsetResetIntf#(8, 6) _mod <- mkAXIOffsetReset(truncate(UInt#(6)'(32-8)));
		
		interface AXI4_Slave_Rd_Fab s_axi_rd = _mod.s_axi_rd;
		interface AXI4_Slave_Wr_Fab s_axi_wr = _mod.s_axi_wr;
		
		interface AXI4_Master_Rd_Fab m_axi_rd = _mod.m_axi_rd;
		interface AXI4_Master_Wr_Fab m_axi_wr = _mod.m_axi_wr;
		
		interface pcore_rst_in = _mod.pcore_rst_in;
		interface core_rst = _mod.core_rst;
		interface core_rstn = _mod.core_rstn;
		interface setup = _mod.setup;
	endmodule
endpackage
