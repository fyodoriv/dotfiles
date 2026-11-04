#![forbid(unsafe_code)]
use checkup_run::{Error, Record, ResultKind, Store};
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args_os().skip(1);
    let Some(path) = args.next() else {
        return ExitCode::from(3);
    };
    if args.next().is_some() {
        return ExitCode::from(3);
    }
    let outcome = Store::new(PathBuf::from(path)).and_then(|store| {
        let record = Record::new(
            "2026-01-01T00:00:01Z".into(),
            ResultKind::Degraded,
            vec![("repo".into(), "def1234".into())],
        )?;
        store.record("fixture", record)
    });
    match outcome {
        Ok(_) => ExitCode::SUCCESS,
        Err(Error::Busy) => ExitCode::from(2),
        Err(_) => ExitCode::from(3),
    }
}
