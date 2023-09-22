import FuzzerTypes::*;

// -------------------------------------------- DETECT BRANCHES -----------------------------------------------
function Bool isConditionalBranch(Bit#(32) inst);
    Bit#(7) opcode = inst[6:0];
    return (opcode==7'b1100011);
endfunction

// ------------- DETECT LOOPS (branch eventually to negative relative address) ------------------------
function Bool isLoopStartBranch(Bit#(32) inst);
    return ( isConditionalBranch(inst) && (inst[31:31]==1) );
endfunction



// ------------------------------------------ DETECT DIRECT JAL -----------------------------
function Bool isJAL(Bit#(32) inst);
    Bit#(1) rd      = inst[7];
    Bit#(7) opcode  = inst[6:0];
    return (opcode == 7'b_1101111 && rd!=0);
endfunction

// ------------------------------------------ DETECT DIRECT JUMP -----------------------------
function Bool isJ(Bit#(32) inst);
    Bit#(1) rd      = inst[7];
    Bit#(7) opcode  = inst[6:0];
    return (opcode == 7'b_1101111 && rd==0);
endfunction

// --------------------------- DETECT JALR (and its derivations) ----------------------------------------------------------
/**
* Check if the currently started instruction is a JALR instruction. (Ret is replaced by JALR. inst 31..20 is imm 11:0, 31 is sign extension, inst 14..12 is func3)
*/		
function Bool isJALR(Bit#(32) inst);
    Bit#(7) opcode = inst[6:0];
    Bit#(3) funct3 = inst[14:12];
    return ((opcode == 7'b_1100111) && (funct3 == 3'b_000));
endfunction

