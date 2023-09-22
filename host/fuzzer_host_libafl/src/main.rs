//Modified based on LibAFL's forkserver fuzzer example ( https://github.com/AFLplusplus/LibAFL/blob/main/fuzzers/forkserver_simple )
// and the fuzzbench host ( https://github.com/AFLplusplus/LibAFL/blob/main/fuzzers/fuzzbench/src ).

mod tapasco_host;
mod tapasco_runner_sim;
mod tapasco_runner_phys;
mod time_feedback;

use libafl::{
    bolts::{
        current_nanos,
        rands::StdRand,
        os::{Cores, CoreId},
        tuples::{tuple_list, Merge},
        llmp::{LlmpClient, LlmpBroker},
        shmem::{StdShMemProvider, ShMemProvider},
    },
    corpus::{
        Corpus, IndexesLenTimeMinimizerCorpusScheduler, OnDiskCorpus,
        PowerQueueCorpusScheduler, CachedOnDiskCorpus,
    },
    events::{LlmpEventManager, EventConfig, LlmpEventBroker},
    feedback_and_fast, feedback_or,
    feedbacks::{CrashFeedback, MapFeedbackState, MaxMapFeedback},
    fuzzer::{Fuzzer, StdFuzzer},
    inputs::BytesInput,
    monitors::MultiMonitor,
    mutators::{scheduled::havoc_mutations, tokens_mutations, Tokens, StdMOptMutator},
    observers::{VariableMapObserver, HitcountsMapObserver},
    stages::{CalibrationStage, power::PowerSchedule, PowerMutationalStage},
    state::{HasCorpus, StdState, HasMetadata}, executors::ExitKind,
};
use libc::sigaction;
use tapasco_host::{TapascoHostExecutor, TapascoRunError, TapascoRunner};
use tapasco_runner_sim::{TapascoRunnerSim};
use tapasco_runner_phys::{TapascoRunnerPhysical, TapascoDispatcher};
use time_feedback::{ManualTimeObserver, ManualTimeFeedback};
use std::{
    path::PathBuf,
    sync::{Arc, atomic::{AtomicBool, AtomicU64}, Barrier, Once},
    marker::PhantomData,
    num::ParseIntError, io::Read,
    u32
};

use clap::{Command, Arg, ArgMatches};
use snafu::{Snafu, ResultExt};

//HACK: From libafl/src/events/llmp.rs, since it is not marked as public there:
const LLMP_TAG_EVENT_TO_BOTH: libafl::bolts::llmp::Tag = 0x2B0741;

#[derive(Debug, Snafu)]
enum FuzzErr {
    #[snafu(display("{}", source))]
    TapascoRunError { source: TapascoRunError},
    #[snafu(display("{}", source))]
    AFLError { source: libafl::Error},
    #[snafu(display("{}: {}", desc, source))]
    AFLDescError { desc: String, source: libafl::Error},
    #[snafu(display("{}", s))]
    ArgError { s: String },
    #[snafu(display("{}", source))]
    ParseIntError { source: ParseIntError },
    #[snafu(display("Program execution with a benchmark corpus entry did not succeed"))]
    BenchmarkCorpusError { }
}

fn create_tapascorunner<'a>(cmd_matches: &ArgMatches,
    tapasco_dispatchers: Vec<Arc<TapascoDispatcher>>,
    stop_req: &'a AtomicBool)
