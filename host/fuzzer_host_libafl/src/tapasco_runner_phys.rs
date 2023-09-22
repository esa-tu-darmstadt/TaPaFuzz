use std::sync::Arc;
use std::io::prelude::*;
use std::io::SeekFrom;
use std::sync::atomic::AtomicBool;
use std::time::Duration;
use snafu::ResultExt;

use async_trait::async_trait;

use tapasco::device::DeviceSize;
use tapasco::device::OffchipMemory;
use tapasco::device::{Device, DeviceAddress, PEParameter};
use tapasco::pe::PE;

use crate::tapasco_host::{TapascoRunStatusFlags, TapascoHostRun, TapascoRunner, TapascoRunError};
use crate::tapasco_host::{TapascoDeviceSnafu, TapascoJobSnafu, TapascoAllocatorSnafu, TapascoDMASnafu, TapascoPESnafu};


//static INSTMEM_DRAM_OFFS : u32 = 0;
static INSTMEM_SIZE : usize = 8*1024*1024;
//static DATAMEM_DRAM_OFFS : u32 = INSTMEM_DRAM_OFFS + INSTMEM_SIZE as u32;
static DATAMEM_SIZE : usize = 8*1024*1024;

static DRAM_REGION_SHIFT : u32 = 32-8;
static DRAM_REGION_SIZE : u32 = 1 << DRAM_REGION_SHIFT;
static DRAM_REGION_MASK : u64 = (!(DRAM_REGION_SIZE - 1)) as u64;
//static PROCESSOR_INSTMEM_BASE : u32 = 0x40000000;
//static PROCESSOR_DATAMEM_BASE : u32 = 0x40800000;

//static BITMAP_SIZE : usize = 0x2000;

static PE_INVFLAG_ICACHE : u32 = 1 << 0;
static PE_INVFLAG_BP : u32 = 1 << 1;
static PE_INVFLAG_DCACHE : u32 = 1 << 2;

#[derive(Copy, Clone)]
pub struct PEMemConfig {
    invalidate_caches: bool,
    instmem_offs_phys: u32,
    instmem_size_phys: usize,
    datamem_offs_phys: u32,
    datamem_size_phys_without_stack: usize,
    datamem_size_phys: usize,
    datamem_addr_virt: u32, //Virtual base location as visible from programs.
    bitmap_via_dram_dma: bool,
    bitmap_bram_addr: u32,
    bitmap_bram_size: u32
}
//DRAM: 16 MiB section; 1 MiB imem, 7 MiB padding, 8 MiB dmem. Assuming 32K stack.
static PEMEMCONFIG_DRAM: PEMemConfig = PEMemConfig {
    invalidate_caches: true,
    instmem_offs_phys: 0, 
    instmem_size_phys: 1*1024*1024,
    datamem_offs_phys: 8*1024*1024,
    datamem_size_phys_without_stack: 8*1024*1024 - 32*1024,
    datamem_size_phys: 8*1024*1024,
    datamem_addr_virt: 0x40800000,
    bitmap_via_dram_dma: false,
    bitmap_bram_addr: 0x20000,
    bitmap_bram_size: 0x2000
};
//HBM: Like DRAM; 16 MiB section; 1 MiB imem, 7 MiB padding, 8 MiB dmem. Assuming 32K stack.
//-> Accessed via PE local memory interface instead.
static PEMEMCONFIG_HBM: PEMemConfig = PEMemConfig {
    invalidate_caches: true,
    instmem_offs_phys: 0, 
    instmem_size_phys: 1*1024*1024,
    datamem_offs_phys: 8*1024*1024,
    datamem_size_phys_without_stack: 8*1024*1024 - 32*1024,
    datamem_size_phys: 8*1024*1024,
    datamem_addr_virt: 0x40800000,
    bitmap_via_dram_dma: false,
    bitmap_bram_addr: 0x01000000,
    bitmap_bram_size: 0x2000
};
//BRAM: 2x64 KiB; 64 
// -> Is configured in core to have the same imem, dmem base addresses as with DRAM.
static PEMEMCONFIG_BRAM: PEMemConfig = PEMemConfig {
    invalidate_caches: false,
    instmem_offs_phys: 0, 
    instmem_size_phys: 64*1024,
    datamem_offs_phys: 64*1024,
    datamem_size_phys_without_stack: 64*1024 - 4*1024,
    datamem_size_phys: 64*1024,
    datamem_addr_virt: 0x40800000,
    bitmap_via_dram_dma: false,
    bitmap_bram_addr: 0x20000,
    bitmap_bram_size: 0x2000
};
//BRAM via DMA ("dram"): 2x64 KiB; 64 
// -> Is configured in core to have the same imem, dmem base addresses as with DRAM.
static PEMEMCONFIG_BRAM_DMA: PEMemConfig = PEMemConfig {
    invalidate_caches: false,
    instmem_offs_phys: 0, 
    instmem_size_phys: 64*1024,
    datamem_offs_phys: 64*1024,
    datamem_size_phys_without_stack: 64*1024 - 4*1024,
    datamem_size_phys: 64*1024,
    datamem_addr_virt: 0x40800000,
    bitmap_via_dram_dma: true,
    bitmap_bram_addr: 0x20000,
    bitmap_bram_size: 0x2000
};
//BRAM: 2x64 KiB
// Variant without fuzzer hardware (standard tapasco-riscv PE)
static PEMEMCONFIG_BRAM_TAPASCORISCV: PEMemConfig = PEMemConfig {
    invalidate_caches: false,
    instmem_offs_phys: 0, 
    instmem_size_phys: 64*1024,
    datamem_offs_phys: 64*1024,
    datamem_size_phys_without_stack: 64*1024 - 4*1024,
    datamem_size_phys: 64*1024,
    datamem_addr_virt: 0x00800000,
    bitmap_via_dram_dma: false,
    bitmap_bram_addr: 0x20000,
    bitmap_bram_size: 0
};

