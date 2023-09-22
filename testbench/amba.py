# Copyright (c) 2014 Potential Ventures Ltd
# Copyright (c) 2022 Embedded Systems and Applications Group, TU Darmstadt
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Potential Ventures Ltd,
#       SolarFlare Communications Inc nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL POTENTIAL VENTURES LTD BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

"""Drivers for Advanced Microcontroller Bus Architecture."""

import cocotb
from cocotb.triggers import RisingEdge, ReadOnly, Lock
from cocotb_bus.drivers import BusDriver
from cocotb.binary import BinaryValue

import array


class AXIProtocolError(Exception):
    pass


axi4_lite_signals = [
    "AWVALID", "AWADDR", "AWREADY",        # Write address channel
    "WVALID", "WREADY", "WDATA", "WSTRB",  # Write data channel
    "BVALID", "BREADY", "BRESP",           # Write response channel
    "ARVALID", "ARADDR", "ARREADY",        # Read address channel
    "RVALID", "RREADY", "RRESP", "RDATA"  # Read data channel
]

axi4_additional_signals = [
    "WLAST",
    "RLAST",
    "ARSIZE",
    "AWSIZE",
    "ARBURST",
    "AWBURST",
    "ARLEN",
    "AWLEN",
    "ARLOCK",
    "AWLOCK",
    "ARCACHE",
    "AWCACHE",
    "ARPROT",
    "AWPROT"
]

axi4_id_signals = [
    "ARID",
    "RID",
    "AWID",
    "BID"
]

class AXI4LiteMaster(BusDriver):
    """AXI4-Lite Master.

    TODO: Kill all pending transactions if reset is asserted.
    """

    def __init__(self, entity, name, clock, signals=None, **kwargs):
        self._signals = axi4_lite_signals if signals is None else signals
        BusDriver.__init__(self, entity, name, clock, **kwargs)
        # Drive some sensible defaults (setimmediatevalue to avoid x asserts)
        self.bus.AWVALID.setimmediatevalue(0)
        self.bus.WVALID.setimmediatevalue(0)
        self.bus.ARVALID.setimmediatevalue(0)
        self.bus.BREADY.setimmediatevalue(1)
        self.bus.RREADY.setimmediatevalue(1)

        # Mutex for each channel that we master to prevent contention
        self.write_address_busy = Lock("%s_wabusy" % name)
        self.read_address_busy = Lock("%s_rabusy" % name)
        self.write_data_busy = Lock("%s_wbusy" % name)

    @cocotb.coroutine
    async def _send_write_address(self, address, delay=0):
        """
        Send the write address, with optional delay (in clocks)
        """
        await self.write_address_busy.acquire()
        for cycle in range(delay):
            await RisingEdge(self.clock)

        self.bus.AWADDR.value = address
        self.bus.AWVALID.value = 1

        while True:
            await ReadOnly()
            if self.bus.AWREADY.value:
                break
            await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.bus.AWVALID.value = 0
        self.write_address_busy.release()

    @cocotb.coroutine
    async def _send_write_data(self, data, delay=0, byte_enable=0xF):
        """Send the write address, with optional delay (in clocks)."""
        await self.write_data_busy.acquire()
        for cycle in range(delay):
            await RisingEdge(self.clock)

        self.bus.WDATA.value = data
        self.bus.WVALID.value = 1
        self.bus.WSTRB.value = byte_enable

        while True:
            await ReadOnly()
            if self.bus.WREADY.value:
                break
            await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.bus.WVALID.value = 0
        self.write_data_busy.release()

    @cocotb.coroutine
    async def write(
        self, address: int, value: int, byte_enable: int = 0xf,
        address_latency: int = 0, data_latency: int = 0, sync: bool = True
    ) -> BinaryValue:
        """Write a value to an address.

        Args:
            address: The address to write to.
            value: The data value to write.
            byte_enable: Which bytes in value to actually write.
                Default is to write all bytes.
            address_latency: Delay before setting the address (in clock cycles).
                Default is no delay.
            data_latency: Delay before setting the data value (in clock cycles).
                Default is no delay.
            sync: Wait for rising edge on clock initially.
                Defaults to True.

        Returns:
            The write response value.

        Raises:
            AXIProtocolError: If write response from AXI is not ``OKAY``.
        """
        if sync:
            await RisingEdge(self.clock)

        c_addr = cocotb.fork(self._send_write_address(address,
                                                      delay=address_latency))
        c_data = cocotb.fork(self._send_write_data(value,
                                                   byte_enable=byte_enable,
                                                   delay=data_latency))

        if c_addr:
            await c_addr.join()
        if c_data:
            await c_data.join()

        # Wait for the response
        while True:
            await ReadOnly()
            if self.bus.BVALID.value and self.bus.BREADY.value:
                result = self.bus.BRESP.value
                break
            await RisingEdge(self.clock)

        await RisingEdge(self.clock)

        if int(result):
            raise AXIProtocolError("Write to address 0x%08x failed with BRESP: %d"
                                   % (address, int(result)))

        return result

    @cocotb.coroutine
    async def read(self, address: int, sync: bool = True) -> BinaryValue:
        """Read from an address.

        Args:
            address: The address to read from.
            sync: Wait for rising edge on clock initially.
                Defaults to True.

        Returns:
            The read data value.

        Raises:
            AXIProtocolError: If read response from AXI is not ``OKAY``.
        """
        if sync:
            await RisingEdge(self.clock)

        self.bus.ARADDR.value = address
        self.bus.ARVALID.value = 1

        while True:
            await ReadOnly()
            if self.bus.ARREADY.value:
                break
            await RisingEdge(self.clock)

        await RisingEdge(self.clock)
        self.bus.ARVALID.value = 0

        while True:
            await ReadOnly()
            if self.bus.RVALID.value and self.bus.RREADY.value:
                data = self.bus.RDATA.value
                result = self.bus.RRESP.value
                break
            await RisingEdge(self.clock)

        if int(result):
            raise AXIProtocolError("Read address 0x%08x failed with RRESP: %d" %
                                   (address, int(result)))

        return data

    def __len__(self):
        return 2**len(self.bus.ARADDR)