-> Result<Box<dyn TapascoRunner + 'a>, FuzzErr> {
    let target: String = cmd_matches.value_of("binary").ok_or(FuzzErr::ArgError{s:"binary argument missing".to_string()})?.to_string();
    let ignoreaddr_min: u32 = cmd_matches.value_of("ignore_min").map_or(0xffffffff, |s| u32::from_str_radix(s, 16).unwrap());
    let timeout_cycles = cmd_matches.value_of("timeout").map_or(0,|s| s.parse::<u64>().unwrap());
    let tapasco_host: Box<dyn TapascoRunner>;
    match cmd_matches.subcommand() {
        Some(("sim", simcmd_matches)) => {
            //Simulation runner backend, invokes a tapasco-pe-tb testbench and uses IPC for parameter and result transfer.
            tapasco_host = Box::new(TapascoRunnerSim::<'a>::new(
                    target,
                    ignoreaddr_min,
                    simcmd_matches.value_of("simdir").ok_or(FuzzErr::ArgError{s:"simdir argument missing".to_string()})?.to_string(),
                    simcmd_matches.value_of("simlogfile").and_then(|s| Some(s.to_string())),
                    timeout_cycles,
                    stop_req
                ).context(AFLDescSnafu {desc: "Failed to create the tapasco-pe-tb runner.".to_string()})?
            );
        },
        Some(("tapasco", _tapascocmd_matches)) => {
            //TaPaSCo runner backend. Takes a PE, configures it and waits for the results.
            tapasco_host = Box::new(TapascoRunnerPhysical::<'a>::new(
                    target,
                    ignoreaddr_min,
                    tapasco_dispatchers,
                    timeout_cycles,
                    stop_req
                ).context(AFLDescSnafu {desc: "Failed to create the TaPaSCo runner.".to_string() })?
            );
        },
        _ => unreachable!()
    }
    Ok(tapasco_host)
}

const MAP_OBSERVER_NAME: &'static str = "copied_bitmap";
const TIME_OBSERVER_NAME: &'static str = "time";

//Runs an execution benchmark.
fn benchmark(i_thread: usize,
    cmd_matches: ArgMatches,
    tapasco_dispatchers: Vec<Arc<TapascoDispatcher>>,
    inputs: &Vec<BytesInput>,
    barrier_start: &Barrier,
    stop_req: &AtomicBool)
    -> Result<u64, FuzzErr> {
    
    let bitmap_size = cmd_matches.value_of("bitmapsize").ok_or(FuzzErr::ArgError{s:"bitmapsize argument missing".to_string()})?.parse::<usize>().unwrap();
    let mut bitmap_vec_tmp : Vec<u8> = Vec::new();
    bitmap_vec_tmp.resize(bitmap_size, 0);
    let mut bitmap_buf = bitmap_vec_tmp.into_boxed_slice();

    let mut _tmp_bitmap_size = bitmap_size;
    // Create an observation channel for the bitmap
    let edges_observer = HitcountsMapObserver::new(VariableMapObserver::new(
        MAP_OBSERVER_NAME,
        &mut *bitmap_buf,
        &mut _tmp_bitmap_size //Does not appear to be used by VariableMapObserver except for reading?
    ));
    // Create an observation channel to keep track of the execution time
    let time_observer = ManualTimeObserver::new(TIME_OBSERVER_NAME);

    let mut tapasco_host: Box<dyn TapascoRunner> = create_tapascorunner(&cmd_matches, tapasco_dispatchers, stop_req)?;

    // Executor to interface with the TapascoRunner.
    let mut executor = TapascoHostExecutor::<BytesInput,HitcountsMapObserver<VariableMapObserver<u8>>,_,u8>::new(
        cmd_matches.value_of("binary").ok_or(FuzzErr::ArgError{s:"binary argument missing".to_string()})?.to_string(),
        tapasco_host.as_mut(),
        tuple_list!(edges_observer, time_observer),
        MAP_OBSERVER_NAME,
        bitmap_size,
        TIME_OBSERVER_NAME
    )
    .context(AFLDescSnafu {desc: "Failed to create the executor.".to_string() })?;

    let numiter = cmd_matches.value_of("numiter").unwrap_or("1").parse::<u64>().context(ParseIntSnafu)?;

    // Initialisation is done, enter the actual benchmark Barrier.
    if inputs.len() > 0 {
        executor.run_target(&inputs[0]).context(AFLSnafu)?;
    }
    barrier_start.wait();
    let run_start_time = std::time::Instant::now();

    let mut num_executions: u64 = 0;
    for _ in 0..numiter {
        for input in inputs {
            if executor.run_target(input).context(AFLSnafu)? != ExitKind::Ok {
                return Err(FuzzErr::BenchmarkCorpusError {});
            }
            num_executions += 1;
        }
    }
    let elapsed_run = run_start_time.elapsed().as_secs_f64();
    if elapsed_run > 1e-9 {
        println!("Thread {} finished after {:.3e} seconds ({:.2} exec per second).",
            i_thread, elapsed_run,
            (num_executions as f64) / elapsed_run);
    }
    else {
        println!("Thread {} finished after {:.3e} seconds", i_thread, elapsed_run);
    }

    Ok(num_executions)
}