fn read_binary(path: &str) -> Result<(Box<[u8]>, Box<[u8]>), std::io::Error> {
    //Open the given file.
    let mut f = std::fs::File::open(&path)?;

    //Allocate a buffer that corresponds to the program binary in BRAM.
    let mut buffer: Vec<u8> = Vec::new();
    buffer.resize(INSTMEM_SIZE + DATAMEM_SIZE, 0);

    //Determine the file size, don't read past the hardcoded BRAM size.
    let mut file_size = f.seek(SeekFrom::End(0))?;
    f.seek(SeekFrom::Start(0))?;
    file_size = std::cmp::min(file_size, (INSTMEM_SIZE + DATAMEM_SIZE) as u64);

    //Read the file. Note: read(..) does not guarantee that all data is read in one call.
    let mut read_pos: usize = 0;
    while read_pos < file_size as usize {
        match f.read(&mut buffer[read_pos..file_size as usize]) {
            Ok(n) if n == 0 => Err(std::io::Error::new(std::io::ErrorKind::Other, "File end before expected eof"))?,
            Ok(n) => read_pos += n,
            Err(e) => Err(e)?
        };
    }

    //Select the memory ranges actually present in the binary.
    
    let instmem: Box<[u8]> = buffer[0..std::cmp::min(file_size, INSTMEM_SIZE as u64) as usize].into();
    let datamem_size = 
        if file_size <= INSTMEM_SIZE as u64 { 0 }
        else { std::cmp::min(file_size - (INSTMEM_SIZE as u64), DATAMEM_SIZE as u64) as usize };
    let datamem: Box<[u8]> = buffer[INSTMEM_SIZE..INSTMEM_SIZE+datamem_size].into();
    Ok((instmem, datamem))
}