def check_for_id(entity, name):
    bus_signals = [sig[0] for sig in entity._sub_handles.items() if name in sig[0]]
    arid = [arid for arid in bus_signals if "arid" in arid.lower()]
    return len(arid) > 0

class AXI4Master(AXI4LiteMaster):
    """
    Full AXI4 Master
    """

    def __init__(self, entity, name, clock):
        signals = axi4_lite_signals + axi4_additional_signals
        self._has_id = check_for_id(entity, name)
        if self._has_id:
            signals += axi4_id_signals
        AXI4LiteMaster.__init__(self, entity, name, clock, signals=signals)

        # Drive some sensible defaults (setimmediatevalue to avoid x asserts)
        self.bus.WLAST.setimmediatevalue(1)
        self.bus.ARSIZE.setimmediatevalue(0b010) # 4 bytes
        self.bus.AWSIZE.setimmediatevalue(0b010) # 4 bytes
        self.bus.ARBURST.setimmediatevalue(1) # INCR
        self.bus.AWBURST.setimmediatevalue(1) # INCR
        self.bus.ARLEN.setimmediatevalue(0)
        self.bus.AWLEN.setimmediatevalue(0)
        self.bus.ARLOCK.setimmediatevalue(0)
        self.bus.AWLOCK.setimmediatevalue(0)
        self.bus.ARCACHE.setimmediatevalue(0)
        self.bus.AWCACHE.setimmediatevalue(0)
        self.bus.ARPROT.setimmediatevalue(0)
        self.bus.AWPROT.setimmediatevalue(0)
        if self._has_id:
            self.bus.ARID.setimmediatevalue(0)
            self.bus.AWID.setimmediatevalue(0)