//Initialises and runs the fuzzer loop for a thread. 
fn fuzz<SP>(i_thread: usize,
    cmd_matches: ArgMatches, llmp_client: LlmpClient<SP>, tapasco_dispatchers: Vec<Arc<TapascoDispatcher>>,
    stop_req: &AtomicBool)
    -> Result<(), FuzzErr>
where SP: ShMemProvider, SP: 'static {
    println!("Thread {} starting up.",  i_thread);

    let corpus_dirs = vec![PathBuf::from(cmd_matches.value_of("in").ok_or(FuzzErr::ArgError{s:"in argument missing".to_string()})?.to_string())];

    let bitmap_size = cmd_matches.value_of("bitmapsize").ok_or(FuzzErr::ArgError{s:"bitmapsize argument missing".to_string()})?.parse::<usize>().unwrap();

    // Note: Possibly, for some targets u16 or even u32 for the bitmap (i.e. edge count map) may be necessary instead of just u8.
    let mut bitmap_vec_tmp : Vec<u8> = Vec::new();
    bitmap_vec_tmp.resize(bitmap_size, 0);
    let mut bitmap_buf = bitmap_vec_tmp.into_boxed_slice();

    let mut _tmp_bitmap_size = bitmap_size;
    // Create an observation channel for the bitmap
    let edges_observer = HitcountsMapObserver::new(VariableMapObserver::new(
        MAP_OBSERVER_NAME,
        &mut *bitmap_buf,
        &mut _tmp_bitmap_size //Does not appear to be used by VariableMapObserver except for reading?
    ));

    // Create an observation channel to keep track of the execution time
    let time_observer = ManualTimeObserver::new(TIME_OBSERVER_NAME);

    // The state of the edges feedback.
    let feedback_state = MapFeedbackState::with_observer(&edges_observer);

    // The state of the edges feedback for crashes.
    let objective_state = MapFeedbackState::new("crash_edges", bitmap_size);
    
    // Feedback to rate the interestingness of an input
    // This one is composed by two Feedbacks in OR
    let feedback = feedback_or!(
        // New maximization map feedback linked to the edges observer and the feedback state
        MaxMapFeedback::new_tracking(&feedback_state, &edges_observer, true, false),
        // Time feedback, this one does not need a feedback state
        ManualTimeFeedback::new_with_observer(&time_observer)
    );

    // A feedback to choose if an input is a solution or not
    // We want to do the same crash deduplication that AFL does
    let objective = feedback_and_fast!(
        // Must be a crash
        CrashFeedback::new(),
        // Take it onlt if trigger new coverage over crashes
        MaxMapFeedback::new(&objective_state, &edges_observer)
    );

    // create a State from scratch
    let mut state = StdState::new(
        // RNG
        StdRand::with_seed(current_nanos()),
        // Corpus that will be evolved, saved to disk for external analysis but cached in memory for performance
        CachedOnDiskCorpus::<BytesInput>::new(PathBuf::from("./runtimecorpus"), 256).context(AFLSnafu)?,
        // Corpus in which we store solutions (crashes in this example),
        // on disk so the user can get them after stopping the fuzzer
        OnDiskCorpus::new(PathBuf::from("./crashes")).context(AFLSnafu)?,
        // States of the feedbacks.
        // They are the data related to the feedbacks that you want to persist in the State.
        tuple_list!(feedback_state, objective_state),
    );
    // Add tokens.
    if state.metadata().get::<Tokens>().is_none() {
        let tokens = match cmd_matches.value_of("tokenfile") {
            Some(tokenfile) => Tokens::from_tokens_file(tokenfile).context(AFLSnafu)?,
            None => Tokens::new(vec![ //Some tokens for JSON
                vec![b'{'], vec![b'}'], 
                vec![b'['], vec![b']'],
                vec![b','],
                vec![b':'],
                vec![b'"'],
            ])
        };
        state.add_metadata(tokens);
    }

    // The event manager handle the various events generated during the fuzzing loop
    //  such as the notification of the addition of a new item to the corpus.
    // EventConfig: Used to distinghuish between independent fuzzer sessions (?)
    //  in multi processing mode.
    // For this fuzzer, the client<->broker connection does not run into collisions either way,
    //  since the clients are generated in-process and directly connected to the LlmpBroker object.
    let mut mgr = LlmpEventManager::new(llmp_client, EventConfig::from_build_id()).context(AFLSnafu)?;

    // A minimization+queue policy to get testcasess from the corpus
    let scheduler = IndexesLenTimeMinimizerCorpusScheduler::new(PowerQueueCorpusScheduler::new());

    // A fuzzer with feedbacks and a corpus scheduler
    let mut fuzzer = StdFuzzer::new(scheduler, feedback, objective);

    // Create the executor for the forkserver
    let mut tapasco_host: Box<dyn TapascoRunner> = create_tapascorunner(&cmd_matches, tapasco_dispatchers, stop_req)?;

    let calibration = CalibrationStage::new(&mut state, &edges_observer);

    // Setup a MOPT mutator
    let mutator = StdMOptMutator::new(&mut state, havoc_mutations().merge(tokens_mutations()), 5).context(AFLSnafu)?;
    let power = PowerMutationalStage::new(mutator, PowerSchedule::FAST, &edges_observer);

    let mut stages = tuple_list!(calibration, power);

    // Executor as an 'adapter' between the LibAFL API and the TapascoRunner.
    let mut executor = TapascoHostExecutor::<_,HitcountsMapObserver<VariableMapObserver<u8>>,_,_>::new(
        cmd_matches.value_of("binary").ok_or(FuzzErr::ArgError{s:"binary argument missing".to_string()})?.to_string(),
        tapasco_host.as_mut(),
        tuple_list!(edges_observer, time_observer),
        MAP_OBSERVER_NAME,
        bitmap_size,
        TIME_OBSERVER_NAME
    )
    .context(AFLDescSnafu {desc: "Failed to create the executor.".to_string() })?;

    // In case the corpus is empty (on first run), reset
    if state.corpus().count() < 1 {
        state
            .load_initial_inputs(&mut fuzzer, &mut executor, &mut mgr, &corpus_dirs)
            .context(AFLDescSnafu {
                desc: format!("Failed to load initial corpus at {:?}",
                    &corpus_dirs) 
                }
            )?;
        println!("We imported {} inputs from disk.", state.corpus().count());
    }
    
    let fuzz_result = match cmd_matches.value_of("numiter") {
        Some(s) => {
            let numiter = s.parse::<u64>().context(ParseIntSnafu)?;
            fuzzer.fuzz_loop_for(&mut stages, &mut executor, &mut state, &mut mgr, numiter)
        }
        None => {
            fuzzer.fuzz_loop(&mut stages, &mut executor, &mut state, &mut mgr)
        }
    };
    match fuzz_result {
        Err(libafl::Error::ShuttingDown) => {
            //Don't panic on a regular shutdown.
            println!("Thread {} shutting down.", i_thread);
        },
        _ => {
            fuzz_result.context(AFLSnafu)?;
        }
    }

    Ok(())
}

