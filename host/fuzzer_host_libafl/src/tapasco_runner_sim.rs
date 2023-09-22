use core::fmt::Debug;
use std::{
    io::{prelude::*},
    sync::{Arc, atomic::AtomicBool},
    process::{Command, Child},
    cmp,
    fs::File,
    os::unix::io::IntoRawFd,
    time::Duration
};

use libafl::{
    bolts::shmem::{ShMemProvider, ShMem, unix_shmem::{MmapShMemProvider, MmapShMem}},
    bolts::os::pipes::Pipe
};
use async_trait::async_trait;

use crate::tapasco_host::{TapascoHostRun, TapascoRunner, TapascoRunError};


/// The [`TapascoRunnerSim`] manages the execution on the tapasco-pe-tb fuzzer PE simulation.
/// (Currently only a stub).
#[derive(Debug)]
pub struct TapascoRunnerSim<'a> {
    child: Child,
    shmem: <MmapShMemProvider as ShMemProvider>::Mem,
    req_pipe: Pipe,
    resp_pipe: Pipe,
    fuzzer_stdout: std::os::raw::c_int,
    timeout_cycles: u64,
    stop_req: &'a AtomicBool
}

impl<'a> TapascoRunnerSim<'a> {
    /// Create a new [`TapascoRunnerSim`]
    pub fn new(
        target: String,
        ignore_addresses_min: u32,
        pesimdir: String,
        stdout_filepath: Option<String>,
        timeout_cycles: u64,
        stop_req: &'a AtomicBool
    ) -> Result<Self, libafl::Error> {
        let mut req_pipe = Pipe::new()?;
        let mut resp_pipe = Pipe::new()?;
        // Cannot create several MmapShMems with the same ID,
        //  regardless of where it was created (e.g. in another thread).
        let mut shmem_res: Result<MmapShMem, libafl::Error> = Err(libafl::Error::Unknown("".to_string()));
        let mut shmem_cnt: usize = 0;
        for i  in 0..512 {
            shmem_res = MmapShMem::new(4096, i);
            if let Ok(_) = shmem_res {
                shmem_cnt = i;
                break;
            }
        }
        let shmem = shmem_res?;
        //Hack (MmapShMem does not provide a getter for the name).
        let shmem_path = format!("/libafl_{}_{}", std::process::id(), shmem_cnt);
        //stdout)
        let fuzzer_stdout = match stdout_filepath {
            Some(s) => {
                let filefd = File::create(s)?.into_raw_fd();
                //File::create sets the FD_CLOEXEC flag,
                // i.e. child process will not inherit the fd by default.
                //Option A: Call fcntl with F_GETFD and F_SETFD, removing the flag.
                //Option B: Duplicate the fd.
                //          Simpler open code, but both fds must be closed later.
                //Using option A.
                unsafe {
                    let fdflags = match libc::fcntl(filefd, libc::F_GETFD) {
                        -1 => Err(std::io::Error::last_os_error())?,
                        flags => flags
                    };
                    match libc::fcntl(filefd, libc::F_SETFD, fdflags & !libc::FD_CLOEXEC) {
                        -1 => Err(std::io::Error::last_os_error())?,
                        _ => {}
                    };
                };
                filefd
            },
            None => unsafe {libc::dup(0)}
        };

        let child = Command::new("make")
            .current_dir(pesimdir)
            .env("FUZZTB_TARGET", target)
            .env("FUZZTB_IGNOREMIN", format!("{:08x}", ignore_addresses_min))
            .env("FUZZTB_SHMEM", shmem_path)
            .env("FUZZTB_SHMEM_SIZE", format!("{}", shmem.len()))
            .env("FUZZTB_REQ_PIPE", format!("{}", req_pipe.read_end().ok_or(libafl::Error::Unknown("Pipe read_end empty".to_string()))?))
            .env("FUZZTB_RESP_PIPE", format!("{}", resp_pipe.write_end().ok_or(libafl::Error::Unknown("Pipe write_end empty".to_string()))?))
            .env("FUZZTB_STDOUT", format!("{}", fuzzer_stdout))
            .stdout(std::process::Stdio::null())
            .spawn()
            .map_err(|e| {libafl::Error::Unknown(format!("Unable to start tapasco-pe-tb: {}", e))})?;
        
        req_pipe.close_read_end();
        resp_pipe.close_write_end();

        Ok(Self {
            child: child,
            shmem: shmem,
            req_pipe: req_pipe,
            resp_pipe: resp_pipe,
            fuzzer_stdout: fuzzer_stdout,
            stop_req: stop_req,
            timeout_cycles: timeout_cycles
        })
    }
}

