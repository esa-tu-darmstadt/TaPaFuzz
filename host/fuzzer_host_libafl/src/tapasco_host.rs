//! TaPaSCo RISC-V Fuzzer host (`Executor`) for LibAFL
// Based on LibAFL's Forkserver executor code (https://github.com/AFLplusplus/LibAFL/blob/main/libafl/src/executors/forkserver.rs)

use core::{
    fmt::{self, Debug, Formatter},
    marker::PhantomData
};
use std::{sync::Arc, time::Duration};
use futures::executor;

use libafl::{
    executors::{Executor, ExitKind, HasObservers},
    inputs::{HasTargetBytes, Input},
    observers::{ObserversTuple, MapObserver}
};
use async_trait::async_trait;
use snafu::Snafu;

use crate::time_feedback::ManualTimeObserver;

pub mod TapascoRunStatusFlags {
    pub const PROGRAM_CRASH_FLAG: u32 = 1 << 0;
    pub const PROGRAM_CRASH_CAUSE_SHIFT: u32 = 1;
    pub const PROGRAM_CRASH_CAUSE_MASK: u32 = 31 << PROGRAM_CRASH_CAUSE_SHIFT;
    pub const INVALID_BITMAP_SIZE_FLAG: u32 = 1 << 6;
    pub const TIMEOUT_FLAG: u32 = 1 << 7;
    
    pub const ALL_MASK: u32 = 0xFF;
}

/// Run result data of a [`TapascoHost`].
#[derive(Debug)]
pub struct TapascoHostRun {
    pub status: u32,
    pub bitmap: Arc<std::sync::Mutex<Box<[u8]>>>,
    pub duration: Option<Duration>
}

#[derive(Debug, Snafu)]
#[snafu(visibility(pub(crate)))]
pub enum TapascoRunError {
    #[snafu(display("Unknown Error: {}", s))]
    Unknown { s: String },
    #[snafu(display("IO Error: {}", source))]
    IO { source: std::io::Error },
    #[snafu(display("LibAFL Error: {}", source))]
    LibAFL { source: libafl::Error },
    #[snafu(display("Bitmap length error: {}", s))]
    BitmapLen { s: String },
    #[snafu(display("Program instruction and/or data memory too large"))]
    ProgramOrDataTooLarge { },
    #[snafu(display("Input does not fit in free data memory"))]
    InputTooLarge { },
    #[snafu(display("A DRAM allocation does not fit the required {}K ({:x}) alignment: Address 0x{:x}", alignment_num/1024, alignment_num, addr))]
    DRAMAllocationMisaligned { addr: u64, alignment_num: u64 },

    #[snafu(display("Poisened mutex occured"))]
    MutexPoisoned {},

    #[snafu(display("TaPaSCo Allocator Error: {}", source))]
    TapascoAllocator { source: tapasco::allocator::Error },
    #[snafu(display("TaPaSCo DMA Error: {}", source))]
    TapascoDMA { source: tapasco::dma::Error },
    #[snafu(display("TaPaSCo TLKM Error: {}", source))]
    TapascoTLKM { source: tapasco::tlkm::Error },
    #[snafu(display("TaPaSCo Device Error: {}", source))]
    TapascoDevice { source: tapasco::device::Error },
    #[snafu(display("TaPaSCo PE Error: {}", source))]
    TapascoPE { source: tapasco::pe::Error },
    #[snafu(display("TaPaSCo PE not found. Last Error: {:?}", last))]
    TapascoPENotFound { last: Option<tapasco::device::Error> },
    #[snafu(display("TaPaSCo Job Error: {}", source))]
    TapascoJob { source: tapasco::job::Error },
}
impl From<std::io::Error> for TapascoRunError {
    fn from(err: std::io::Error) -> Self {
        Self::IO {source: err}
    }
}
impl From<libafl::Error> for TapascoRunError {
    fn from(err: libafl::Error) -> Self {
        Self::LibAFL {source: err}
    }
}
impl<T> From<std::sync::PoisonError<T>> for TapascoRunError {
    fn from(_err: std::sync::PoisonError<T>) -> Self {
        Self::MutexPoisoned {}
    }
}

/// Trait for program execution backends.
#[async_trait(?Send)]
pub trait TapascoRunner {
    async fn run(&mut self, input: &[u8], bitmap_mem: Arc<std::sync::Mutex<Box<[u8]>>>) -> Result<TapascoHostRun,TapascoRunError>;
}

/// A struct that has a [`TapascoRunner`]
pub trait HasTapascoRunner {
    /// The host
    fn runner(&self) -> &dyn TapascoRunner;

    /// The host, mutable
    fn runner_mut(&mut self) -> &mut dyn TapascoRunner;
}

/// This [`Executor`] can launch binaries through a [`TapascoRunner`].
pub struct TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    target: String,
    tapascorunner: &'host mut dyn TapascoRunner,
    bitmap_internal: Arc<std::sync::Mutex<Box<[u8]>>>,
    observers: OT,
    map_observer_name: &'static str,
    time_observer_name: &'static str,
    phantom: PhantomData<(I, O, S)>,
}

impl<'host, I, O, OT, S> Debug for TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.debug_struct("TapascoHostExecutor")
            .field("target", &self.target)
            //.field("tapascorunner", self.tapascorunner)
            .field("observers", &self.observers)
            .field("map_observer_name", &self.map_observer_name.to_string())
            .finish()
    }
}