#[allow(clippy::similar_names)]
pub fn main() {
    let cmd_matches = Command::new("fuzzer_host_libafl")
        .about("Fuzzer host for TaPaSCo-based fuzzing accelerator")
        .subcommand_required(true)
        .subcommand(Command::new("sim")
            .about("Simulate the hardware through tapasco-pe-tb.")
            .arg(
                Arg::new("simdir")
                    .help("The directory of the tapasco-pe-tb based simulator")
                    .required(true)
                    .takes_value(true),
            )            
            .arg(
                Arg::new("simlogfile").long("simlogfile") //Positional arg
                    .help("Log file path for the simulation script")
                    .takes_value(true),
            )
        )   
        .subcommand(Command::new("tapasco")
            .about("Run on hardware accessible through TaPaSCo.")
        )   
        .arg(
            Arg::new("binary")
                .help("The instrumented binary we want to fuzz")
                .required(true)
                .takes_value(true),
        )
        .arg(
            Arg::new("in")
                .help("The directory to read initial inputs from ('seeds')")
                .required(true)
                .takes_value(true),
        )
        .arg(
            Arg::new("ignore_min").long("ignore_min")
                .help("Address range minimum for the hardware to ignore any control flows in. 32bit hex without 0x")
                .validator(|s| u32::from_str_radix(s, 16))
                .takes_value(true)
        )
        .arg(
            Arg::new("bitmapsize").long("bitmapsize").short('b') //Positional arg
                .help("Amount of CF edge counters. Must be a power of two of at most 8192.")
                .long_help("Bitmap length for the fuzzer, where each 'bit' is actually a counter addressed by a range of CF edge hashes.\n\
                            Higher values generally decrease the collision ratio, whereas smaller values increase performance.")
                .validator(|s| -> Result<(),String> {
                    let bitmapsize = s.parse::<usize>().or_else(|e| Err(e.to_string()))?;
                    if bitmapsize == 0 {
                        return Err("bitmapsize must be a power of two".to_string());
                    }
                    if bitmapsize > 8192 {
                        return Err("bitmapsize must be a power of two of at most 8192".to_string());
                    }
                    for i in 0..64 {
                        if (bitmapsize & (1 << i)) != 0 && (bitmapsize & !(1 << i)) != 0 {
                            return Err("bitmapsize must be a power of two".to_string());
                        }
                    }
                    Ok(())
                })
                .takes_value(true)
                .default_value("8192"),
        )
        .arg(
            Arg::new("tokenfile").long("tokenfile") //Positional arg
                .help("Token dictionary file path")
                .long_help("Token dictionary file path, supports the AFL++ dictionary format.\nSee https://github.com/AFLplusplus/AFLplusplus/tree/stable/dictionaries")
                .takes_value(true),
        )
        .arg(
            Arg::new("numiter").long("numiter") //Positional arg
                .help("Number of fuzzer or benchmark loop iterations")
                .validator(|s| 
                     s.parse::<u64>()
                     .map_err(|e| e.to_string())
                     .and_then(|val| if val > 0 {Ok(val)} else {Err("numiter must be at least one".to_string())})
                    )
                .takes_value(true),
        )
        .arg(
            Arg::new("numthreads").long("numthreads") //Positional arg
                .help("Number of fuzzing threads")
                .validator(|s| -> Result<(),String> {
                        let n = s.parse::<usize>().or_else(|e| Err(e.to_string()))?;
                        if n == 0 {
                            return Err("At least one thread required".to_string());
                        }
                        if n > 1024 {
                            return Err("Excessive number of threads (expected <= 1024)".to_string());
                        }
                        Ok(())
                    })
                .default_value("1")
                .takes_value(true),
        )
        .arg(
            Arg::new("cores").long("cores") //Positional arg
                .help("Comma-separated list of cores to run the fuzzing threads on.")
                .validator(|s| Cores::from_cmdline(s))
                .default_value("all")
                .takes_value(true),
        )
        .arg(
            Arg::new("timeout").long("timeout")
                .help("Timeout for each individual execution, in PE cycles")
                .validator(|s| s.parse::<u64>())
                .default_value("400000000") //Equivalent to 4 seconds at 100 MHz
                .takes_value(true),
        )
        .arg(
            Arg::new("benchmark").long("benchmark")
                .help("Run benchmark mode instead of fuzzer")
        )
        .get_matches();

    let num_threads = cmd_matches.value_of("numthreads").unwrap().parse::<usize>().unwrap();
    let mut cores = Cores::from_cmdline(cmd_matches.value_of("cores").unwrap()).map(|coress| coress.ids).unwrap_or_default();
    if num_threads > cores.len() {
        cores.clear();
    }
    else {
        println!("Setting per-thread affinity {:?}.", &cores);
    }
    //Use LLMP for multi threading.
    //For now, use inter-process shared memory (no ShMemProvider provides regular heap memory).
    let shmem_provider = StdShMemProvider::new().unwrap();
    let mut broker = LlmpBroker::new(shmem_provider.clone()).unwrap();

    let mut tapasco_dispatchers: Vec<Arc<TapascoDispatcher>> = Vec::new();

    if let Some(("tapasco", _tapascocmd_matches)) = cmd_matches.subcommand() {
        //For TaPaSCo mode, fetch the available PEs and create TapascoDispatchers to distribute to the threads.
        let tlkm = tapasco::tlkm::TLKM::new().unwrap();
        let mut devices = tlkm.device_enum(&std::collections::HashMap::new()).unwrap();
        let pes = tapasco_runner_phys::get_pes(&mut devices[..]).unwrap();
        if cmd_matches.is_present("benchmark") && pes.len() >= num_threads {
            tapasco_dispatchers = pes.into_iter().map(|pedesc| TapascoDispatcher::new(vec![pedesc]).unwrap()).collect();
        }
        else {
            tapasco_dispatchers = tapasco_runner_phys::create_dispatchers(pes).unwrap();
        }
    }

    struct ThreadEntry {
        handle: std::thread::JoinHandle<()>
    }
    let mut threads: Vec<ThreadEntry> = Vec::with_capacity(num_threads);

    if cmd_matches.is_present("benchmark") {
        let corpus_path = cmd_matches.value_of("in").unwrap().to_string();
        let inputs: Arc<Vec<BytesInput>> = Arc::new(
            std::fs::read_dir(corpus_path).unwrap()
                .map(|res| res.unwrap().path())
                .filter(|path| path.is_file() //Is a file ...
                    && path.file_name()                //... that does not start with "."
                       .and_then(|os_fname| os_fname.to_str())
                       .and_then(|fname| Some(!fname.starts_with("."))).unwrap_or(false))
                .filter_map(|path| {
                    //Open and read the file. Return a LibAFL BytesInput.
                    let mut buf = Vec::new();
                    std::fs::File::open(path).unwrap().read_to_end(&mut buf).unwrap();
                    Some(BytesInput::from(buf))
                }).collect()
        );

        let barrier_threadstart = Arc::new(Barrier::new(num_threads + 1));
        let total_executions = Arc::new(AtomicU64::new(0));
        unsafe { GLOBAL_SIGINT_HOOK.install_nohook(); }
        let pre_start_time = std::time::Instant::now();
        for i in 0..num_threads {
            let thr_dispatchers;
            if tapasco_dispatchers.len() >= num_threads-i {
                thr_dispatchers = vec![tapasco_dispatchers.pop().unwrap()];
            }
            else {
                thr_dispatchers = tapasco_dispatchers.clone();
            }
            let thr_cmd_matches = cmd_matches.clone();
            let thr_barrier_threadstart = barrier_threadstart.clone();
            let thr_total_executions = total_executions.clone();
            let thr_inputs = inputs.clone();
            let mut thr_core: Option<CoreId> = None;
            if cores.len() > i {
                thr_core = Some(cores[i]);
            }
            let handle = std::thread::spawn(move || {
                if let Some(core) = thr_core {
                    core.set_affinity(); //Appears to only affect the current core.
                }
                let stop_signal_arrived = unsafe {&GLOBAL_SIGINT_HOOK.signal_arrived};

                //Run the benchmark thread.
                let res = benchmark(i, 
                    thr_cmd_matches, 
                    thr_dispatchers, 
                    &*thr_inputs, 
                    &*thr_barrier_threadstart, 
                    stop_signal_arrived);
                
                match res {
                    Ok(n_exec) => {
                        thr_total_executions.fetch_add(n_exec, std::sync::atomic::Ordering::SeqCst);
                    }
                    Err(_) => {
                        println!("Thread {} shutting down due to an error.",  i);
                    }
                };

                res.unwrap(); //Panic the thread if an Error occured.
            });
            threads.push(ThreadEntry {handle});

        }
        barrier_threadstart.wait();
        let run_start_time = std::time::Instant::now();
        println!("Benchmark started. Init took {:.3e} seconds", run_start_time.duration_since(pre_start_time).as_secs_f64());
        for thread in threads {
            thread.handle.join().unwrap();
        }
        let elapsed_run = run_start_time.elapsed().as_secs_f64();
        println!("Benchmark finished after {:.3e} seconds.", elapsed_run);
        if elapsed_run > 1e-9 {
            let num_total_executions = total_executions.load(std::sync::atomic::Ordering::SeqCst);
            println!("Total executions per second: {:.2}",
                (num_total_executions as f64) / elapsed_run);
            println!("Executions per thread and second: {:.2}",
                (num_total_executions as f64) / elapsed_run / (num_threads as f64));
        }

        return;
    }

    //Initialize synchronization barriers.
    let barrier_sighookstart = Arc::new(Barrier::new(num_threads + 1));
    //Access to GLOBAL_SIGINT_HOOK requires unsafe, as it is a static mut.
    unsafe {GLOBAL_SIGINT_HOOK.hook_initialized = Some(barrier_sighookstart.clone())};
    let barrier_threadend = Arc::new(Barrier::new(num_threads));
    let once_threadend = Arc::new(Once::new());
    for i in 0..num_threads {
        let thr_dispatchers = tapasco_dispatchers.clone();
        //Create an LlmpClient for the thread and register it with the LlmpBroker.
        let mut llmp_client = LlmpClient::new(
            shmem_provider.clone(),
            broker.llmp_out.out_maps.first().unwrap().clone()
        ).unwrap();
        broker.register_client(llmp_client.sender.out_maps.first().unwrap().clone());
        if i == 0 {
            //Send a dummy message to the broker to ensure that the MultiMonitor calls the print_fn.
            //-> The print_fn sets up a wrapping SIGINT handler so the threads can be terminated safely.
            //   It then waits for barrier_sighookstart, so the fuzzers can only start once the handler is installed.
            let dummy_event: libafl::events::Event<BytesInput> = libafl::events::Event::UpdateUserStats { 
                name: "thread_init".to_string(),
                value: libafl::stats::UserStats::Number(i as u64),
                phantom: PhantomData
            };
            let serialized = postcard::to_allocvec(&dummy_event).unwrap();
            llmp_client.send_buf(LLMP_TAG_EVENT_TO_BOTH, &serialized).unwrap();
        }

        //HACK: Cannot send LlmpClient, because the ShMemProvider stores the reference as a pointer.
        //-> Have to use an unsafe wrapper as a workaround.
        let llmp_client_share = unsafe_send_sync::UnsafeSend::new(std::sync::Mutex::new(Some(llmp_client)));
        //Clone objects to pass to the thread.
        let thr_cmd_matches = cmd_matches.clone();
        let thr_barrier_sighookstart = barrier_sighookstart.clone();
        let thr_barrier_threadend = barrier_threadend.clone();
        let thr_once_threadend = once_threadend.clone();
        let mut thr_core: Option<CoreId> = None;
        if cores.len() > i {
            thr_core = Some(cores[i]);
        }
        let handle = std::thread::spawn(move || {
            if let Some(core) = thr_core {
                core.set_affinity(); //Appears to only affect the current core.
            }
            //Move the LlmpClient out of the Mutex, replacing it with a None value.
            let mut lock = llmp_client_share.lock().unwrap();
            let mut llmp_client_opt = None;
            std::mem::swap(&mut *lock, &mut llmp_client_opt);

            //Wait for hook initialization, and also for other threads to reach this point.
            // (Only the former is required).
            thr_barrier_sighookstart.wait();

            let stop_signal_arrived = unsafe {&GLOBAL_SIGINT_HOOK.signal_arrived};
            //Run the fuzzer on this thread.
            let res = fuzz(i, thr_cmd_matches, llmp_client_opt.unwrap(), thr_dispatchers, stop_signal_arrived);
            //Wait for the other threads to finish/error out.
            thr_barrier_threadend.wait();
            //Notify the main thread through LlmpBroker's signal handler.
            thr_once_threadend.call_once(|| {
                //Access to GLOBAL_SIGINT_HOOK requires unsafe, as it is a static mut.
                // SeqCst ordering for signal_acknowledged, as the generated SIGINT is intended to be passed on to LibAFL's handler.
                unsafe { GLOBAL_SIGINT_HOOK.signal_acknowledged.store(true, std::sync::atomic::Ordering::SeqCst); }
                unsafe { libc::raise(libc::SIGINT); }
            });
            match res {
                Err(_) => {
                    println!("Thread {} shutting down due to an error.",  i);
                }
                _ => ()
            };
            res.unwrap(); //Panic the thread if an Error occured.
        });
        threads.push(ThreadEntry {handle});
    }

    // Monitor passed to the broker to display stats.
    let monitor = MultiMonitor::new(|ln| {
        println!("{}", ln);
        // Hook into LibAFL's signal handler.
        // May be a weird place, but the monitor is the only viable callback from within LlmpBroker after the callback is installed.
        unsafe {
            GLOBAL_SIGINT_HOOK.install();
        }
    });
    //Create the event broker out of the generic LlmpBroker.
    let mut event_broker : LlmpEventBroker<BytesInput,_,_> = LlmpEventBroker::new(broker, monitor).unwrap();
    //Run the broker.
    //The broker loop fn also sets up a SIGINT handler, and uses received signals as a loop end condition.
    // For certain incoming message types, the monitor and consequently its print_fn is called (see above).
    event_broker.broker_loop().unwrap();
    //Join the threads, i.e. allow the threads to stop safely.
    for thread in threads {
        thread.handle.join().unwrap();
    }
}

