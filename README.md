# TaPaFuzz Fuzzing Accelerator

TaPaFuzz is a fuzzing accelerator that controls and monitors a RISC-V processor (CVA5), along with a [LibAFL](https://github.com/AFLplusplus/LibAFL) host program.  

## Dependencies
- Vivado 2021.2 (if not in PATH, `source <vivado_dir>/settings.sh`)
- [Bluespec compiler](https://github.com/B-Lang-org/bsc) (tested with commit `e76ca2114a4d625dada768304d2da39be76126bf`)
- [tapasco-riscv](https://github.com/esa-tu-darmstadt/tapasco-riscv) for included IP, no installation steps required
- For building test programs: RISC-V GNU toolchain (referenced in [testPrograms/base.mk](testPrograms/base.mk) and `testPrograms/mn_*/Makefile`)
- For simulation: Questa 2020.4 (`questasim/bin` in PATH)
- To build and deploy on a supported FPGA: [TaPaSCo 2022.1](https://github.com/esa-tu-darmstadt/tapasco/tree/d7768b3986d1852b08cb70506dff911f600705e6)
- Rust compiler with Cargo (e.g. 1.60.0), for instance via distribution packages or [rustup](https://rustup.rs/).

Set the `TAPASCO_RV_DIR` environment variable to point to the cloned tapasco-riscv directory.

## Hardware simulation

In the [testbench/tapasco-pe-tb]([testbench/tapasco-pe-tb]) directory, follow the setup steps described in [testbench/tapasco-pe-tb/README.md]([testbench/tapasco-pe-tb/README.md]). We recommend creating and sourcing a virtual python environment, since the locally installed cocotb-bus package will be modified.

Build the TaPaSCo PE IP only (CVA5 core):  
`make cva5_pe`

Run the simulation:  
```bash
# Prepare the simulation. Also includes the cva5_pe and binaries steps.
make cva5_sim
# Run the actual simulation.
cd testbench/tapasco-pe-tb
TEST=en_mix1 TESTIN=../../testPrograms/en_mix1/corpus/in1.txt make
```

## LibAFL fuzzer (simulation)

Setup the simulation as described above, including the `make cva5_sim` command.  

Build the Fuzzer host:  
```bash
cd host/fuzzer_host_libafl
# Debug mode should suffice, simulation is the bottleneck under most circumstances.
cargo build
```

Run the Fuzzer (only 1 thread supported for simulation):  
` ./host/fuzzer_host_libafl/target/debug/fuzzer_host_libafl ./testPrograms/en_mix1/bin/good.bin ./testPrograms/en_mix1/corpus sim ./testbench/tapasco-pe-tb `

## LibAFL fuzzer (TaPaSCo)

Build the PE:  
```bash
make cva5_pe
```

Alternatively, create the PE with BRAM as program memory by substituting `cva5_pe` with `cva5_bram_pe` in the make command above and in the following commands.

Create a TaPaSCo project and build the bitstream:  
```bash
mkdir tapasco_workdir && cd tapasco_workdir
<tapasco_dir>/tapasco-init.sh
source tapasco-setup.sh
tapasco-build-toolflow
# Import the fuzzer PE (as PE ID 10), VC709 FPGA platform.
tapasco import ../fuzzer_ip/esa.informatik.tu-darmstadt.de_fuzzer_cva5_pe_fuzzer_1.0.zip as 10 -p vc709
# Build a VC709 bitstream with 4 instances of the PE and a clock speed of 100 MHz (can be altered freely).
tapasco compose [cva5_pe_fuzzer x 4] @ 100 MHz -p vc709
```

Build the test programs and fuzzer host:  
```bash
PE_BRAM=<0 or 1> make binaries
cd host/fuzzer_host_libafl
# Release mode can improve performance significantly.
cargo build --release
```

Load the bitstream:  
```bash
cd tapasco_workdir
source tapasco-setup.sh
# Example bitstream location, may vary.
sudo tapasco-load-bitstream compose/axi4mm/vc709/cva5_pe_fuzzer/004/100.0/axi4mm-vc709--cva5_pe_fuzzer_4--100.0.bit
```

Run the Fuzzer with N threads:  
` ./host/fuzzer_host_libafl/target/release/fuzzer_host_libafl ./testPrograms/en_mix1/bin/good.bin ./testPrograms/en_mix1/corpus --numthreads N tapasco `

## Build test programs for AFL++
The test program Makefile supports builds for AFL++'s persistent and forkserver modes, either native or RISC-V Linux.

A sample build script wrapper for AFL++ native persistent is located at [testPrograms/make_afl_clang_fast.sh](testPrograms/make_afl_clang_fast.sh).
Can be run with `./make_afl_clang_fast.sh build_mn_arduinojson` for instance. Make sure to run `make clean` in the testPrograms and mn_* directories.

For qemu builds, export RISCV_CC, RISCV_CXX, RISCV_OBJCOPY and RISCV_OBJDUMP environment vars for the target architecture
 and run `make BUILD_FORKSERVER=1 build_mn_arduinojson` in the testPrograms directory.

# License
The contents of this repository are provided under the MIT license (see the file [LICENSE](LICENSE)), except where noted otherwise.

Exceptions are indicated by separate `LICENSE` files in subdirectories (that apply to the entire subdirectory), separate license files named to match individual files, or comments in individual files. Additionally, files and directories downloaded as a submodule or by build scripts (e.g. by `testPrograms/mn_*/Makefile`) come with separate license terms.

# Literature
Florian Meisel, David Volz, Christoph Spang, Dat Tran, and Andreas Koch. 2023. **TaPaFuzz - An FPGA-Accelerated Framework for RISC-V IoT Graybox Fuzzing.** In Workshop on Design and Architectures for Signal and Image Processing, DASIP ’23. Springer International Publishing.