pub struct PEDesc {
    pe: PE,
    memconf: PEMemConfig,
    dram: Option<Arc<OffchipMemory>>,
    dram_allocation: Option<DeviceAddress>,
    instmem_initialized: bool,
    is_regular_tapascoriscv: bool
}
impl PEDesc {
    pub fn new(
        pe: PE, memconf: PEMemConfig, dram: Option<Arc<OffchipMemory>>
    ) -> Self {
        Self {
            pe: pe,
            memconf: memconf,
            dram: dram,
            dram_allocation: None,
            instmem_initialized: false,
            is_regular_tapascoriscv: false
        }
    }
    pub fn new_tapascoriscv(
        pe: PE, memconf: PEMemConfig
    ) -> Self {
        let mut desc = Self::new(pe, memconf, None);
        desc.is_regular_tapascoriscv = true;
        desc
    }
}
impl Drop for PEDesc {
    fn drop(&mut self) {
        if let Some(dram_allocation) = self.dram_allocation {
            self.dram.as_deref().unwrap().allocator().lock().unwrap().free(dram_allocation).unwrap();
            self.dram_allocation = None;
        }
    }
}
///Manages a set of PEs to run fuzzing jobs on.
pub struct TapascoDispatcher {
    idlepe_mutex: async_std::sync::Mutex<Vec<PEDesc>>,
    idlepe_condvar: async_std::sync::Condvar //idlepe_mutex
}
impl TapascoDispatcher {
    pub fn new(
        pes: Vec<PEDesc>
    ) -> Result<Arc<Self>, TapascoRunError> {
        let jobs_idle: Result<Vec<PEDesc>, TapascoRunError> = pes.into_iter().map(|mut pedesc| {
            if let Some(dram) = pedesc.dram.as_deref() {
                //Allocate DRAM according to the memory configuration.
                let mut alloc_size = pedesc.memconf.datamem_offs_phys as DeviceSize + pedesc.memconf.datamem_size_phys as DeviceSize;
                let bitmap_end = pedesc.memconf.bitmap_bram_addr as DeviceSize + pedesc.memconf.bitmap_bram_size as DeviceSize;
                if pedesc.memconf.bitmap_via_dram_dma && bitmap_end > alloc_size {
                    alloc_size = bitmap_end;
                }
                let dram_allocation = dram.allocator().lock()?.allocate(alloc_size, None).context(TapascoAllocatorSnafu)?;
                //For now: Assumes that all allocations are aligned to DRAM_REGION_MASK. 
                //-> Relevant for regular (AU280: DDR4) DRAM variants, since the address space is shared across all PEs.
                if (dram_allocation & !DRAM_REGION_MASK) != 0 {
                    dram.allocator().lock().unwrap().free(dram_allocation).unwrap();
                    return Err(TapascoRunError::DRAMAllocationMisaligned { addr: dram_allocation, alignment_num: alloc_size/1024 });
                }
                pedesc.dram_allocation = Some(dram_allocation);
            }
            Ok(pedesc)
        }).collect();
        let _self = Arc::new(Self { 
            idlepe_mutex: async_std::sync::Mutex::new(jobs_idle?),
            idlepe_condvar: async_std::sync::Condvar::new()
        });
        Ok(_self)
    }
    ///Runs a fuzzing job and returns its result and bitmap.
    /// Performs an async wait if no PE is ready.
    /// 
    /// * `task_id`: An ID to pass on to the PE. Can be set to any value for now.
    /// * `instmem`, `datamem`: Program binary data with addresses and sizes as in the INSTMEM_* and DATAMEM_* constants.
    /// * `input`: Program inputs to store in the free data memory region. If no space is available, an error is returned.
    /// * `bitmap_mem`: Buffer for the control flow bitmap. No other thread or task may lock the mutex.
    /// 
    /// On success, the returned TapascoHostRun carries details on the execution result.
    pub async fn run(&self, task_id: u32, instmem: &[u8], datamem: &[u8], ignore_addresses_min: u32, timeout_cycles: u64,
            input: &[u8], bitmap_mem: Arc<std::sync::Mutex<Box<[u8]>>>
    ) -> Result<TapascoHostRun, TapascoRunError> {
        let bitmap_len: u32;
        // Lock the bitmap_mem to access the length.
        {
            let lock_res = (*bitmap_mem).try_lock();
            assert!(match lock_res {Ok(_) => {true} Err(_) => {false}},
                "Unable to lock mutex that should have been unlocked: {}", lock_res.unwrap_err());
            let bitmap_slice = &mut **lock_res.unwrap();
            bitmap_len = bitmap_slice.len() as u32;
        }
        // Fetch a PE ready for a new task, or wait for one.
        let mut pedesc;
        {
            let mut idlepes_guard = self.idlepe_mutex.lock().await;
            idlepes_guard = self.idlepe_condvar.wait_until(idlepes_guard,
                |idlepes| -> bool {!idlepes.is_empty()}
            ).await;
            pedesc = idlepes_guard.pop().unwrap();
        }
        
        // Since each individual allocation may return an error, use a try-finally equivalent to free all successful allocations.
        // -> The bulk of the dispatch/result retrieval logic is implemented in different functions,
        //    and the result is only passed on to the caller after the 'finally' equivalent code.
        //    Reduces the amount of 'if let Ok(<...>)' or 'match' statements.
        
        let disable_bitmap_transfer = pedesc.memconf.bitmap_bram_size == 0;
        
        let mut result_interm: Result<(), TapascoRunError> = Ok(());
        if !disable_bitmap_transfer && (bitmap_len < 4 || bitmap_len > pedesc.memconf.bitmap_bram_size) {
            result_interm = Err(TapascoRunError::BitmapLen{s:
                format!("Bitmap length is {}, but should be in [4, {}]", bitmap_len, pedesc.memconf.bitmap_bram_size)});
        }
        
        let mut devbitmap_addr_opt: Option<DeviceAddress> = None;
        if let Ok(_) = result_interm {
            // Setup the PE parameters and memory, and start the job.
            result_interm = Self::try_dispatch(task_id, instmem, datamem, input, ignore_addresses_min, 
                bitmap_len, timeout_cycles,
                &mut pedesc, &mut devbitmap_addr_opt
            );
        }
        if let Ok(_) = result_interm {
            // Wait for the job to finish.
            //TODO: Implement an async equivalent for wait_for_completion.
            result_interm = pedesc.pe.wait_for_completion().context(TapascoPESnafu);
        }
        if let Ok(_) = result_interm  {
            // Request data cache invalidation, so a following run does not use stale data.
            result_interm = Self::set_invalidate_flags(&mut pedesc, PE_INVFLAG_DCACHE);
        }
        // Retrieve the execution results, unless a previous step has failed.
        let result_final;
        match result_interm {
            Ok(_) => {
                result_final = Self::try_get_results(&mut pedesc, devbitmap_addr_opt, bitmap_mem, bitmap_len);
            },
            Err(e) => result_final = Err(e),
        };
        // Free all successful allocations, regardless of whether the overall dispatch succeeded or not.
        match pedesc.pe.local_memory().as_ref() {
            Some(localmem) => {
                let mut allocator = localmem.allocator().lock().unwrap();
                if let Some(devbitmap_addr) = devbitmap_addr_opt {allocator.free(devbitmap_addr).unwrap();}
            },
            None => (), //Don't panic if the PE has no local memory.
        };
        // Put the PE back in jobs_idle.
        {
            let mut idlepes_guard = self.idlepe_mutex.lock().await;
            idlepes_guard.push(pedesc);
        }
        // Notify waiting tasks about the idle PE.
        //-> Call notify_one while outside the mutex used for waiting
        //  (is noted as possibly beneficial for C++'s std::condition_variable, not sure if the same applies to this Condvar implementation).
        self.idlepe_condvar.notify_one();

        result_final
    }