impl<'host, I, O, OT, S> TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    /// Creates a new [`TapascoHostExecutor`] with the given target, actual runner and observers.
    pub fn new(
        target: String,
        tapascorunner: &'host mut dyn TapascoRunner,
        observers: OT,
        map_observer_name: &'static str,
        bitmap_len: usize,
        time_observer_name: &'static str,
    ) -> Result<Self, libafl::Error> {
        Self::with_debug(target, tapascorunner, observers, map_observer_name, bitmap_len, time_observer_name, false)
    }

    /// Creates a new [`TapascoHostExecutor`] with the given target, arguments and observers, with debug mode
    pub fn with_debug(
        target: String,
        tapascorunner: &'host mut dyn TapascoRunner,
        observers: OT,
        map_observer_name: &'static str,
        bitmap_len: usize,
        time_observer_name: &'static str,
        _debug_output: bool,
    ) -> Result<Self, libafl::Error> {        
        let mut bitmap_internal_vec : Vec<u8> = Vec::new();
        bitmap_internal_vec.resize(bitmap_len, 0);
        let bitmap_internal = std::sync::Arc::new(std::sync::Mutex::new(bitmap_internal_vec.into_boxed_slice()));

        Ok(Self {
            target: target,
            tapascorunner: tapascorunner,
            bitmap_internal: bitmap_internal,
            observers: observers,
            map_observer_name: map_observer_name,
            time_observer_name: time_observer_name,
            phantom: PhantomData,
        })
    }
}

impl<'host, I, O, OT, S> TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    #[inline]
    pub fn run_target(
        &mut self,
        input: &I,
    ) -> Result<ExitKind, libafl::Error> {
        let exit_kind;

        let input_slice_owner = input.target_bytes();
        let input_slice = input_slice_owner.as_slice();
        let bitmap_interal_cl1 = self.bitmap_internal.clone();
        // Invoke the [`TapascoRunner`].
        let result = executor::block_on(self.runner_mut().run(input_slice, bitmap_interal_cl1));
        let time_observer_name = self.time_observer_name;
        match result {
            Err(e) => {
                //Set the duration in the [`ManualTimeOberver`] to None.
                self.observers_mut().match_name_mut::<ManualTimeObserver>(time_observer_name)
                    .ok_or_else(|| libafl::Error::KeyNotFound("ManualTimeObserver not found".to_string()))?
                    .set_last_runtime(None);
                // Convert errors to a libafl::Error type.
                return Err(match e {
                    TapascoRunError::Unknown { s } => libafl::Error::Unknown(s),
                    TapascoRunError::IO { source } => libafl::Error::File(source),
                    TapascoRunError::LibAFL { source } => source,
                    _ => libafl::Error::Unknown(e.to_string()),
                });
            }
            Ok(run) => {
                if (run.status & TapascoRunStatusFlags::INVALID_BITMAP_SIZE_FLAG) != 0 {
                    return Err(libafl::Error::Unknown("PE: Invalid bitmap size".to_string()));
                }
                else if (run.status & !TapascoRunStatusFlags::ALL_MASK) != 0 {
                    return Err(libafl::Error::Unknown(format!("PE: Invalid run status 0x{:x}", run.status)));
                }
                else if (run.status & TapascoRunStatusFlags::TIMEOUT_FLAG) != 0 {
                    exit_kind = ExitKind::Timeout;
                    println!("Run result: Timeout.");
                }
                else if (run.status & TapascoRunStatusFlags::PROGRAM_CRASH_FLAG) != 0 {
                    exit_kind = ExitKind::Crash;
                }
                else {
                    exit_kind = ExitKind::Ok;
                }
                //Copy the bitmap regardless of how execution ended.
                // -> LibAFL doesn't register crashes if the bitmap only has zeroes.
                let bitmap_interal_cl2 = self.bitmap_internal.clone();
                let lock_res = (*bitmap_interal_cl2).try_lock();
                assert!(match lock_res {Ok(_) => {true} Err(_) => {false}},
                    "Unable to lock mutex that should have been unlocked: {}", lock_res.unwrap_err());
                //Based on LibAFL: libafl/src/stages/calibrate.rs
                let map_observer_name = self.map_observer_name;

                //Copy the bitmap into the [`MapOberver`].
                self.observers_mut().match_name_mut::<O>(map_observer_name)
                    .ok_or_else(|| libafl::Error::KeyNotFound("MapObserver not found".to_string()))?
                    .map_mut().unwrap()
                    .copy_from_slice(&*lock_res.unwrap());

                //Set the duration in the [`ManualTimeOberver`].
                self.observers_mut().match_name_mut::<ManualTimeObserver>(time_observer_name)
                    .ok_or_else(|| libafl::Error::KeyNotFound("ManualTimeObserver not found".to_string()))?
                    .set_last_runtime(run.duration);
            }
        };

        Ok(exit_kind)
    }
}

impl<'host, EM, I, O, OT, S, Z> Executor<EM, I, S, Z> for TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    #[inline]
    fn run_target(
        &mut self,
        _fuzzer: &mut Z,
        _state: &mut S,
        _mgr: &mut EM,
        input: &I,
    ) -> Result<ExitKind, libafl::Error> {
        self.run_target(input)
    }
}

impl<'host, I, O, OT, S> HasObservers<I, OT, S> for TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    #[inline]
    fn observers(&self) -> &OT {
        &self.observers
    }

    #[inline]
    fn observers_mut(&mut self) -> &mut OT {
        &mut self.observers
    }
}

impl<'host, I, O, OT, S> HasTapascoRunner for TapascoHostExecutor<'host, I, O, OT, S>
where
    I: Input + HasTargetBytes,
    OT: ObserversTuple<I, S>,
    O: MapObserver<u8>,
{
    #[inline]
    fn runner(&self) -> &dyn TapascoRunner {
        self.tapascorunner
    }

    /// The runner, mutable
    #[inline]
    fn runner_mut(&mut self) -> &mut dyn TapascoRunner {
        self.tapascorunner
    }
}
