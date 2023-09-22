# Modified tapasco-pe-tb test_riscv.py script.
import struct
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.result import TestFailure, TestSuccess
from cocotb.triggers import Timer, RisingEdge, FallingEdge
from cocotb.binary import BinaryValue
# ~ from cocotb.drivers.amba import AXI4LiteMaster#, AXI4Slave
# ~ from amba import AXI4SlaveNew
from amba import AXI4LiteMaster, AXI4Master, AXI4Slave
# ~ from amba import AXI4Slave
# ~ from cocotb.regression import TestFactory

from multiprocessing.shared_memory import SharedMemory

CLK_PERIOD = 1000

def mem_callback(rw, addr):
    if rw:
        print ("Write to addr {}".format(addr))
    else:
        print ("Read at addr {}".format(addr))

def mem_event():
    return

def find_clk(dut):
    dut._discover_all()
    for name in dut._sub_handles:
        if 'clk' in name.lower() and not 'axi' in name.lower():
            return dut._sub_handles[name]
    raise Exception

def find_rstn(dut):
    dut._discover_all()
    for name in dut._sub_handles:
        if ('reset_n' in name.lower() or 'resetn' in name.lower() or 'rst_n' in name.lower() or 'rstn' in name.lower()) and not 'axi' in name.lower():
            return dut._sub_handles[name]
    raise Exception

def find_axi_s_ctrl(dut):
    dut._discover_all()
    for name in dut._sub_handles:
        if 'arvalid' in name.lower() and 's_axi' in name.lower() and not 'bram' in name.lower():
            return '_'.join(name.split('_')[0:-1])

def find_axi_s_bram(dut):
    dut._discover_all()
    for name in dut._sub_handles:
        if 'arvalid' in name.lower() and 's_axi' in name.lower() and 'bram' in name.lower():
            return '_'.join(name.split('_')[0:-1])

def find_axi_m(dut):
    dut._discover_all()
    for name in dut._sub_handles:
        if 'arvalid' in name.lower() and 'm_axi' in name.lower():
            return '_'.join(name.split('_')[0:-1])
    return None

@cocotb.coroutine
def clock_print(clk):
    while True:
        yield RisingEdge(clk)
        print ("-")

@cocotb.coroutine
def load_binary(f, axim_bram, inaddr, outaddr):
    f.seek(inaddr, os.SEEK_SET)
    while True:
        word = f.read(4)
        if word == b'' or len(word) < 4:
            break
        #print (outaddr)
        #print (struct.unpack('BBBB', word))
        word = struct.unpack('I', word)[0]
        yield axim_bram.write(outaddr, word)
        outaddr = outaddr + 4
    return outaddr

@cocotb.coroutine
def load_bram(data, axim_bram, outaddr):
    for i in range(0, len(data), 4):
        if (len(data)-i < 4):
            word = bytearray(data[i:len(data)]) + bytearray(4 - (len(data)-i))
        else:
            word = data[i:i+4]
        
        word = struct.unpack('I', word)[0]
        yield axim_bram.write(outaddr, word)
        outaddr = outaddr + 4
    return outaddr