class AXI4Slave(BusDriver):
    '''
    AXI4 Slave

    Monitors an internal memory and handles read and write requests.
    '''
    

    # Not currently supported by this driver
    _optional_signals = [
        "WLAST",   "WSTRB",
        "RCOUNT",  "WCOUNT",  "RACOUNT", "WACOUNT",
        "ARLOCK",  "AWLOCK",  "ARCACHE", "AWCACHE",
        "ARQOS",   "AWQOS",   "WID"
    ]

    def __init__(self, entity, name, clock, memory, callback=None, event=None,
                 big_endian=False, artificial_stall=False, **kwargs):
        self._signals = axi4_lite_signals + axi4_additional_signals
        self._has_id = check_for_id(entity, name)
        if self._has_id:
            self._signals += axi4_id_signals
        BusDriver.__init__(self, entity, name, clock, **kwargs)
        self.clock = clock

        self.callback = callback

        self.big_endian = big_endian
        self.artificial_stall = artificial_stall
        self.bus.ARREADY.setimmediatevalue(1)
        self.bus.RVALID.setimmediatevalue(0)
        self.bus.RLAST.setimmediatevalue(0)
        self.bus.AWREADY.setimmediatevalue(0)
        self.bus.BVALID.setimmediatevalue(0)
        self.bus.BRESP.setimmediatevalue(0)
        self.bus.RRESP.setimmediatevalue(0)
        if self._has_id:
            self.bus.BID.setimmediatevalue(0)

        self._memory = memory
        self._ar_requests = []
        self._aw_requests = []
        self._w_requests = []
        

        self.write_address_busy = Lock("%s_wabusy" % name)
        self.read_address_busy = Lock("%s_rabusy" % name)
        self.write_data_busy = Lock("%s_wbusy" % name)

        cocotb.fork(self._read_addr())
        cocotb.fork(self._read_data())
        cocotb.fork(self._write_addr())
        cocotb.fork(self._write_data())
        cocotb.fork(self._write_process())

    def _size_to_bytes_in_beat(self, AxSIZE):
        if AxSIZE < 7:
            return 2 ** AxSIZE
        return None
    
    @cocotb.coroutine
    async def _write_process(self):
        clock_re = RisingEdge(self.clock)
        self.bus.BVALID.value = 0
        
        while True:
            while True:
                if len(self._w_requests) > 0:
                    break
                await clock_re
            
            await ReadOnly()
            
            _st, _end, word, wstrb, wlast, aw_request = self._w_requests[0]
            _awaddr, _awlen, _awsize, _awburst, _awprot, _awid = aw_request
            self._w_requests = self._w_requests[1:]
            
            await clock_re
            if self.artificial_stall:
                # Artificial delay
                for i in range(28): #25
                    await clock_re
            
            for i in range(len(wstrb)):
                if wstrb[i] == 0:
                    word[i] = self._memory[_st+i]
            self._memory[_st:_end] = word
            
            if wlast:
                self.bus.BVALID.value = 1
                if self._has_id:
                    self.bus.BID.value = _awid
                while True:
                    await ReadOnly()
                    if self.bus.BREADY.value:
                        break
                    await clock_re
                await clock_re
                self.bus.BVALID.value = 0
            
            
    
    @cocotb.coroutine
    async def _write_data(self):
        clock_re = RisingEdge(self.clock)
        self.bus.WREADY.value = 0

        while True:
            while True:
                await clock_re
                self.bus.WREADY.value = 0 if (len(self._aw_requests) == 0 or len(self._w_requests) >= 8) else 1
                await ReadOnly()
                if self.bus.WREADY.value and self.bus.WVALID.value:
                    break

            _awaddr, _awlen, _awsize, _awburst, _awprot, _awid = self._aw_requests[0]
            
            await ReadOnly()
            word = self.bus.WDATA.value
            word.big_endian = self.big_endian
            word = array.array('B', word.buff)
            wlast = self.bus.WLAST.value
            wstrb = self.bus.WSTRB.value
            wstrb.big_endian = self.big_endian
            
            bytes_in_beat = self._size_to_bytes_in_beat(_awsize)
            _st = _awaddr  # start
            _end = _awaddr + bytes_in_beat  # end
            
            self._w_requests.append((_st, _end, word, wstrb, wlast, self._aw_requests[0]))
            if wlast:
                self._aw_requests = self._aw_requests[1:]
            else:
                if _awlen == 0:
                    raise AXIProtocolError("Write to address 0x%08x: Expected wlast (burst end)" % (_awaddr))
                self._aw_requests[0] = (_awaddr + bytes_in_beat, _awlen - 1, _awsize, _awburst, _awprot, _awid)
            
            

    @cocotb.coroutine
    async def _write_addr(self):
        self.bus.AWREADY.value = 0
        clock_re = RisingEdge(self.clock)

        while True:
            while True:
                await clock_re
                self.bus.AWREADY.value = 0 if (len(self._aw_requests) > 4) else 1
                await ReadOnly()
                if self.bus.AWREADY.value and self.bus.AWVALID.value:
                    break

            _awaddr = int(self.bus.AWADDR)
            _awlen = int(self.bus.AWLEN)
            _awsize = int(self.bus.AWSIZE)
            _awburst = int(self.bus.AWBURST)
            _awprot = int(self.bus.AWPROT)

            if self._has_id:
                _awid = int(self.bus.AWID)
            else:
                _awid = 0

            burst_length = _awlen + 1
            bytes_in_beat = self._size_to_bytes_in_beat(_awsize)
            
            self._aw_requests.append((_awaddr, _awlen, _awsize, _awburst, _awprot, _awid))
            if self.callback:
                self.callback(1, _awaddr)

            if __debug__ or True:
                print(
                    "AWADDR  %d\n" % _awaddr +
                    "AWLEN   %d\n" % _awlen +
                    "AWSIZE  %d\n" % _awsize +
                    "AWBURST %d\n" % _awburst +
                    "AWPROT %d\n" % _awprot +
                    "AWID %d\n" % _awid +
                    "BURST_LENGTH %d\n" % burst_length +
                    "Bytes in beat %d\n" % bytes_in_beat)

    @cocotb.coroutine
    async def _read_data(self):
        clock_re = RisingEdge(self.clock)
        self.bus.RVALID.value = 0

        while True:
            while True:
                await clock_re
                if len(self._ar_requests) > 0:
                    break

            _araddr, _arlen, _arsize, _arburst, _arprot, _arid = self._ar_requests[0]
            self._ar_requests = self._ar_requests[1:]
            
            burst_length = _arlen + 1
            bytes_in_beat = self._size_to_bytes_in_beat(_arsize)
            word = BinaryValue(n_bits=bytes_in_beat*8, bigEndian=self.big_endian)

            burst_count = burst_length

            await clock_re
            if self.artificial_stall:
                # Artificial delay
                for i in range(40): #12
                    await clock_re

            while True:
                self.bus.RVALID.value = 1
                _burst_diff = burst_length - burst_count
                _st = _araddr + (_burst_diff * bytes_in_beat)
                _end = _araddr + ((_burst_diff + 1) * bytes_in_beat)
                word.buff = bytes(self._memory[_st:_end])
                self.bus.RDATA.value = word
                if self._has_id:
                    self.bus.RID.value = _arid
                if burst_count == 1:
                    self.bus.RLAST.value = 1

                while True:
                    await ReadOnly()
                    if self.bus.RREADY.value:
                        break
                    await clock_re
                await clock_re
                self.bus.RVALID.value = 0
                
                burst_count -= 1
                self.bus.RLAST.value = 0
                if burst_count == 0:
                    break
                
            
    @cocotb.coroutine
    async def _read_addr(self):
        self.bus.ARREADY.value = 0
        clock_re = RisingEdge(self.clock)

        while True:
            while True:
                await clock_re
                self.bus.ARREADY.value = 0 if (len(self._ar_requests) > 4) else 1
                await ReadOnly()
                if self.bus.ARREADY.value and self.bus.ARVALID.value:
                    break
            
            _araddr = int(self.bus.ARADDR)
            _arlen = int(self.bus.ARLEN)
            _arsize = int(self.bus.ARSIZE)
            _arburst = int(self.bus.ARBURST)
            _arprot = int(self.bus.ARPROT)
            if self._has_id:
                _arid = int(self.bus.ARID)
            else:
                _arid = 0
            
            self._ar_requests.append((_araddr, _arlen, _arsize, _arburst, _arprot, _arid))

            if __debug__ or True: 
                burst_length = _arlen + 1
                bytes_in_beat = self._size_to_bytes_in_beat(_arsize)
                print(
                    "ARADDR  %d\n" % _araddr +
                    "ARLEN   %d\n" % _arlen +
                    "ARSIZE  %d\n" % _arsize +
                    "ARBURST %d\n" % _arburst +
                    "ARPROT %d\n" % _arprot +
                    "BURST_LENGTH %d\n" % burst_length +
                    "Bytes in beat %d\n" % bytes_in_beat)
            
