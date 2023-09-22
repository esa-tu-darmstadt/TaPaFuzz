package Logging;
    import OInt::*;
    import Vector::*;
    import BuildVector::*;
    Bool verbose = True;
    typedef enum {
        L_WARNING,
        L_ERROR,
        L_IRQ,              // Relevant for cmp_logs.py
        L_CF_STACKS,
        L_CF_StateAndFSM,   // Basic information
        L_CF_Flows,         // Branch, JR, call return flow
        L_CF_LoopLimits,
        L_CF_TableAccesses, // Access and content of configuration memories
        L_CF_MemWr,         // Write configuration memories
		L_Bitmap,
        L_CORE_MemWr,
        L_CORE_CF,
        L_CORE_DF,          // Relevant for cmp_logs.py
        L_CORE_STALLS,
		L_CORE_EXC
    } LogType deriving (Bits, Eq, FShow);

    // Con
    typedef 13 N_LOG_TYPES;
    
    // Returns a one-hot-encoded LogType Bitvector
    function Bit#(N_LOG_TYPES) one_hot_log(LogType level);
        return pack(toOInt(pack(level))); 
    endfunction

    function Action feature_log(Fmt message, LogType feature);
        action
            let v_logconfig = vec(`FUZZER_LOG_TYPES);
            let logconfig_1hot = map(one_hot_log, v_logconfig);
            Bit#(N_LOG_TYPES) logconfig = fold(\| , logconfig_1hot); // now we got a bit vector encoding the state of logconfig
            if( (unpack(pack(toOInt(pack(feature)))) & logconfig) >0 || verbose) begin
                $display($format("Fuzzer PE: ")+fshow(feature)+$format(": ")+ fshow(message));
            end
        endaction
    endfunction
endpackage