    fn set_invalidate_flags(pedesc: &PEDesc, flags: u32) -> Result<(), TapascoRunError> {
        if pedesc.memconf.invalidate_caches {
            let flags_prev = match pedesc.pe.read_arg(9, 4).context(TapascoPESnafu)? {
                PEParameter::Single32(val) => val,
                _ => panic!("Unexpected PE::read_arg result type."),
            };
            pedesc.pe.set_arg(9, PEParameter::Single32(flags | flags_prev)).context(TapascoPESnafu)?;
        }
        Ok(())
    }

    fn try_dispatch(
        task_id: u32, instmem: &[u8], datamem: &[u8], input: &[u8], ignore_addresses_min: u32,
        bitmap_len: u32, timeout_cycles: u64,
        pedesc: &mut PEDesc,
        devbitmap_addr_opt: &mut Option<DeviceAddress>
    ) -> Result<(),TapascoRunError> {
        // Check whether there is enough room for the input data.
        let datamem_len_aligned = (datamem.len() + 15) & !15; //16 byte aligned length.
        let input_len_aligned = (input.len() + 15) & !15;
        if datamem_len_aligned > pedesc.memconf.datamem_size_phys_without_stack {
            return Err(TapascoRunError::ProgramOrDataTooLarge {});
        }
        if !pedesc.instmem_initialized {
            // -> Estimate the length of the used instruction memory.
            //    (Assumption: all suffix zeroes in instmem are unused)
            // Only run this once to save host cycles.
            let instmem_len_nonzero = instmem.iter().rposition(|&v| v != 0).map(|rpos| rpos + 1).unwrap_or(0);
            if instmem_len_nonzero > pedesc.memconf.instmem_size_phys {
                return Err(TapascoRunError::ProgramOrDataTooLarge {});
            }
        }
        if input_len_aligned > pedesc.memconf.datamem_size_phys_without_stack - datamem_len_aligned {
            return Err(TapascoRunError::InputTooLarge {});
        }

        let localmem = pedesc.pe.local_memory().as_ref()
            .ok_or(tapasco::job::Error::NoLocalMemory {  }).context(TapascoJobSnafu)?;
        // Retrieve and 'lock' relevant PE memory addresses.
        if !pedesc.is_regular_tapascoriscv && !pedesc.memconf.bitmap_via_dram_dma {
            let mut allocator = localmem.allocator().lock()?;
            *devbitmap_addr_opt = Some(allocator.allocate_fixed(pedesc.memconf.bitmap_bram_size as u64, pedesc.memconf.bitmap_bram_addr as u64).context(TapascoAllocatorSnafu)?);
        }
        else {
            *devbitmap_addr_opt = None;
        }

        // Compose the initialized program data section and input data.
        // Align the data for DMA (appears to be required?)
        let mut datamem_composed = vec![0; (datamem.len() + 15) & !15];
        datamem_composed[0..datamem.len()].copy_from_slice(datamem);
        let input_data_offs = (pedesc.memconf.datamem_size_phys_without_stack - input.len()) & !15;
        let mut datamem_input_composed = vec![0; pedesc.memconf.datamem_size_phys_without_stack - input_data_offs];
        datamem_input_composed[0..input.len()].copy_from_slice(input);

        // Invalidate data cache for the PE and instruction cache (if needed).
        // Note: If data cache has already been invalidated after the last run, the PE should notice and ignore the request (flag may stick to the next run).
        Self::set_invalidate_flags(pedesc, PE_INVFLAG_DCACHE | (
                if pedesc.instmem_initialized {0}
                else {PE_INVFLAG_ICACHE | PE_INVFLAG_BP}
            )
        )?;
        let instmem_len_copy = std::cmp::min(instmem.len(), pedesc.memconf.instmem_size_phys);
        if let Some(dram) = pedesc.dram.as_deref() {
            // Program memory in DRAM
            // Upload instruction memory (if needed) and data memory, including program inputs.
            if !pedesc.instmem_initialized {
                dram.dma().copy_to(&instmem[..instmem_len_copy], pedesc.dram_allocation.unwrap() + pedesc.memconf.instmem_offs_phys as DeviceSize).context(TapascoDMASnafu)?;
                pedesc.instmem_initialized = true;
            }
            // Upload the data section.
            dram.dma().copy_to(&datamem_composed[..], pedesc.dram_allocation.unwrap() + pedesc.memconf.datamem_offs_phys as DeviceSize).context(TapascoDMASnafu)?;
            // Upload the input data.
            dram.dma().copy_to(
                &datamem_input_composed[..],
                pedesc.dram_allocation.unwrap() + (pedesc.memconf.datamem_offs_phys as usize + input_data_offs) as DeviceSize
            ).context(TapascoDMASnafu)?;
        }
        else {
            // PE local memory (e.g. BRAM)
            // Upload instruction memory (if needed) and data memory, including program inputs.
            if !pedesc.instmem_initialized {
                localmem.dma().copy_to(&instmem[..instmem_len_copy], pedesc.memconf.instmem_offs_phys as DeviceAddress).context(TapascoDMASnafu)?;
                pedesc.instmem_initialized = true;
            }
            // Upload the data section.
            localmem.dma().copy_to(&datamem_composed[..], pedesc.memconf.datamem_offs_phys as DeviceAddress).context(TapascoDMASnafu)?;
            // Upload the input data.
            localmem.dma().copy_to(
                &datamem_input_composed[..],
                (pedesc.memconf.datamem_offs_phys as usize + input_data_offs) as DeviceAddress
            ).context(TapascoDMASnafu)?;
        }
        
        //Arg 0: Job ID
        pedesc.pe.set_arg(0, PEParameter::Single32(task_id)).context(TapascoPESnafu)?;
        //Arg 1: Input length
        pedesc.pe.set_arg(1, PEParameter::Single32(input.len() as u32)).context(TapascoPESnafu)?;
        //Arg 2: Input address
        pedesc.pe.set_arg(2, PEParameter::Single32(pedesc.memconf.datamem_addr_virt + input_data_offs as u32)).context(TapascoPESnafu)?; 
        //Arg 3: Bitmap length
        pedesc.pe.set_arg(3, PEParameter::Single32(bitmap_len)).context(TapascoPESnafu)?; 
        if !pedesc.is_regular_tapascoriscv {
            //(Arg 4: Returns exception information)
            //Arg 5: Timeout (cycles)
            pedesc.pe.set_arg(5, PEParameter::Single64(timeout_cycles)).context(TapascoPESnafu)?; 
            if let Some(_) = pedesc.dram.as_deref() {
                //Arg 8: DRAM region index.
                pedesc.pe.set_arg(8, PEParameter::Single32(((pedesc.dram_allocation.unwrap() & DRAM_REGION_MASK) >> DRAM_REGION_SHIFT) as u32)).context(TapascoPESnafu)?; 
            }
            //Arg 9: Min address to skip
            pedesc.pe.set_arg(10, PEParameter::Single32(ignore_addresses_min));
            //Arg 10: For Debug - 1 disables bitmap->core stalls (result bitmap will be unreliable)
            pedesc.pe.set_arg(11, PEParameter::Single32(0));
        }
        
        //Not sure if required - should make sure the parameters are written out before the start signal.
        std::sync::atomic::fence(std::sync::atomic::Ordering::SeqCst);

        //Start the task.
        pedesc.pe.start().context(TapascoPESnafu)?;
        
        Ok(())
    }

