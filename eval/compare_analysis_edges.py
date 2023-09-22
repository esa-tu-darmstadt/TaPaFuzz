#!/bin/python3

import sys
import os
import parse

# Compares the edges of two simulation transcript analysis files generated with either "-edges" or "-edges-count".

def print_usage():
    print("Usage: compare_analysis_edges.py <analysis file A> <analysis file B>", file=sys.stderr)


if len(sys.argv) < 3:
    print("Unexpected number of arguments.", file=sys.stderr)
    print_usage()
    exit(1)

class ParseException(Exception):
    pass

def parse_analysis_file(analysis_file):
    expect_edges = False
    edges = {}
    for line in analysis_file:
        if line.startswith("pc_from, pc_to"):
            expect_edges = True
            continue
        if expect_edges and len(line) == 0:
            break
        if expect_edges:
            parse_res = parse.parse("{:08x}, {:08x}{}", line + " ")
            if parse_res == None:
                raise ParseException("Unexpected CF log line: %s" % line)
            cur_pc, next_pc, _ = parse_res
            edges[(cur_pc,next_pc)] = True
    return edges
    
with open(sys.argv[1], 'r') as analysis_file_A:
    edges_A = parse_analysis_file(analysis_file_A)
with open(sys.argv[2], 'r') as analysis_file_B:
    edges_B = parse_analysis_file(analysis_file_B)

print("A: {} edges, B: {} edges".format(len(edges_A), len(edges_B)))

def get_new_entries(edges_new, edges_old):
    return [edge for edge in edges_new if (not edge in edges_old)]

edges_added = get_new_entries(edges_B, edges_A)
edges_removed = get_new_entries(edges_A, edges_B)

def print_edge(prefix, edge):
    print("{} {:08x}, {:08x}".format(prefix, edge[0], edge[1]))

for edge_added in edges_added:
    print_edge("+", edge_added)
for edge_removed in edges_removed:
    print_edge("-", edge_removed)

if len(edges_added) == 0 and len(edges_removed) == 9:
    print("No difference detected")