impl<'a> TapascoRunnerSim<'a> {
    fn read_resp(&mut self) -> Result<u8, std::io::Error> {
        let mut buf: [u8; 1] = [0_u8; 1];
        self.resp_pipe.read(&mut buf)?;

        Ok(buf[0])
    }
    fn write_req_type(&mut self, req: u8) -> Result<usize, std::io::Error> {
        self.req_pipe.write(std::slice::from_ref(&req))
    }
}

enum SimRequestType {
    SetInput = 0,
    Start = 1,
    CopyBitmap = 2,
    Close = 255
}

#[async_trait(?Send)]
impl<'a> TapascoRunner for TapascoRunnerSim<'a> {
    async fn run(&mut self, input: &[u8], bitmap_mem: Arc<std::sync::Mutex<Box<[u8]>>>) -> Result<TapascoHostRun,TapascoRunError> {
        //Not properly 'async' (only blocking operations).
        if self.stop_req.load(std::sync::atomic::Ordering::Relaxed) == true {
            return Err(TapascoRunError::LibAFL { source: libafl::Error::ShuttingDown });
        }

        //Write the input data to shared memory (truncated to the shared memory block length).
        {
            let input_len = cmp::min(input.len(), self.shmem.len() - 4) as u32;
            let input_len_bytes = input_len.to_ne_bytes();
            self.shmem.map_mut()[..4].copy_from_slice(&input_len_bytes[..4]);
            self.shmem.map_mut()[4..(4 + (input_len as usize))].copy_from_slice(input);
        }
        //Tell the simulator to take the input data, and wait for a response.
        self.write_req_type(SimRequestType::SetInput as u8)?;
        self.read_resp()?;
        let ret_status: u32;
        let counter: u64;
        {
            let lock_res = (*bitmap_mem).try_lock();
            assert!(match lock_res {Ok(_) => {true} Err(_) => {false}},
                "Unable to lock mutex that should have been unlocked: {}", lock_res.unwrap_err());
            let bitmap_slice = &mut **lock_res.unwrap();
            if bitmap_slice.len() < 4 || bitmap_slice.len() > self.shmem.len() {
                return Err(TapascoRunError::BitmapLen{s:
                    format!("Bitmap length is {}, but should be in [4, {}]", bitmap_slice.len(), self.shmem.len())});
            }
            //Start the PE, providing the bitmap size and timeout through shmem.
            {
                let bitmap_len_bytes = (bitmap_slice.len() as u32).to_ne_bytes();
                self.shmem.map_mut()[..4].copy_from_slice(&bitmap_len_bytes[..4]);
                let timeout_cycles_bytes = (self.timeout_cycles as u64).to_ne_bytes();
                self.shmem.map_mut()[8..16].copy_from_slice(&timeout_cycles_bytes[..8]);
            }
            self.write_req_type(SimRequestType::Start as u8)?;
            
            //The program result is given as 32bit fields in shmem.
            let _resp = self.read_resp()?;
            let mut _valbytes32 = [0u8; 4];

            _valbytes32.copy_from_slice(&self.shmem.map()[0..4]);
            let ret_lo = u32::from_ne_bytes(_valbytes32);

            _valbytes32.copy_from_slice(&self.shmem.map()[4..8]);
            let _arg4_lo = u32::from_ne_bytes(_valbytes32);

            _valbytes32.copy_from_slice(&self.shmem.map()[8..12]);
            let _arg4_hi = u32::from_ne_bytes(_valbytes32);

            let mut _valbytes64 = [0u8; 8];
            _valbytes64.copy_from_slice(&self.shmem.map()[16..24]);
            let _counter = u64::from_ne_bytes(_valbytes64);

            ret_status = ret_lo;
            counter = _counter;

            //Read the bitmap.
            self.write_req_type(SimRequestType::CopyBitmap as u8)?;
            self.read_resp()?;
            {
                let shmem_slice = self.shmem.map();
                bitmap_slice.copy_from_slice(&shmem_slice[0..bitmap_slice.len()]);
            }

        }
        if self.stop_req.load(std::sync::atomic::Ordering::Relaxed) == true {
            return Err(TapascoRunError::LibAFL { source: libafl::Error::ShuttingDown });
        }
        Ok(TapascoHostRun {
            status: ret_status,
            bitmap: bitmap_mem,
            duration: Some(Duration::new(counter >> 32, (counter & 0xFFFFFFFF) as u32))
        })
    }
}

impl<'a> Drop for TapascoRunnerSim<'a> {
    fn drop(&mut self) {
        if let Ok(None) = self.child.try_wait() {
            //Process still running, send the Close command and wait.
            let _writecloseres = self.write_req_type(SimRequestType::Close as u8);
            let _childwaitres = self.child.wait();
        }
        if self.fuzzer_stdout != -1 {
            unsafe { libc::close(self.fuzzer_stdout); };
            self.fuzzer_stdout = -1;
        }
    }
}