#[cfg(all(target_os = "macos", not(feature = "fixture-actions")))]
mod macos {
    use std::ffi::c_int;

    const PRIO_PROCESS: c_int = 0;
    const PRIO_DARWIN_PROCESS: c_int = 4;
    const PRIO_DARWIN_BG: c_int = 0x1000;
    const TASK_OVERRIDE_QOS_POLICY: c_int = 9;
    const LATENCY_QOS_TIER_0: c_int = (0xff << 16) | 1;
    const THROUGHPUT_QOS_TIER_0: c_int = (0xfe << 16) | 1;

    unsafe extern "C" {
        fn setpriority(which: c_int, who: u32, priority: c_int) -> c_int;
        static mach_task_self_: u32;
        fn task_name_for_pid(target: u32, pid: c_int, task: *mut u32) -> c_int;
        fn task_policy_set(task: u32, flavor: c_int, policy: *mut c_int, count: u32) -> c_int;
        fn mach_port_deallocate(task: u32, name: u32) -> c_int;
    }

    pub fn background(pid: u32, enabled: bool) {
        if pid > i32::MAX as u32 { return; }
        // SAFETY: scalar inputs; callers ignore errors just as the shell does.
        let result = unsafe { setpriority(PRIO_DARWIN_PROCESS, pid, if enabled { PRIO_DARWIN_BG } else { 0 }) };
        if enabled || result != 0 { return; }
        let mut port = 0;
        // SAFETY: the output pointer is valid and the PID fits in c_int.
        let task = unsafe { mach_task_self_ };
        if unsafe { task_name_for_pid(task, pid as c_int, &mut port) } != 0 { return; }
        let mut qos = [LATENCY_QOS_TIER_0, THROUGHPUT_QOS_TIER_0];
        // SAFETY: this flavor consumes two integer fields; release the acquired port.
        unsafe {
            task_policy_set(port, TASK_OVERRIDE_QOS_POLICY, qos.as_mut_ptr(), qos.len() as u32);
            mach_port_deallocate(task, port);
        }
    }

    pub fn nice(pid: u32, value: i32) {
        // SAFETY: scalar inputs; callers ignore errors just as the shell does.
        unsafe { setpriority(PRIO_PROCESS, pid, value); }
    }
}

#[cfg(all(target_os = "macos", not(feature = "fixture-actions")))]
pub use macos::{background, nice};

#[cfg(all(not(target_os = "macos"), not(feature = "fixture-actions")))]
pub fn background(_: u32, _: bool) {}
#[cfg(all(not(target_os = "macos"), not(feature = "fixture-actions")))]
pub fn nice(_: u32, _: i32) {}

#[cfg(feature = "fixture-actions")]
mod fixture {
    use std::io::Write;
    fn record(line: &str) {
        let path = std::env::var_os("ACTION_LOG").expect("fixture log required");
        let mut file = std::fs::OpenOptions::new().append(true).open(path)
            .expect("fixture log unavailable");
        writeln!(file, "{line}").expect("fixture log unavailable");
    }
    pub fn background(pid: u32, enabled: bool) {
        if enabled { record(&format!("taskpolicy -b -p {pid}")); }
        else { record(&format!("taskpolicy -B -t 0 -l 0 -p {pid}")); }
    }
    pub fn nice(pid: u32, value: i32) { record(&format!("renice {value} -p {pid}")); }
}
#[cfg(feature = "fixture-actions")]
pub use fixture::{background, nice};
