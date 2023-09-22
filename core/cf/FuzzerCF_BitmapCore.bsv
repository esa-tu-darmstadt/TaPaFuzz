package FuzzerCF_BitmapCore;
	import FIFO::*;
	import FIFOF::*;
	import FIFOLevel::*;
	import SpecialFIFOs::*;
	import BRAM::*;
	import BRAMCore::*;
	import Vector::*;
	import DReg::*;
	import FuzzerTypes::*;
	import FuzzerCF_CfDetectors::*;
	import Logging::*;
	import AXI4_Types::*;
	import AXI4_Master::*;
	
	typedef enum{
		UpdateIdle, UpdateCalcAddr, UpdateRead, UpdateWrite
	} T_UpdateState deriving(Eq, Bits);

	//Simple Get-like interface that accepts 
	interface GetForID#(type restype, type idtype);
		//Since arguments can't be used as a method condition,
		// call accepts_id and add the result to the caller's condition.
		method Bool for_id(idtype _id);
		//Equivalent to Get::get.
		//If arguments were allowed in implicit method conditions,
		// this would accept an idtype parameter.
		method ActionValue#(restype) get();
	endinterface
	interface PutIfID#(type puttype, type idtype);
		//Since arguments can't be used as a method condition,
		// call accepts_id and add the result to the caller's condition.
		method Bool accepts_id(idtype _id);
		//Equivalent to Put::put.
		method Action put(puttype req);
	endinterface

	interface FuzzerBitmapCoreIfc#(numeric type addr_width, numeric type data_width, numeric type id_width, numeric type user_width);
		//Checks whether a given bitmap size is allowed.
		(* always_ready *)
		method Bool isValidSize(UInt#(32) bitmap_size);
		//Signals if this module requests a core pipeline stall.
		//-> Set depending on FIFO level to prevent overflows / skipped CF events down the line.
		(* always_ready *)
		method Bool getStallSignal();
		//Returns whether the external bitmap memory is valid.
		//-> Returns False if at least one bitmap request is not fully handled yet.
		//-> Returns False if there could be cached bitmap values
		//    that are not updated in external memory.
		//   Call flush to initiate a write back.
		//-> Returns True otherwise.
		(* always_ready *)
		method Bool isFlushed();
		//Zeroes the bitmap once all requests are handled.
		//Marks the bitmap as flushed if no requests are added in between.
		//Expects the end pointer to be at least (data_width/8 * 256) below FFFFFFFFh,
		//        and bitmap_size to be a power of 2 of at least data_width/8.
		//bitmap_addr_end points to the first byte after the bitmap region.
		(* always_ready *)
		method Action clear(Bit#(32) bitmap_addr_begin, UInt#(32) bitmap_size);
		//Call to write the bitmap to memory.
		//The flush will be delayed until all pending requests
		// (added up until some point in the flushing process) are handled.
		method Action flush();
		
		interface Put#(T_Fuzzer_BitmapUpdateReq) fuzzBitmapReq_ifc;	// Interface write CF event hash
		
		interface Get#(AXI4_Write_Rq_Addr#(addr_width, id_width, user_width)) bitmap_waddr_ifc;
		interface GetForID#(AXI4_Write_Rq_Data#(data_width, user_width), Bit#(id_width)) bitmap_wdata_ifc;
		interface PutIfID#(AXI4_Write_Rs#(id_width, user_width), Bit#(id_width)) bitmap_wrs_ifc;
		interface Get#(AXI4_Read_Rq#(addr_width, id_width, user_width)) bitmap_raddr_ifc;
		interface PutIfID#(AXI4_Read_Rs#(data_width, id_width, user_width), Bit#(id_width)) bitmap_rdata_ifc;
	endinterface
	
	module mkFuzzerCF_BitmapCore#(AXI4_BurstSize maxBurst)
		(FuzzerBitmapCoreIfc#(addr_width, data_width, id_width, user_width))
		provisos(
			Add#(32,0,addr_width),
			Add#(8,__a,data_width),
			Add#(1, __b, TDiv#(data_width,8)),
			
			Bits#(T_FuzzerAxiIDRead, id_width), Bits#(T_FuzzerAxiIDWrite, id_width)
			);
		
		Wire#(AXI4_Read_Rs#(data_width, id_width, user_width)) readResult <- mkWire;
		
		//Read address to pass to bitmap_raddr_ifc.get() callers.
		Wire#(AXI4_Read_Rq#(addr_width, id_width, user_width)) readAddrReq <- mkWire;
		//Set if bitmap_raddr_ifc.get() is being called, i.e. readAddrReq will be committed by the end of this cycle.
		PulseWire reading_addr <- mkPulseWire;
		
		//Write address to pass to bitmap_waddr_ifc.get() callers.
		Wire#(AXI4_Write_Rq_Addr#(addr_width, id_width, user_width)) writeAddrReq <- mkWire;
		//Set if bitmap_waddr_ifc.get() is being called, i.e. writeAddrReq will be committed by the end of this cycle.
		PulseWire writing_addr <- mkPulseWire;
		
		//Write address to pass to bitmap_wdata_ifc.get() callers.
		Wire#(T_AxiWriteDataID#(data_width, id_width, user_width)) writeDataReq <- mkWire;
		//Set if bitmap_wdata_ifc.get() is being called, i.e. writeDataReq will be committed by the end of this cycle.
		PulseWire writing_data <- mkPulseWire;
		
		//Set if bitmap_wrs_ifc.put() is being called, i.e. a write burst is complete.
		PulseWire write_complete <- mkPulseWire;
		
		
		//Counter for the request FIFO.
		FIFOCountIfc#(T_Fuzzer_BitmapUpdateReq, 10)  bitmapUpdateReqFifo <- mkFIFOCount;
		
		Wire#(Bool) incr_bitmapUpdateReq_count <- mkDWire(False);
		
		Reg#(Bool) stall <- mkReg(False);
		rule update_stall;
			//Stall the core if the bitmap is nearly full:
			//- Stall signal is late by two cycles:
			//   bitmapUpdateReqFifo.enq | stall._write | stall set.
			//- Core itself may need another cycle:
			//  e.g. CV5 non-RT-LIFE trace interface could still generate one CF event.
			//  NOTE: Depends on core; RT-LIFE integrations immediately prevent further events.
			//Prevents dropped CF events once/if the stall propagates back to the CF event input FIFO (-> FuzzerCF_Hasher).
			stall <= (bitmapUpdateReqFifo.count >= (10-3));
		endrule
		
		Reg#(Bool) initialized <- mkReg(False);
		Reg#(Bool) clearReq <- mkReg(False);
		
		Reg#(Bit#(32)) bitmapAddr_begin <- mkReg(0);
		Reg#(Bit#(32)) bitmapAddr_end <- mkReg(0);
		Reg#(UInt#(32)) bitmap_size <- mkReg(0);
		Reg#(Bit#(32)) bitmap_hash_indexmask <- mkReg(0);
		
		//State of the bitmap update process.
		Reg#(T_UpdateState) cur_update_state[2] <- mkCReg(2, UpdateIdle);
		
		//---- Initialize bitmap (clear) ----
		Reg#(Bit#(32)) clearAddr_next <- mkReg(0);
		//Amount of beats still to send as data write requests.
		Reg#(UInt#(9)) clear_beats_pending[2] <- mkCReg(2, 0);
		//Amount of bursts still pending confirmation.
		Reg#(UInt#(9)) write_bursts_pending_confirm[2] <- mkCReg(2, 0);
		Reg#(Bool) clearing <- mkReg(False);
		rule initiate_clear(clearReq && !bitmapUpdateReqFifo.notEmpty && cur_update_state[0] == UpdateIdle);
			//Compute the bitmap hash mask: hash&mask will be the output index of an update.
			//Assume that bitmap_size is a simple power of two,
			// i.e. (hash mod bitmap_size) == (hash & (bitmap_size-1))
			//Construct the mask bitwise, setting a bit iff a higher bitmap_size bit is set.
			Bit#(32) indexmask = 0;
			for (Integer i_bit_hash = 0; i_bit_hash < 31; i_bit_hash = i_bit_hash + 1) begin
				Bool bit_mask = False;
				for (Integer i_bit_size = i_bit_hash + 1; i_bit_size < 32; i_bit_size = i_bit_size + 1) begin
					if (pack(bitmap_size)[i_bit_size] == 1) bit_mask = True;
				end
				indexmask[i_bit_hash] = bit_mask ? 1 : 0;
			end
			bitmap_hash_indexmask <= indexmask;
			
			if (!clearing) begin
				if (UInt#(32)'(unpack(bitmapAddr_end)) <= UInt#(32)'(unpack(bitmapAddr_begin))) begin
					initialized <= True;
					clearAddr_next <= ?;
					clearing <= False;
				end
				else begin
					initialized <= False;
					clearAddr_next <= bitmapAddr_begin;
					clearing <= True;
				end
			end
			clearReq <= False;
		endrule
		
		//Sets up a write address request for bitmap zero initialization.
		//-> Prepares data for possible bitmap_waddr_ifc.get call.
		//Assumption: No write goes past the end (<=> bitmap size is a power of two above 2^^data_width).
		rule clear_write_addr(clearing && clearAddr_next != bitmapAddr_end
				&& clear_beats_pending[0] < unpack(-1)
				&& write_bursts_pending_confirm[0] < unpack(-1));
			writeAddrReq <= AXI4_Write_Rq_Addr {
				id:				pack(AXIID_BitmapWrite),
				addr: 			clearAddr_next,
				burst_length: 	0, //1 beat; Note: When increasing, also check that clear_beats_pending[0] won't overflow. 
				burst_size: 	bitsToBurstSize(valueOf(data_width)), //1 full word
				burst_type: 	INCR,
				lock: 			NORMAL,
				cache: 			NORMAL_NON_CACHEABLE_BUFFERABLE,
				prot: 			UNPRIV_SECURE_DATA,
				qos: 			0,
				region: 		0,
				user: 			0
			};
		endrule
		//If the write addr request is forwarded to the bus, update the address and write counter.
		rule clear_on_enq_waddr_req(clearing && writing_addr);
			clearAddr_next <= clearAddr_next
				+ pack((extend(writeAddrReq.burst_length) + 1) * fromInteger(valueOf(data_width)/8));
			clear_beats_pending[0] <= clear_beats_pending[0] + (extend(writeAddrReq.burst_length) + 1);
			write_bursts_pending_confirm[0] <= write_bursts_pending_confirm[0] + 1;
		endrule
		
		//Sets up a write data request for bitmap zero initialization.
		//-> Prepares data for possible bitmap_wdata_ifc.get call.
		rule clear_write_data(clearing && clear_beats_pending[1] > 0);
			writeDataReq <= T_AxiWriteDataID {
				id:  pack(AXIID_BitmapWrite),
				req: AXI4_Write_Rq_Data { //Exactly the default from AXI4_Types (for now).
					data: 0,
					strb: unpack(-1),
					last: True, //Note: Only applicable for burst_length 0. clear_beats_pending counts all bursts.
					user: 0
				}
			};
		endrule
		//If the write data request is forwarded to the bus, update the counter check whether clearing is done.
		rule clear_on_enq_wdata_req(clearing && writing_data);
			clear_beats_pending[1] <= clear_beats_pending[1] - 1;
		endrule
		
		//If all writes are done, end the clearing sequence.
		(* descending_urgency = "clear_detect_end, initiate_clear" *)
		(* descending_urgency = "clear_write_data, clear_detect_end" *)
		(* descending_urgency = "clear_on_enq_wdata_req, clear_detect_end" *)
		(* descending_urgency = "clear_on_enq_waddr_req, clear_detect_end" *)
		rule clear_detect_end(clearing && clearAddr_next == bitmapAddr_end
				&& clear_beats_pending[0] == 0);
			initialized <= True;
			clearing <= False;
		endrule
		
		//---- Bitmap update ----
		//Request to handle. Valid for states UpdateCalcAddr, UpdateRead, UpdateWrite.
		Reg#(T_Fuzzer_BitmapUpdateReq) cur_request <- mkRegU;
		//Absolute address of the bitmap entry. Valid for states UpdateRead, UpdateWrite.
		Reg#(Bit#(32)) cur_request_addr <- mkRegU;
		//Counter value pre-update. Valid for state UpdateWrite.
		Reg#(UInt#(8)) cur_request_readdata <- mkRegU;
		Reg#(Bool) cur_request_raddr_set <- mkReg(False);
		Reg#(Bool) cur_request_waddr_set[2] <- mkCReg(2, False);
		
		//If ready, initiate a new request.
		//-> Also wait for all writes to complete.
		(* descending_urgency = "initiate_clear, handle_req" *)
		rule handle_req(!clearing && initialized && cur_update_state[1] == UpdateIdle
				&& write_bursts_pending_confirm[1] == (write_complete ? 1 : 0));
			let request = bitmapUpdateReqFifo.first;
			cur_update_state[1] <= UpdateCalcAddr;
			cur_request <= request;
			bitmapUpdateReqFifo.deq;
		endrule
		
		//-- Bitmap UpdateCalcAddr --
		
		rule update_calc_addr(!clearing && cur_update_state[0] == UpdateCalcAddr);
			cur_update_state[0] <= UpdateRead;
			cur_request_raddr_set <= False;
			cur_request_waddr_set[1] <= False;
			//Each entry is 8 bits wide.
			//For 16 bytes, for instance, the hash mask would have to be halved and the index would have to be doubled.
			cur_request_addr <= bitmapAddr_begin + (cur_request.hash & bitmap_hash_indexmask);
		endrule
		
		//-- Bitmap UpdateRead --
		
		//Sets up a write address request for bitmap updating.
		//-> Prepares data for possible bitmap_waddr_ifc.get call.
		rule update_read_addr(!clearing && cur_update_state[0] == UpdateRead && !cur_request_raddr_set);
			readAddrReq <= AXI4_Read_Rq {
				id:				pack(AXIID_BitmapRead),
				addr: 			cur_request_addr & ~3, //Read the 4 bytes aligned address.
				burst_length: 	0, //1 beat; Note: When increasing, also check that clear_beats_pending[0] won't overflow. 
				burst_size: 	bitsToBurstSize(32), //4 bytes
				burst_type: 	INCR,
				lock: 			NORMAL,
				cache: 			NORMAL_NON_CACHEABLE_BUFFERABLE,
				prot: 			UNPRIV_SECURE_DATA,
				qos: 			0,
				region: 		0,
				user: 			0
			};
		endrule
		//If the read request is forwarded to the bus, no longer try to enqueue readAddrReq.
		rule update_on_enq_raddr_req(!clearing && cur_update_state[0] == UpdateRead && reading_addr);
			cur_request_raddr_set <= True;
		endrule
		//When the read result arrives, store the data and move on to UpdateWrite.
		rule update_on_read_result(!clearing && cur_update_state[0] == UpdateRead);
			cur_request_readdata <= unpack((readResult.data >> (8*(cur_request_addr & 3)))[7:0]);
			cur_update_state[0] <= UpdateWrite;
		endrule
		
		//-- Bitmap UpdateWrite --
		
		//Sets up a write address request for bitmap updating.
		//-> Prepares data for possible bitmap_waddr_ifc.get call.
		(* mutually_exclusive = "update_write_addr, clear_on_enq_waddr_req" *)
		(* mutually_exclusive = "update_write_addr, clear_write_addr" *)
		(* mutually_exclusive = "update_write_addr, clear_write_data" *)
		rule update_write_addr(!clearing && cur_update_state[0] == UpdateWrite && !cur_request_waddr_set[0]);
			writeAddrReq <= AXI4_Write_Rq_Addr {
				id:				pack(AXIID_BitmapWrite),
				addr: 			cur_request_addr & ~3, //Write the 4 bytes aligned address.
				burst_length: 	0, //1 beat; Note: When increasing, also check that clear_beats_pending[0] won't overflow. 
				burst_size: 	bitsToBurstSize(32), //4 bytes
				burst_type: 	INCR,
				lock: 			NORMAL,
				cache: 			NORMAL_NON_CACHEABLE_BUFFERABLE,
				prot: 			UNPRIV_SECURE_DATA,
				qos: 			0,
				region: 		0,
				user: 			0
			};
		endrule
		//If the write addr request is forwarded to the bus, start the write data request.
		(* mutually_exclusive = "update_on_enq_waddr_req, clear_on_enq_waddr_req" *)
		(* mutually_exclusive = "update_on_enq_waddr_req, clear_write_addr" *)
		(* mutually_exclusive = "update_on_enq_waddr_req, clear_write_data" *)
		rule update_on_enq_waddr_req(!clearing && cur_update_state[0] == UpdateWrite && writing_addr);
			cur_request_waddr_set[0] <= True;
			write_bursts_pending_confirm[0] <= write_bursts_pending_confirm[0] + 1;
		endrule
		//Sets up a write data request for a bitmap entry update.
		//-> Prepares data for possible bitmap_wdata_ifc.get call.
		(* mutually_exclusive = "update_write_data, clear_on_enq_waddr_req" *)
		(* mutually_exclusive = "update_write_data, clear_write_addr" *)
		(* mutually_exclusive = "update_write_data, clear_write_data" *)
		rule update_write_data(!clearing && cur_update_state[0] == UpdateWrite && cur_request_waddr_set[1]);
			Bit#(2) misalignment = truncate(cur_request_addr & 3);
			
			//Replicate the counter across all the data bytes in the request.
			//-> Reduces the logic overhead compared to zeroing the unchanged bytes.
			Bit#(8) counter_updated = pack((cur_request_readdata == 255) ? 255 : (cur_request_readdata + 1));
			Vector#(TDiv#(data_width,8), Bit#(8)) counter_repl_vec = replicate(counter_updated);
			function Bit#(data_width) replfunc(Bit#(8) elem, Bit#(data_width) seed);
				return {seed[valueOf(data_width)-9:0], elem};
			endfunction
			Bit#(data_width) counter_repl = foldr(replfunc, '0, counter_repl_vec);
			
			writeDataReq <= T_AxiWriteDataID {
				id:  pack(AXIID_BitmapWrite),
				req: AXI4_Write_Rq_Data {
					data: counter_repl, //New counter. For simplicity, put it in each data byte.
					strb: Bit#(TDiv#(data_width, 8))'(zeroExtend(1'b1)) << misalignment, //Decode misalignment to get the byte mask.
					last: True,
					user: 0
				}
			};
		endrule
		//If the write data request is forwarded to the bus, set the update state to Idle
		// (and allow a new bitmap update to start immediately, as cur_update_state is a CReg).
		rule update_on_enq_wdata_req(!clearing && cur_update_state[0] == UpdateWrite && writing_data);
			cur_update_state[0] <= UpdateIdle;
			cur_request_waddr_set[1] <= False;
		endrule
		
		
		//General rule that updates the 'pending write bursts' counter.
		// Used for both clearing and updating.
		rule on_write_complete(write_complete);
			if (write_bursts_pending_confirm[1] == 0)
				feature_log($format("write_bursts_pending_confirm underflow!"), L_ERROR);
			write_bursts_pending_confirm[1] <= write_bursts_pending_confirm[1] - 1;
		endrule
		
		//---- Methods ----
		method Bool isValidSize(UInt#(32) _bitmap_size);
			//Size must be >= data_width/8 and a power of two.
			//<=> Exactly one bit ((1<<bit#) >= data_width/8) in _bitmap_size is set.
			Bool bitmapSizeError = False;
			Bool bitmapSizeBitFound = False;
			for (Integer i = 0; i < 32; i=i+1) begin
				if (pack(_bitmap_size)[i] == 1) begin
					bitmapSizeError = bitmapSizeBitFound || (1<<Bit#(32)'(fromInteger(i))) < Bit#(32)'(fromInteger(valueOf(data_width)/8));
					bitmapSizeBitFound = True;
				end
			end
			return !bitmapSizeError;
		endmethod
		method Bool getStallSignal();
			return stall;
		endmethod
		
		method Bool isFlushed();
			return initialized && cur_update_state[0] == UpdateIdle
				&& !bitmapUpdateReqFifo.notEmpty
				&& (write_bursts_pending_confirm[0] == 0);
		endmethod
		method Action clear(Bit#(32) _bitmapAddr_begin, UInt#(32) _bitmap_size);
			clearReq <= True;
			bitmapAddr_begin <= _bitmapAddr_begin;
			bitmapAddr_end <= pack(UInt#(32)'(unpack(_bitmapAddr_begin)) + _bitmap_size);
			bitmap_size <= _bitmap_size;
		endmethod
		method Action flush();
			//Do nothing, current implementation already writes back to memory immediately.
		endmethod
		
		
		
		//---- Interfaces ----
		interface Put fuzzBitmapReq_ifc;
			method Action put(T_Fuzzer_BitmapUpdateReq req);
				feature_log($format("Bitmap got req: ") + fshow(req), L_Bitmap);
				bitmapUpdateReqFifo.enq(req);
				incr_bitmapUpdateReq_count <= True;
			endmethod
		endinterface
		
		interface Get bitmap_waddr_ifc;
			method ActionValue#(AXI4_Write_Rq_Addr#(addr_width, id_width, user_width)) get();
				feature_log($format("Bitmap sends AXI4_Write_Rq_Addr: ") + fshow(writeAddrReq), L_Bitmap);
				writing_addr.send();
				return writeAddrReq;
			endmethod
		endinterface
		interface GetForID bitmap_wdata_ifc;
			method Bool for_id(Bit#(id_width) _id) = (writeDataReq.id == _id);
			method ActionValue#(AXI4_Write_Rq_Data#(data_width, user_width)) get();
				feature_log($format("Bitmap sends AXI4_Write_Rq_Data: ") + fshow(writeDataReq), L_Bitmap);
				writing_data.send();
				return writeDataReq.req;
			endmethod
		endinterface
		interface PutIfID bitmap_wrs_ifc;
			method Bool accepts_id(Bit#(id_width) _id) = (_id == pack(AXIID_BitmapWrite));
			method Action put(AXI4_Write_Rs#(id_width, user_width) resp);
				if (resp.resp == SLVERR || resp.resp == DECERR)
					feature_log($format("Bitmap AXI4_Write_Rs error: ") + fshow(resp), L_ERROR);
				else
					feature_log($format("Bitmap gets AXI4_Write_Rs: ") + fshow(resp), L_Bitmap);
				write_complete.send();
			endmethod
		endinterface
		interface Get bitmap_raddr_ifc;
			method ActionValue#(AXI4_Read_Rq#(addr_width, id_width, user_width)) get();
				feature_log($format("Bitmap sends AXI4_Read_Rq: ") + fshow(readAddrReq), L_Bitmap);
				reading_addr.send();
				return readAddrReq;
			endmethod
		endinterface
		interface PutIfID bitmap_rdata_ifc;
			method Bool accepts_id(Bit#(id_width) _id) = (_id == pack(AXIID_BitmapRead));
			method Action put(AXI4_Read_Rs#(data_width, id_width, user_width) rdata);
				if (rdata.resp == SLVERR || rdata.resp == DECERR)
					feature_log($format("Bitmap AXI4_Read_Rs error: ") + fshow(rdata), L_ERROR);
				feature_log($format("Bitmap gets AXI4_Read_Rs: ") + fshow(rdata), L_Bitmap);
				//Behave as if no bus errors happen (to simplify hardware).
				readResult <= rdata;
			endmethod
		endinterface
	endmodule
endpackage