    fn try_get_results(
        pedesc: &mut PEDesc,
        devbitmap_addr: Option<DeviceAddress>,
        bitmap_mem: Arc<std::sync::Mutex<Box<[u8]>>>,
        bitmap_len: u32
    ) -> Result<TapascoHostRun, TapascoRunError> {
        //Return value bits:
        // [0]: Program ended with an exception.
        // [5:1]: If [0] is set: RISC-V exception cause, otherwise: 0.
        // [6]: Failed to run, invalid bitmap size parameter.
        // [63:32] reserved (currently: Overall CF hash, consistency not guaranteed)
        let retval = (pedesc.pe.return_value() & 0xFFFFFFFF) as u32;
        let counter_arg_num = if pedesc.is_regular_tapascoriscv {5} else {7};
        let counter = match pedesc.pe.read_arg(counter_arg_num, 8).context(TapascoPESnafu)? {
            PEParameter::Single64(val) => val,
            _ => panic!("Unexpected PE::read_arg result type."),
        };
        //Create a duration from counter with a cycle time of 1ns (i.e. 1GHz), regardless of actual clock speed.
        let duration = Some(Duration::new(counter >> 32, (counter & 0xFFFFFFFF) as u32));
        
        {
            //Copy the bitmap from the PE local memory.
            // LibAFL also expects a bitmap in case of a program crash.
            let lock_res = (*bitmap_mem).try_lock();
            assert!(match lock_res {Ok(_) => {true} Err(_) => {false}},
                "Unable to lock mutex that should have been unlocked: {}", lock_res.unwrap_err());
            let bitmap_slice = &mut **lock_res.unwrap();
            if pedesc.is_regular_tapascoriscv {
                //Regular tapasco-riscv has no bitmap hardware.
                //Fill with zero (-> LibAFL strategy will detect input as dead end)
                bitmap_slice.fill(0);
            }
            else {
                let localmem = pedesc.pe.local_memory().as_ref()
                    .ok_or(tapasco::job::Error::NoLocalMemory {  }).context(TapascoJobSnafu)?;
                if bitmap_slice.len() != bitmap_len as usize {
                    //Someone else may have locked and changed the slice length in the meantime.
                    return Err(TapascoRunError::BitmapLen { s: "Bitmap slice length changed unexpectedly".to_string() });
                }
                if pedesc.memconf.bitmap_via_dram_dma {
                    let dram = pedesc.dram.as_deref().unwrap();
                    dram.dma().copy_from(pedesc.dram_allocation.unwrap() + pedesc.memconf.bitmap_bram_addr as DeviceSize, bitmap_slice).context(TapascoDMASnafu)?;
                }
                else {
                    localmem.dma().copy_from(devbitmap_addr.unwrap(), bitmap_slice).context(TapascoDMASnafu)?;
                }
            }
        }
        
        if (retval & TapascoRunStatusFlags::PROGRAM_CRASH_FLAG) != 0 {
            let _ecause = (retval & TapascoRunStatusFlags::PROGRAM_CRASH_CAUSE_MASK) >> TapascoRunStatusFlags::PROGRAM_CRASH_CAUSE_SHIFT;
            //Arg 4: exception epc (low 32bits), tval (high 32bits).
            let (_tval, _epc) = match pedesc.pe.read_arg(4, 8).context(TapascoPESnafu)? {
                PEParameter::Single64(arg4_hi_lo) => ((arg4_hi_lo >> 32) as u32, (arg4_hi_lo & 0xFFFFFFFF) as u32),
                _ => panic!("Unexpected PE::read_arg result type."),
            };
            //Output the exception information to console.
            // -> TODO: Save it alongside the corresponding crash input somehow?
            println!("Exception: Cause {}, epc 0x{:08x}, tval 0x{:08x}", _ecause, _epc, _tval);
            return Ok(TapascoHostRun {
                status: TapascoRunStatusFlags::PROGRAM_CRASH_FLAG,
                bitmap: bitmap_mem,
                duration: duration
            });
        }
        else if ((retval >> 6) & 1) == 1 {
            return Err(TapascoRunError::BitmapLen { s: "PE reported an unsupported bitmap length".to_string() });
        }
        else if (retval & !(1 << 7)) == 0 {
            if (retval & (1 << 7)) != 0 {println!("Timeout");}
            // Program completed successfully, or a timeout occured.
            return Ok(TapascoHostRun {
                status: retval, //Success / Timeout
                bitmap: bitmap_mem,
                duration: duration
            });
        }

        Err(TapascoRunError::Unknown { s: format!("Unexpected PE return value: 0x{:08x}", retval) })
    }
}
//Acquires the PEs of the device matching the given name, and calls the provided callback on each of them.
fn acquire_pes<Cb>(dev: &mut Device, pe_name: &str, mut process_pe: Cb) -> Result<(), tapasco::device::Error>
where Cb: FnMut(PE)
{
    // Retrieve the ID of the fuzzer PE in the current device.
    let pe_id = dev.get_pe_id(pe_name)?;
    for _i in 0..dev.num_pes(pe_id) {
        // Retrieve the PE object.
        // Need access to the PE itself (esp. for read_arg).
        let pe = dev.acquire_pe_without_job(pe_id)?;
        process_pe(pe);
    }
    Ok(())
}
//Returns a descriptor object for all supported PEs in the given devices.
pub fn get_pes(devices: &mut [Device]) -> Result<Vec<PEDesc>, TapascoRunError> {
    let mut pes: Vec<PEDesc> = Vec::new();
    let mut last_err : Option<tapasco::device::Error> = None;
    for dev in devices {
        dev.change_access(tapasco::tlkm::tlkm_access::TlkmAccessExclusive)
            .context(TapascoDeviceSnafu {})?;
        let dram = dev.default_memory().context(TapascoDeviceSnafu)?;
        //Acquire PEs of all supported types:
        //Regular DRAM
        let mut cur_result = acquire_pes(dev, "esa.informatik.tu-darmstadt.de:fuzzer:cva5_pe_fuzzer:1.0",
            |pe: PE| {pes.push(PEDesc::new(pe, PEMEMCONFIG_DRAM, Some(dram.clone())));}
        );
        //BRAM
        cur_result = cur_result.or(acquire_pes(dev, "esa.informatik.tu-darmstadt.de:fuzzer:cva5_bram_pe_fuzzer:1.0",
            |pe: PE| {pes.push(PEDesc::new(pe, PEMEMCONFIG_BRAM, None));}
            //|pe: PE| {pes.push(PEDesc::new(pe, PEMEMCONFIG_BRAM_DMA, Some(dram.clone())));}
        ));
        //HBM (programming via 'PE local memory' interface)
        cur_result = cur_result.or(acquire_pes(dev, "esa.informatik.tu-darmstadt.de:fuzzer:cva5_hbm_pe_fuzzer:1.0",
            |pe: PE| {pes.push(PEDesc::new(pe, PEMEMCONFIG_HBM, None));}
        ));
        //tapasco-riscv BRAM (for evaluation purposes)
        cur_result = cur_result.or(acquire_pes(dev, "esa.informatik.tu-darmstadt.de:tapasco:cva5_pe:1.0",
            |pe: PE| {pes.push(PEDesc::new_tapascoriscv(pe, PEMEMCONFIG_BRAM_TAPASCORISCV));}
        ));
        if let Err(e) = cur_result {
            last_err = Some(e); // Don't immediately return an error in case there are several devices.
        }
    }
    if pes.is_empty() {
        return Err(TapascoRunError::TapascoPENotFound { last: last_err });
    }
    Ok(pes)
}
//Splits the Jobs (PE wrappers) across new TapascoDispatchers.
//For now: Creates a single TapascoDispatchers with all Jobs.
pub fn create_dispatchers(pes: Vec<PEDesc>) -> Result<Vec<Arc<TapascoDispatcher>>, TapascoRunError> {
    Ok(vec![TapascoDispatcher::new(pes)?])
}