INVFLAG_ICACHE = (1 << 0)
INVFLAG_BP = (1 << 1)
INVFLAG_DCACHE = (1 << 2)
@cocotb.coroutine
def startwait_pe(dut, clk, axim, arglen, argptr, bitmap_size, ignore_min, timeout_cycles, is_dram, is_tapascoriscv):
    # start PE
    bla = yield(axim.read(0x00))
    print(bla)
    yield axim.write(0x04, 1) # GIER
    yield axim.write(0x08, 1) # IER
    
    # ~ yield axim.write(0x20, 0) # arg 0: Job ID (not required here).
    yield axim.write(0x30, arglen) # arg 1: Length of argument data.
    yield axim.write(0x40, argptr) # arg 2: Argument data pointer.
    yield axim.write(0x50, bitmap_size) # arg 3: Bitmap size.
    if not is_tapascoriscv:
        # ~ yield axim.write(0x60, 1) # arg 4 (ret): Exception information
        print("timeout low: {}, high: {}".format(timeout_cycles & 0xFFFFFFFF, (timeout_cycles >> 32) & 0xFFFFFFFF))
        yield axim.write(0x70, timeout_cycles & 0xFFFFFFFF) # arg 5: Timeout.
        yield axim.write(0x74, (timeout_cycles >> 32) & 0xFFFFFFFF)
        yield axim.write(0xA0, 0) # arg 8: DRAM section ID (currently upper 12 bits of address) for program memory.
        yield axim.write(0xC0, ignore_min) # arg 10: Address range min, at/above which bitmap hardware should ignore CF.
        yield axim.write(0xD0, 0) # arg 11: For Debug - 1 disables bitmap->core stalls (result bitmap will be unreliable)
    yield axim.write(0x00, 1) # start

    yield RisingEdge(dut.interrupt)
    if is_dram:
        # Invalidate the data cache only, as instructions are read-only and remain unchanged between runs,
        #  whereas the data memory has to be reset to its original state plus possibly with new inputs.
        # Note: If the simulator were to support program swaps mid-run in the future,
        #       INVFLAG_ICACHE would also have to be set.
        yield axim.write(0xB0, INVFLAG_DCACHE) # Clear dcache only
    counterLo = yield axim.read(0x70 if is_tapascoriscv else 0x90) # counterLo
    counterHi = yield axim.read(0x74 if is_tapascoriscv else 0x94) # counterHi
    counter = (counterLo.integer | (counterHi.integer << 32))
    print("int received, counter {}".format(counter))
    yield Timer(CLK_PERIOD * 10)
    yield axim.write(0x0C, 1) # irq_ack
    retLo = BinaryValue(0) if is_tapascoriscv else (yield axim.read(0x10)) # retLo
    arg4Lo = BinaryValue(0) if is_tapascoriscv else (yield axim.read(0x60)) # arg4Lo
    arg4Hi = BinaryValue(0) if is_tapascoriscv else (yield axim.read(0x64)) # arg4Hi
    return (retLo, arg4Lo, arg4Hi, counter)
    
def print_result(retLo: BinaryValue, arg4Lo: BinaryValue, arg4Hi: BinaryValue, counter, file=sys.stdout):
    if retLo.integer & (1<<7) != 0:
        print("PE result: Timeout", file=file)
    if retLo.integer & (1<<0) != 0:
        print("PE result: Exception (cause %u, epc 0x%08X, tval 0x%08X)" 
            % ((retLo.integer >> 1) & 31, arg4Lo.integer, arg4Hi.integer), file=file)
    if retLo.integer & (1<<6) != 0:
        print("PE result: Error - Invalid bitmap size", file=file)
    if retLo.integer == 0:
        print("PE result: Success ({} cycles)".format(counter), file=file)

@cocotb.coroutine
def read_bitmap(axim_bram, bitmap_loc, bitmap_size):
    result_bmp = bytearray(bitmap_size)
    for i_bitmap in range(0,bitmap_size,4):
        word_bits = yield axim_bram.read(bitmap_loc + i_bitmap)
        #word_bits is a cocotb BinaryValue
        result_bmp[i_bitmap + 3] = word_bits[0:7]
        result_bmp[i_bitmap + 2] = word_bits[8:15]
        result_bmp[i_bitmap + 1] = word_bits[16:23]
        result_bmp[i_bitmap + 0] = word_bits[24:31]
    return result_bmp

def print_bitmap(bmp, file=sys.stdout):
    bmp_message = "result bitmap: "
    for i_bitmap in range(0,len(bmp),4):
        if (i_bitmap % 16 == 0):
            bmp_message += ("\n%02x%02x:" % ((i_bitmap & 0xFF00) >> 8, i_bitmap & 0xFF))
        bmp_message += " %02x %02x %02x %02x" % tuple(bmp[i_bitmap:i_bitmap+4]);
    print(bmp_message, file=file)

class TargetBinaryException(Exception):
    pass
class InvalidSizeException(Exception):
    pass
class RunInconsistencyException(Exception):
    pass

