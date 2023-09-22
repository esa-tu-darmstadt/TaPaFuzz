//Based on files from LibAFL.

use std::time::Duration;
use libafl::{
    bolts::tuples::Named,
    corpus::Testcase,
    events::EventFirer,
    executors::ExitKind,
    feedbacks::Feedback,
    inputs::Input,
    observers::{Observer, ObserversTuple},
    state::HasClientPerfMonitor
};
use serde::{Deserialize, Serialize};


/// Based on LibAFL's TimeObserver (libafl/src/observers/mod.rs).
/// A simple observer intended to be fed with runtime values after each execution.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ManualTimeObserver {
    name: String,
    last_runtime: Option<Duration>,
}

impl ManualTimeObserver {
    /// Creates a new [`ManualTimeObserver`] with the given name.
    #[must_use]
    pub fn new(name: &'static str) -> Self {
        Self {
            name: name.to_string(),
            last_runtime: None,
        }
    }

    /// Gets the runtime for the last execution of this target.
    #[must_use]
    pub fn last_runtime(&self) -> &Option<Duration> {
        &self.last_runtime
    }

    /// Sets the runtime for the last execution of this target.
    pub fn set_last_runtime(&mut self, last_runtime: Option<Duration>) {
        self.last_runtime = last_runtime;
    }
}

impl<I, S> Observer<I, S> for ManualTimeObserver {
    fn pre_exec(&mut self, _state: &mut S, _input: &I) -> Result<(), libafl::Error> {
        Ok(())
    }

    fn post_exec(&mut self, _state: &mut S, _input: &I) -> Result<(), libafl::Error> {
        Ok(())
    }
}

impl Named for ManualTimeObserver {
    fn name(&self) -> &str {
        &self.name
    }
}


/// Based on LibAFL's TimeFeedback (libafl/src/feedbacks/mod.rs).
/// Nop feedback that annotates execution time in the new testcase, if any
/// for this Feedback, the testcase is never interesting (use with an OR)
/// It decides, if the given [`ManualTimeObserver`] value of a run is interesting.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ManualTimeFeedback {
    exec_time: Option<Duration>,
    name: String,
}

impl<I, S> Feedback<I, S> for ManualTimeFeedback
where
    I: Input,
    S: HasClientPerfMonitor,
{
    fn is_interesting<EM, OT>(
        &mut self,
        _state: &mut S,
        _manager: &mut EM,
        _input: &I,
        observers: &OT,
        _exit_kind: &ExitKind,
    ) -> Result<bool, libafl::Error>
    where
        EM: EventFirer<I>,
        OT: ObserversTuple<I, S>,
    {
        // TODO Replace with match_name_type when stable
        let observer = observers.match_name::<ManualTimeObserver>(self.name()).unwrap();
        self.exec_time = *observer.last_runtime();
        Ok(false)
    }

    /// Append to the testcase the generated metadata in case of a new corpus item
    #[inline]
    fn append_metadata(&mut self, _state: &mut S, testcase: &mut Testcase<I>) -> Result<(), libafl::Error> {
        *testcase.exec_time_mut() = self.exec_time;
        self.exec_time = None;
        Ok(())
    }

    /// Discard the stored metadata in case that the testcase is not added to the corpus
    #[inline]
    fn discard_metadata(&mut self, _state: &mut S, _input: &I) -> Result<(), libafl::Error> {
        self.exec_time = None;
        Ok(())
    }
}

impl Named for ManualTimeFeedback {
    #[inline]
    fn name(&self) -> &str {
        self.name.as_str()
    }
}

impl ManualTimeFeedback {
    /// Creates a new [`ManualTimeFeedback`], deciding if the value of a [`ManualTimeObserver`] with the given `name` of a run is interesting.
    #[must_use]
    pub fn new(name: &'static str) -> Self {
        Self {
            exec_time: None,
            name: name.to_string(),
        }
    }

    /// Creates a new [`ManualTimeFeedback`], deciding if the given [`ManualTimeObserver`] value of a run is interesting.
    #[must_use]
    pub fn new_with_observer(observer: &ManualTimeObserver) -> Self {
        Self {
            exec_time: None,
            name: observer.name().to_string(),
        }
    }
}