struct SignalHandlerHook {
    sigaction_old: usize,
    hook_initialized: Option<Arc<Barrier>>,
    signal_arrived: AtomicBool,
    signal_acknowledged: AtomicBool
}

impl SignalHandlerHook {
    // Hooks into the SIGINT handler of LibAFL.
    // Does nothing if the hook is already installed in this object.
    // Panics if the existing handler does not match the way LibAFL 0.7.1 creates it:
    //  See libafl/src/bolts/os/unix_signals.rs: setup_signal_handler
    unsafe fn install(&mut self) {
        if self.sigaction_old != 0 {
            return;
        }
        //Partially based on libafl/src/bolts/os/unix_signals.rs
        let mut sa: sigaction = std::mem::zeroed();
        // Retrieve the old SIGINT action description.
        if libc::sigaction(libc::SIGINT as i32, std::ptr::null(), &mut sa as *mut sigaction) != 0 {
            libc::perror(std::ptr::null());
            panic!("Failed to retrieve SIGINT handler");
        }
        // Make sure the SIGINT action has the expected setup as done by LibAFL.
        const EXPECTED_FLAGS: i32 = libc::SA_NODEFER | libc::SA_SIGINFO | libc::SA_ONSTACK;
        if (sa.sa_flags & EXPECTED_FLAGS) != EXPECTED_FLAGS
            || sa.sa_sigaction == 0 {
            panic!("SIGINT handler by LibAFL not as expected");
        }
        // Store the old handler in self,
        self.sigaction_old = sa.sa_sigaction;
        // and install the hook handler.
        sa.sa_sigaction = handle_hooked_signal as usize;
        if libc::sigaction(libc::SIGINT, &sa as *const sigaction, std::ptr::null_mut()) != 0 {
            libc::perror(std::ptr::null());
            panic!("Failed to register SIGINT hook");
        }
        if let Some(init_barrier_arc) = self.hook_initialized.as_ref() {
            init_barrier_arc.wait();
        }
    }
    unsafe fn install_nohook(&mut self) {
        if self.sigaction_old != 0 {
            return;
        }
        //Partially based on libafl/src/bolts/os/unix_signals.rs
        let mut sa: sigaction = std::mem::zeroed();
        libc::sigemptyset(&mut sa.sa_mask as *mut libc::sigset_t);
        libc::sigaddset(&mut sa.sa_mask as *mut libc::sigset_t, libc::SIGALRM);
        sa.sa_flags = libc::SA_NODEFER | libc::SA_SIGINFO | libc::SA_ONSTACK;
        sa.sa_sigaction = handle_hooked_signal as usize;
        if libc::sigaction(libc::SIGINT, &sa as *const sigaction, std::ptr::null_mut()) != 0 {
            libc::perror(std::ptr::null());
            panic!("Failed to register SIGINT handler");
        }
    }
}

static mut GLOBAL_SIGINT_HOOK: SignalHandlerHook = SignalHandlerHook {
    sigaction_old: 0,
    hook_initialized: None,
    signal_arrived: AtomicBool::new(false),
    signal_acknowledged: AtomicBool::new(false)
};

unsafe fn handle_hooked_signal(sig: std::os::raw::c_int, info: *mut libc::siginfo_t, void: *mut libc::c_void) {
    let _self = &GLOBAL_SIGINT_HOOK;
    _self.signal_arrived.store(true, std::sync::atomic::Ordering::Relaxed);
    // SeqCst ordering, so a thread can set it and then raise SIGINT, expecting it to be passed to the old handler.
    if _self.signal_acknowledged.load(std::sync::atomic::Ordering::SeqCst) && _self.sigaction_old != 0 {
        //Call the original handler.
        let sigaction_old: unsafe extern "C" fn(std::os::raw::c_int, *mut libc::siginfo_t, void: *mut libc::c_void) = std::mem::transmute(_self.sigaction_old);
        sigaction_old(sig, info, void);
    }
}
