#!/bin/bash
# Fuzzer CI simulation script.
#  Runs a given set of test programs through the LibAFL fuzzer host
#   and checks the behaviour against the test specification.
#  Fuzzer host, fuzzer script and simulation stdout/stderr are saved to host/fuzzer_host_libafl/ci_logs.
# Env parameters:
#  RISCVCORE - name of the RISC-V core, to name logs accordingly.
#  TESTS - Set of tests to run, separated by space.
#          Entry format: <test name in testPrograms>:(crash|nocrash):<bin file name>:timeout<timeout duration>
#           crash indicates that the fuzzer host must find a program crash within one fuzzer main loop iteration,
#           nocrash indicates that no crashes must occur.
#           The timeout duration is passed to the timeout command, see `timeout --help`.
#          Example entry: en_mix1:nocrash:good.bin:timeout10m
# Example:
#  TESTS="en_write_fault:crash:main.bin:timeout3m en_read_fault:crash:main.bin:timeout3m" RISCVCORE=cva5 ./ci_run_sim.sh

pushd host/fuzzer_host_libafl
FAILURE=0
# Run all tests in the TESTS variable.
for TESTDESC in ${TESTS}; do 
  # Retrieve the test name and config: Regex match in $TESTDESC.
  [[ ${TESTDESC} =~ ([a-zA-Z0-9_\-]+):(nocrash|crash):([a-zA-Z0-9_.\-]+):timeout([a-z0-9]+) ]]
  TEST=${BASH_REMATCH[1]}
  [ ${BASH_REMATCH[2]} = "nocrash" ] && NOCRASH=1 || :
  [ ${BASH_REMATCH[2]} = "crash" ] && NOCRASH=0 || :
  TESTBIN=${BASH_REMATCH[3]}
  TIMEOUTSPEC=${BASH_REMATCH[4]}
  
  echo "Running test ${TEST} for core ${RISCVCORE}"
  
  mkdir -p ci_logs
  rm -rf crashes
  
  PIPERESULTS=( )
  ASSERTFAIL_CRASHES=0
  #Use && and || so the script does not fail and assigns PIPERESULTS even if the host or grep fails (without using set +e).
  
  # Run a single iteration of the fuzzer loop.
  # Command also fails if all of the corpus files make the program crash.
  timeout ${TIMEOUTSPEC} ./target/debug/fuzzer_host_libafl ../../testPrograms/${TEST}/bin/${TESTBIN} ../../testPrograms/${TEST}/corpus \
      --numiter 1 --bitmapsize 64 \
      sim --simlogfile ci_logs/simlog_${TEST}_${RISCVCORE}.log ../../testbench/tapasco-pe-tb \
      2>&1 | tee ci_logs/fuzzlog_${TEST}_${RISCVCORE}.log | grep "Test Failed\|Dynamic assertion failed" \
  && PIPERESULTS=( "${PIPESTATUS[@]}" ) || PIPERESULTS=( "${PIPESTATUS[@]}" )
  # Test if any crashes were found.
  # (also counts crashes during initial corpus evaluation)
  # -> Each test is expected to have a crash case the first loop iteration can find.
  # NUMCRASHFILES: Number of files in the crashes folder.
  
  if [ ${PIPERESULTS[0]} -eq 124 ]; then
    echo "Error: Testcase timed out.";
  fi
  
  NUMCRASHFILES=$(ls crashes | wc -l)
  if [ ${NOCRASH} -eq 1 ] && [ ${NUMCRASHFILES} -gt 0 ]; then
    echo "Error: Program crashes were found but not expected.";
    ASSERTFAIL_CRASHES=1
  fi
  if [ ${NOCRASH} -eq 0 ] && [ ${NUMCRASHFILES} -eq 0 ]; then
    echo "Error: Expected program crashes, but none were found.";
    ASSERTFAIL_CRASHES=1
  fi
  # Rename the crashes and simulation transcript to output in the artifacts.
  mv crashes ci_logs/crashes_${RISCVCORE}_${TEST} || :
  mv ../../testbench/tapasco-pe-tb/transcript ci_logs/transcript_${RISCVCORE}_${TEST}.log || :
  
  #If an error happens during preparation, the make command fails.
  #However, if an error happens inside the actual test, the make command does not return an error status.
  #The grep for "Test Failed" is a workaround to detect test errors.
  if [ ${PIPERESULTS[0]} -eq 0 ] && [ ${PIPERESULTS[2]} -eq 1 ] && \
    [ ${ASSERTFAIL_CRASHES} -eq 0 ]; then
    # PIPERESULTS[0]: Fuzzer exit code (should be success, i.e. 0).
    # PIPERESULTS[2]: Grep exit code (should be failure 1 if it does not find "Test Failed").
    echo "Success : Test ${TEST} for core ${RISCVCORE}"
  else
    FAILURE=1
    echo "Failure : Test ${TEST} for core ${RISCVCORE}"
  fi
done
#Make sure FAILURE is still set to 0. Using exit or return with $FAILURE might also work instead.
echo $FAILURE | grep 0 > /dev/null
popd
exit $FAILURE