@cocotb.test()
def run_test(dut):
    clk = find_clk(dut)
    cocotb.fork(Clock(clk, CLK_PERIOD).start())

    axim = AXI4LiteMaster(dut, find_axi_s_ctrl(dut), clk)
    axim_bram = AXI4Master(dut, find_axi_s_bram(dut), clk) # is actually a full slave!
    
    #HARDCODED: Memory layout
    cva5_ram_base =      0x40000000
    cva5_ram_base_tapascoriscv = 0x00000000
    instmem_dram_range = 0x00800000
    datamem_dram_offs =   0x00800000
    datamem_dram_range = 0x007F8000 #excl 0x8000 for stack
    dram_total_size =    0x01000000
    
    instmem_bram_range =    0x00010000
    datamem_bram_offs_virt = 0x00800000
    datamem_bram_offs_phys = 0x00010000
    datamem_bram_range =    0x0000F000 #excl 0x1000 for stack
    bitmap_loc = 0x20000
    bitmap_size_max = 0x2000
    
    is_tapascoriscv = False
    
    dut_axim = find_axi_m(dut) if not ("TAPASCORISCV_PURE" in os.environ) else None
    
    if dut_axim is None:
        # BRAM mode
        dram = bytearray()
        use_axim_bram = True
        is_dram = False
        if "TAPASCORISCV_PURE" in os.environ:
            cva5_ram_base = cva5_ram_base_tapascoriscv
            is_tapascoriscv = True
            print("Using tapasco-riscv preset")
        
        instmem_range = instmem_bram_range
        datamem_offs_virt = datamem_bram_offs_virt
        datamem_offs_phys = datamem_bram_offs_phys
        datamem_range = datamem_bram_range
    else:
        dram = bytearray(dram_total_size)
        axis = AXI4Slave(dut, dut_axim, clk, dram, callback=mem_callback, event=mem_event, big_endian=False, artificial_stall=False)
        use_axim_bram = True if ("HBM_MODE" in os.environ) else False
        is_dram = True
        if "HBM_MODE" in os.environ:
            bitmap_loc = 0x01000000
        
        instmem_range = instmem_dram_range
        datamem_offs_virt = datamem_dram_offs
        datamem_offs_phys = datamem_dram_offs
        datamem_range = datamem_dram_range
    
    #reset
    rst_n = find_rstn(dut)
    rst_n <= 0
    yield Timer(CLK_PERIOD * 10)
    rst_n <= 1
    
    if "TEST" in os.environ:
        test = os.environ["TEST"]
        test_path = "../../testPrograms/"+test+"/"
        test_binaries = os.listdir(test_path+"bin")
        ignore_min = int(os.environ["TEST_IGNOREMIN"], 16) if ("TEST_IGNOREMIN" in os.environ) else 0xffffffff
    
        bitmap_size = 0x40

        # Iterate over all binaries of this testcase
        for fname in test_binaries:
            yield Timer(CLK_PERIOD * 100)
            yield axim.write(0xB0, INVFLAG_ICACHE | INVFLAG_BP) #Invalidate instruction cache and branch predictor

            # load firmware
            f = open(test_path+"bin/"+fname, "rb")
            fw_data = bytearray(f.read())
            if len(fw_data) > datamem_offs_virt + datamem_range:
                raise TargetBinaryException("Binary too large (beyond stack location)")
            if len(fw_data) > instmem_range and any((x!=0 for x in fw_data[instmem_range:datamem_offs_virt])):
                # Important for BRAM mode, which has the same base addresses for imem,dmem as DRAM mode but smaller ranges.
                raise TargetBinaryException("Binary instructions too large")
            if use_axim_bram:
                yield load_bram(fw_data[:instmem_range], axim_bram, 0x00000)
                yield load_bram(fw_data[datamem_offs_virt:], axim_bram, datamem_offs_phys)
            else:
                dram[0:len(fw_data)] = fw_data
            localmem_addr = len(fw_data)
            #localmem_addr = yield load_binary(f, axim_bram, 0, 0x0000)
            f.close()
            
            # load program arguments, and sort the access order by file modification date
            inputend_loc = datamem_offs_virt + datamem_range
            indataset_date = []
            indataset_order = []
            indatasets = []
            indataset_lastbmp = []
            indataset_numsuccess = []
            def read_infile(fname):
                with open(fname, "rb") as f:
                    indata = bytearray(f.read())
                    if ((inputend_loc - len(indata)) & ~4) <= localmem_addr:
                        raise TargetBinaryException("Binary too large (no room for input data)")
                    indataset_date.append(os.path.getmtime(fname))
                    indatasets.append(indata)
                    indataset_lastbmp.append(bytearray())
                    indataset_numsuccess.append(0)
            if "TESTIN" in os.environ:
                for fname in os.environ["TESTIN"].split(':'):
                    if os.path.isdir(fname):
                        for fname_sub in os.listdir(fname):
                            fname_sub_full = os.path.join(fname, fname_sub)
                            if os.path.isfile(fname_sub_full) and not fname_sub.startswith("."):
                                read_infile(fname_sub_full)
                    else:
                        read_infile(fname)
                indataset_order = list(range(len(indatasets)))
                indataset_order.sort(key=lambda i: indataset_date[i])
                
            timeout_cycles = 0
            if "TESTTIMEOUT" in os.environ:
                timeout_cycles = int(os.environ["TESTTIMEOUT"])
            n_runs = len(indataset_order)
            if n_runs < 1:
                n_runs = 1
            if "NUMRUNS" in os.environ:
                n_runs = int(os.environ["NUMRUNS"])
            
            
            print ("firmware loaded")
            #cocotb.fork(clock_print(clk))
            
            for i in range(n_runs):
                if len(fw_data) >= datamem_offs_virt:
                    # Copy the data memory again (previous run may have changed it).
                    if use_axim_bram:
                        yield load_bram(fw_data[datamem_offs_virt:], axim_bram, datamem_offs_phys)
                    else:
                        dram[datamem_offs_phys:datamem_offs_phys+len(fw_data)-datamem_offs_virt] = fw_data[datamem_offs_virt:]
                
                i_dataset = indataset_order[i % len(indatasets)] if (len(indatasets) > 0) else -1
                indata = (indatasets[i_dataset]) if (i_dataset >= 0) else bytearray()
                cur_dmem_input_offs = (datamem_range - len(indata)) & ~4
                cur_input_offs_phys = datamem_offs_phys + cur_dmem_input_offs
                cur_input_pos_virt = cva5_ram_base + datamem_offs_virt + cur_dmem_input_offs
                if use_axim_bram:
                    yield load_bram(indata, axim_bram, cur_input_offs_phys)
                else:
                    dram[cur_input_offs_phys:cur_input_offs_phys+len(indata)] = indata
                print ("Set program input: " + str(indata))
                if i_dataset >= 0:
                    print ("File modify date (seconds since epoch): " + str(indataset_date[i_dataset]))
                
                retLo, arg4Lo, arg4Hi, counter = yield startwait_pe(dut, clk, axim, len(indata), cur_input_pos_virt, bitmap_size, ignore_min, timeout_cycles, is_dram, is_tapascoriscv)
                print_result(retLo, arg4Lo, arg4Hi, counter)
                
                if not is_tapascoriscv:
                    result_bmp = yield read_bitmap(axim_bram, bitmap_loc, bitmap_size)
                    print_bitmap(result_bmp)
                    if i_dataset >= 0 and len(indataset_lastbmp[i_dataset]) > 0 and result_bmp != indataset_lastbmp[i_dataset]:
                        raise RunInconsistencyException("Inconsistent bitmap behaviour detected!")
                    if i_dataset >= 0 and indataset_numsuccess[i_dataset] > 0 and retLo != 0:
                        raise RunInconsistencyException("Previously successful input failed!")
                    if i_dataset >= 0:
                        indataset_lastbmp[i_dataset] = result_bmp
                        if retLo == 0:
                            indataset_numsuccess[i_dataset] += 1
    
    if "FUZZTB_TARGET" in os.environ:
        SimRequestType_SetInput = 0
        SimRequestType_Start = 1
        SimRequestType_CopyBitmap = 2
        SimRequestType_Close = 255
        
        ignore_min = int(os.environ["FUZZTB_IGNOREMIN"], 16) if ("FUZZTB_IGNOREMIN" in os.environ) else 0xffffffff
        
        fuzztb_stdout = sys.stdout
        if "FUZZTB_STDOUT" in os.environ:
            stdout_fd = int(os.environ["FUZZTB_STDOUT"])
            if stdout_fd != -1:
                fuzztb_stdout = os.fdopen(stdout_fd, "a")
        #Assuming that this means that all required FUZZTB env vars are set.
        with open(os.environ["FUZZTB_TARGET"], "rb") as f:
            shmem = SharedMemory(name=os.environ["FUZZTB_SHMEM"], create=False)
            req_pipe_read_fd = int(os.environ["FUZZTB_REQ_PIPE"])
            resp_pipe_write_fd = int(os.environ["FUZZTB_RESP_PIPE"])
            
            yield Timer(CLK_PERIOD * 100)
            
            print ("Loading binary", file=fuzztb_stdout)
            fw_data  = bytearray(f.read())
            if len(fw_data) > datamem_offs_virt + datamem_range:
                raise TargetBinaryException("Binary too large (beyond stack location)")
            if len(fw_data) > instmem_range and any((x!=0 for x in fw_data[instmem_range:datamem_offs_virt])):
                # Important for BRAM mode, which has the same base addresses for imem,dmem as DRAM mode but smaller ranges.
                raise TargetBinaryException("Binary instructions too large")
            if use_axim_bram:
                yield load_bram(fw_data[:instmem_range], axim_bram, 0x00000)
                yield load_bram(fw_data[datamem_offs_virt:], axim_bram, datamem_offs_phys)
            else:
                dram[0:len(fw_data)] = fw_data
            localmem_offs_virt = len(fw_data)
            #localmem_addr = yield load_binary(f, axim_bram, 0, 0x0000)
            
            #16 byte align the input data location
            input_pos_virt = cva5_ram_base + datamem_offs_virt + datamem_range
            input_size = 0
            bitmap_size = 0
            i_run = 0
            
            print ("Simulator ready", file=fuzztb_stdout)
            while True:
                command = os.read(req_pipe_read_fd, 1)
                if len(command) == 0:
                    break
                command = command[0]
                if command == SimRequestType_Close:
                    print ("Closing test_riscv", file=fuzztb_stdout)
                    break
                elif command == SimRequestType_SetInput:
                    # Copy input data to program data memory.
                    # Shared memory: 4 byte size, rest data.
                    size = struct.unpack('I', shmem.buf[:4])[0]
                    
                    cur_dmem_input_offs = (datamem_range - size) & ~4
                    cur_input_offs_phys = datamem_offs_phys + cur_dmem_input_offs
                    if datamem_offs_virt + cur_dmem_input_offs <= localmem_offs_virt:
                        raise InvalidSizeException("Input data too large")
                    
                    print ("Set program input: " + str(bytearray(shmem.buf[4:4+size])), file=fuzztb_stdout)
                    
                    if use_axim_bram:
                        yield load_bram(shmem.buf[4:4+size], axim_bram, cur_input_offs_phys)
                    else:
                        dram[cur_input_offs_phys:cur_input_offs_phys+size] = shmem.buf[4:4+size]
                    
                    input_pos_virt = cva5_ram_base + datamem_offs_virt + cur_dmem_input_offs
                    input_size = size
                    
                    # Respond.
                    os.write(resp_pipe_write_fd, b'\x00')
                elif command == SimRequestType_Start:
                    if len(fw_data) >= datamem_offs_virt:
                        # Copy the data memory again (previous run may have changed it).
                        if use_axim_bram:
                            yield load_bram(fw_data[datamem_offs_virt:], axim_bram, datamem_offs_phys)
                        else:
                            dram[datamem_offs_phys:datamem_offs_phys+len(fw_data)-datamem_offs_virt] = fw_data[datamem_offs_virt:]
                    # print ("Loading data memory", file=fuzztb_stdout)
                    #yield load_binary(f, axim_bram, datamem_loc, datamem_loc)
                    # Start the PE.
                    # Shared memory: 4 byte requested bitmap size.
                    bitmap_size = struct.unpack('I', shmem.buf[:4])[0]
                    if bitmap_size > shmem.size or bitmap_size > bitmap_size_max:
                        raise InvalidSizeException("Bitmap size too large")
                    if bitmap_size < 4 or bin(bitmap_size).count("1") != 1:
                        raise InvalidSizeException("Bitmap size not a power of two of at least 4")
                    timeout_cycles = struct.unpack('Q', shmem.buf[8:16])[0]
                    print ("Starting PE", file=fuzztb_stdout)
                    retLo, arg4Lo, arg4Hi, counter = yield startwait_pe(dut, clk, axim, input_size, input_pos_virt, bitmap_size, ignore_min, timeout_cycles, is_dram, is_tapascoriscv)
                    print_result(retLo, arg4Lo, arg4Hi, counter, file=fuzztb_stdout)
                    # Store result information in shmem.
                    shmem.buf[0:12] = struct.pack('III', retLo, arg4Lo, arg4Hi)
                    shmem.buf[16:24] = struct.pack('Q', counter)
                    # Respond.
                    os.write(resp_pipe_write_fd, b'\x00')
                    i_run = i_run + 1
                elif command == SimRequestType_CopyBitmap:
                    # Copy the bitmap to shared memory.
                    result_bmp = yield read_bitmap(axim_bram, bitmap_loc, bitmap_size)
                    shmem.buf[0:bitmap_size] = result_bmp
                    print_bitmap(result_bmp, file=fuzztb_stdout)
                    # Respond.
                    os.write(resp_pipe_write_fd, b'\x00')
        
    
    if 'GUI' in os.environ and os.environ['GUI'] == '1':
        print("Endless loop to keep GUI alive.")
        while True:
            yield RisingEdge(dut.interrupt)

    dut._log.info("Ok!")

