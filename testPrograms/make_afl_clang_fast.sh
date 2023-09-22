#!/bin/bash
RISCV_CC=afl-clang-fast RISCV_CXX=afl-clang-fast++ RISCV_OBJCOPY=objcopy RISCV_OBJDUMP=objdump BUILD_NATIVE=1 BUILD_PERSISTENT=1 make $1 -j24
