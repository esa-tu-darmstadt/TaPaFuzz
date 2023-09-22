#!/bin/python3

import sys
import os
import parse
import re

HISTOGRAM_MINTIME=1656519231.0: #Minimal system file timestamp to include in the histogram. Adjust to ignore the input corpus files that AFL++ copies into the output corpus folder)

# Parses one or several simulation logs/transcripts and extracts the taken CF edges.

def print_usage():
    print("Unexpected number of arguments.", file=sys.stderr)
    print("Usage: transcript_analyze.py {<simulation transcript path>} [-nocount] [-edges|-edges-count] [-histogram] {-skiprange [addr_from:08x][,<addr_to:08x>]} {-metalog <file>} [-metalog-auto]", file=sys.stderr)
    print(" -nocount: Do not print the number of unique edges.", file=sys.stderr)
    print(" -edges: Print all edges (one per line).", file=sys.stderr)
    print(" -edges-count: Print all edges (one per line) and their number of occurrences.", file=sys.stderr)
    print(" -histogram: Print the number of unique edges for each eventful minute w.r.t. the input file dates reported in the transcript.", file=sys.stderr)
    print(" -skiprange: Specify ranges [from,to) with edge target/source addresses to not register as edges.", file=sys.stderr)
    print(" -metalog: Specify file with only \"# File modify date \" lines (workaround for wrong transcript log line ordering)", file=sys.stderr)
    print(" -metalog-auto: Like -metalog, but for each transcript file, use <transcript>_meta as meta file", file=sys.stderr) 

if len(sys.argv) < 2:
    print("Unexpected number of arguments.", file=sys.stderr)
    print_usage()
    exit(1)
    

print_cfedges = False
print_cfedges_count = False
print_cfcount = True
print_histogram = False

transcript_paths = []
metafile_paths = []
metafile_paths_auto = False
skipranges = []
branches_exclude = { #Set to exclude particular edges.
    #(pc_from, pc_to): True
}

pc_entry = 0x40000000 # For detection of input file evaluation start

i_arg = 0
while i_arg + 1 < len(sys.argv):
    i_arg += 1
    arg = sys.argv[i_arg]
    if arg.startswith('-'):
        if arg == "-nocount":
            print_cfcount = False
        elif arg == "-edges":
            print_cfedges = True
        elif arg == "-edges-count":
            print_cfedges = True
            print_cfedges_count = True
        elif arg == "-histogram":
            print_histogram = True
        elif arg == "-skiprange":
            i_arg += 1
            if i_arg >= len(sys.argv):
                print("skiprange: Unexpected number of arguments.", file=sys.stderr)
                exit(1)
            regex_range = re.compile("([0-9A-F]{8,8})?(?:,([0-9A-F]{8,8}))?", re.IGNORECASE)
            match_obj = regex_range.fullmatch(sys.argv[i_arg])
            if match_obj is None:
                print("skiprange: Range argument format wrong. Expected : [8 digit hex][,<8 digit hex>]", file=sys.stderr)
                exit(1)
            range_from,range_to = match_obj.group(1,2)
            if range_from is None and range_to is None:
                print("skiprange: Range argument invalid.", file=sys.stderr)
                exit(1)
            range_from = 0x00000000 if (range_from is None) else parse.parse("{:08x}", range_from)[0]
            range_to   = 0xffffffff if (range_to   is None) else parse.parse("{:08x}", range_to)[0]
            skipranges.append((range_from,range_to))
        elif arg == "-metalog":
            i_arg += 1
            if i_arg >= len(sys.argv):
                print("metalog: Unexpected number of arguments.", file=sys.stderr)
                exit(1)
            metafile_paths.append(sys.argv[i_arg])
        elif arg == "-metalog-auto":
            metafile_paths_auto = True
        else:
            print("Unexpected argument '%s'" % arg, file=sys.stderr)
            print_usage()
            exit(1)
        continue
    
    if os.path.isdir(arg):
        transcript_paths += [path for path in [os.path.join(arg,fname) for fname in sorted(os.listdir(arg)) if not fname.endswith("_meta")] if os.path.isfile(path)]
    else:
        transcript_paths.append(arg)

if len(transcript_paths) == 0:
    print("No files provided.")
    print_usage()
    exit(1)
if metafile_paths_auto:
    metafile_paths = [(path + "_meta") for path in transcript_paths]

def addr_in_skipranges(addr):
    for skip_from,skip_to in skipranges:
        if addr >= skip_from and addr < skip_to:
            return True
    return False

class ParseException(Exception):
    pass

def is_edge_instruction(instr):
    instr_opcode = instr & 0x7F
    instr_funct3 = (instr >> 12) & 7
    return ((instr_opcode == 0b1100111 and instr_funct3 == 0b000) or #JALR
            (instr_opcode == 0b1101111) or #J, JAL
            (instr_opcode == 0b1100011)) #BRANCH

def edges_add_line_fuzzer(line, edges_out):
    if not line.startswith("# Fuzzer PE: L_CORE_CF: Forwarding CF "):
        return
    if line.endswith("\n"):
        line = line[:-1]
    parse_res = parse.parse("# Fuzzer PE: L_CORE_CF: Forwarding CF curr_pc {:08x} curr_instr {:08x} next_pc {:08x}", line)
    if parse_res == None:
        raise ParseException("Unexpected CF log line: %s" % line)
    cur_pc, cur_instr, next_pc = parse_res
    
    if addr_in_skipranges(cur_pc) or addr_in_skipranges(next_pc):
        return
    
    if is_edge_instruction(cur_instr):
       key = (cur_pc, next_pc)
       edges_out[key] = edges_out.get(key, 0) + 1