/// The [`TapascoRunnerPhysical`] manages the execution on TaPaSCo fuzzer PEs and retrieves the results.
/// Assumption: All users of the given TapascoDispatchers use the same program instruction memory.
pub struct TapascoRunnerPhysical<'a> {
    instmem: Box<[u8]>,
    datamem: Box<[u8]>,
    ignore_addresses_min: u32,
    dispatchers: Vec<Arc<TapascoDispatcher>>,
    timeout_cycles: u64,

    stop_req: &'a AtomicBool
}
impl<'a> TapascoRunnerPhysical<'a> {
    /// Create a new [`TapascoRunnerPhysical`]
    pub fn new(
        target: String,
        ignore_addresses_min: u32,
        dispatchers: Vec<Arc<TapascoDispatcher>>,
        timeout_cycles: u64,
        stop_req: &'a AtomicBool
    ) -> Result<Self, libafl::Error> {
        let (instmem, datamem) = read_binary(target.as_str())?;
        if dispatchers.is_empty() {
            return Err(libafl::Error::Unknown("TapascoRunnerPhysical: No dispatchers provided!".to_string()));
        }

        Ok(Self {
            instmem: instmem,
            datamem: datamem,
            ignore_addresses_min: ignore_addresses_min,
            dispatchers: dispatchers,
            timeout_cycles: timeout_cycles,
            stop_req: stop_req
        })
    }
}

#[async_trait(?Send)]
impl<'a> TapascoRunner for TapascoRunnerPhysical<'a> {
    async fn run(&mut self, input: &[u8], bitmap_mem: Arc<std::sync::Mutex<Box<[u8]>>>) -> Result<TapascoHostRun,TapascoRunError> {
        if self.stop_req.load(std::sync::atomic::Ordering::Relaxed) == true {
            return Err(TapascoRunError::LibAFL { source: libafl::Error::ShuttingDown });
        }
        //For now: Always give the task to the first dispatcher.
        let res = self.dispatchers.first().unwrap().run(0,
            &*self.instmem, &*self.datamem, self.ignore_addresses_min,
            self.timeout_cycles,
            input, bitmap_mem
        ).await;
        if self.stop_req.load(std::sync::atomic::Ordering::Relaxed) == true {
            return Err(TapascoRunError::LibAFL { source: libafl::Error::ShuttingDown });
        }
        res
    }
}
