package FuzzerTypes;
import Vector::*;
import GetPut::*;
import AXI4_Types::*;


// // ----------------- RAS ACTION ---------------
typedef enum{
	None_Br,
	None_J,
	Pop,
	Push,
	PopThenPush
} T_RAS_Action deriving(Eq, Bits);

typedef struct {
	Bit#(id_width) id;
	AXI4_Write_Rq_Data#(data_width, user_width) req;
} T_AxiWriteDataID#(numeric type data_width, numeric type id_width, numeric type user_width) deriving (Bits, FShow);
typedef enum {
	AXIID_BitmapRead = 6'd0,
	AXIID_ExtRead = 6'd1,  //Pass through write from slave.
	MAX = 6'b111111
} T_FuzzerAxiIDRead deriving(Bits, Eq, FShow);
typedef enum {
	AXIID_BitmapWrite = 6'd0,
	AXIID_ExtWrite = 6'd1,  //Pass through write from slave.
	MAX = 6'b111111
} T_FuzzerAxiIDWrite deriving(Bits, Eq, FShow);

// // Core State2 (updated every cycle) - exported at the end of the fetch stage
typedef struct {
	Bit#(32) 	curr_pc; // use complete bitwidth here for now
	Bit#(32) 	next_pc;
	Bit#(32) 	curr_instr;
} T_RiscCoreState2 deriving (Bits, FShow);

typedef struct {
	Bit#(5) 	cause;
	Bit#(32) 	tval;
	Bit#(32) 	epc;
} T_RiscCoreException deriving (Bits, FShow);

typedef struct {
	Bool 		started;
	Bool 		reset;
} T_FuzzerToCfState deriving (Bits);

typedef struct {
	Bit#(32)  hash;
} T_Fuzzer_BitmapUpdateReq deriving (Bits, FShow);

endpackage