def edges_add_line_wrapper(line, edges_out, state):
    if not line.startswith("# val 1, addr "):
        return
    if line.endswith("\n"):
        line = line[:-1]
    #Example: "# val 1, addr 40000000, insn 00801197"
    parse_res = parse.parse("# val 1, addr {:08x}, insn {:08x}", line)
    if parse_res == None:
        raise ParseException("Unexpected CF log line: %s" % line)
    next_pc, next_instr = parse_res
    if len(state) == 0:
        state.append((next_pc, next_instr))
        return
    cur_pc = state[0][0]
    cur_instr = state[0][1]
    state[0] = (next_pc, next_instr)
    
    if addr_in_skipranges(cur_pc) or addr_in_skipranges(next_pc) or next_pc == pc_entry or ((cur_pc, next_pc) in branches_exclude):
        return
    
    if is_edge_instruction(cur_instr):
       key = (cur_pc, next_pc)
       edges_out[key] = edges_out.get(key, 0) + 1

edges = {}

lasttime = None
starttime = None

def histogram_print_line(starttime, lasttime, edgecount):
    timediff_minutes = int(lasttime - starttime) // 60 + 1
    print("{}, {}".format(timediff_minutes, edgecount))
    #timediff_hours = timediff_minutes // 60
    #timediff_minutes -= 60 * timediff_hours
    #print("{}, {}, {}".format(timediff_hours, timediff_minutes, edgecount))
def update_histogram(line):
    global lasttime
    global starttime
    if not print_histogram:
        return
    curtime = float(line.split(":")[1][1:])
    if curtime >= HISTOGRAM_MINTIME:
        if starttime is None:
            starttime = curtime
        if lasttime is not None and int(lasttime - starttime) // 60 != int(curtime - starttime) // 60:
            # Print entry for past minute.
            histogram_print_line(starttime, lasttime, len(edges))
        lasttime = curtime
if print_histogram:
    #print("time_h,time_m, edgecount")
    print("time_m, edgecount")

edges_state = []
i_metafile = 0
metafile = None

debug_transcript_is_new = False
debug_num_transcript_evals = 0
debug_num_metafile_evals = 0

# Reads the "File modify date" line, if a new evaluation going by the transcript.
#  The line is either used directly by the transcript, or through metafile.
def newfile_modify_date_line(transcript_line):
    global i_metafile
    global metafile
    global debug_num_transcript_evals
    global debug_num_metafile_evals
    global debug_transcript_is_new
    if len(metafile_paths) > 0:
        if transcript_line.startswith("# val 1, addr {:08x}".format(pc_entry)):
            dateline = ""
            while True:
                dateline = metafile.readline() if (metafile is not None) else ""
                if len(dateline) != 0:
                    break
                if metafile is not None:
                    metafile.close()
                    metafile = None
                if i_metafile >= len(metafile_paths):
                    print("# Error: metafile EOF early", file=sys.stderr)
                    return None
                if debug_num_metafile_evals != debug_num_transcript_evals:
                    print("# Error: Transcript file/Meta file mismatch: {} evals in single transcript, {} evals in single metafile" % (debug_num_transcript_evals, debug_num_metafile_evals), file=sys.stderr)
                debug_num_metafile_evals = 0
                if debug_transcript_is_new:
                    debug_num_transcript_evals = 0
                    debug_transcript_is_new = False
                print("# Opening metafile " + metafile_paths[i_metafile], file=sys.stderr)
                metafile = open(metafile_paths[i_metafile], 'r')
                i_metafile += 1
            debug_num_metafile_evals += 1
            debug_num_transcript_evals += 1
            if not dateline.startswith("# File modify date (seconds since epoch): "):
                print("# Error: metafile line invalid", file=sys.stderr)
                return None
            return dateline
    elif transcript_line.startswith("# File modify date (seconds since epoch): "):
        return transcript_line
    return None

for transcript_path in transcript_paths:
    with open(transcript_path, 'r') as transcript_file:
        print("# Opening transcript " + transcript_path, file=sys.stderr)
        debug_transcript_is_new = True
        for line in transcript_file:
            newfile_line = newfile_modify_date_line(line)
            if newfile_line is not None:
                update_histogram(newfile_line)
                #edges_state = []
            #edges_add_line_fuzzer(line, edges)
            edges_add_line_wrapper(line, edges, edges_state)
        print("# Processed corpus files: {} transcript, {} meta".format(debug_num_transcript_evals, debug_num_metafile_evals), file=sys.stderr)
if metafile:
    if len(metafile.readline()) > 0 or i_metafile < len(metafile_paths):
        print("# Error: transcripts and metafiles do not match up (uncorrelated runs detected in metafiles)", file=sys.stderr)
    metafile.close()

if print_histogram:
    if lasttime is not None:
        histogram_print_line(starttime, lasttime, len(edges))
    print("\n")
if print_cfcount:
    print("Found {} unique CF edges.".format(len(edges)))
if print_cfedges:
    if print_cfedges_count:
        print("pc_from, pc_to, num")
        for key in edges:
            print("{:08x}, {:08x}, {:d}".format(key[0], key[1], edges[key]))
    else:
        print("pc_from, pc_to")
        for key in edges:
            print("{:08x}, {:08x}".format(key[0], key[1]))
