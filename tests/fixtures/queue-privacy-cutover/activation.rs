#[derive(Clone, Copy)]
struct Cohort {
    complete: bool,
    old_leader: bool,
    old_owner: bool,
    pending_grant: bool,
    waiting_ticket: bool,
    unknown_held: bool,
    old_controller: bool,
}

impl Cohort {
    fn drained(self) -> bool {
        self.complete
            && !self.old_leader
            && !self.old_owner
            && !self.pending_grant
            && !self.waiting_ticket
            && !self.unknown_held
            && !self.old_controller
    }
}

#[derive(Clone, Copy)]
struct Evidence {
    staged_boot: Option<&'static str>,
    current_boot: Option<&'static str>,
    all_entrypoints_current: bool,
    identities_match: bool,
    cohort: Cohort,
    transition_complete: bool,
    receipt_bound: bool,
    dispatch_lease_verified: bool,
    route_covered: bool,
    boot_provenance_bound: bool,
    old_routes_isolated: bool,
    lock_continuous: bool,
}

fn boot_identity(raw: &str) -> Option<[u8; 36]> {
    let mut id: [u8; 36] = raw.as_bytes().try_into().ok()?;
    for (offset, byte) in id.iter_mut().enumerate() {
        if matches!(offset, 8 | 13 | 18 | 23) {
            if *byte != b'-' {
                return None;
            }
        } else if !byte.is_ascii_hexdigit() {
            return None;
        }
        byte.make_ascii_lowercase();
    }
    id.iter()
        .any(|byte| !matches!(byte, b'0' | b'-'))
        .then_some(id)
}

fn permits_activation(evidence: Evidence) -> bool {
    let before = evidence.staged_boot.and_then(boot_identity);
    let after = evidence.current_boot.and_then(boot_identity);
    matches!((before, after), (Some(before), Some(after)) if before != after)
        && evidence.all_entrypoints_current
        && evidence.identities_match
        && evidence.cohort.drained()
        && evidence.transition_complete
        && evidence.receipt_bound
        && evidence.dispatch_lease_verified
        && evidence.route_covered
        && evidence.boot_provenance_bound
        && evidence.old_routes_isolated
        && evidence.lock_continuous
}

const DRAINED: Cohort = Cohort {
    complete: true,
    old_leader: false,
    old_owner: false,
    pending_grant: false,
    waiting_ticket: false,
    unknown_held: false,
    old_controller: false,
};
const VALID: Evidence = Evidence {
    staged_boot: Some("10000000-0000-0000-0000-00000000000a"),
    current_boot: Some("20000000-0000-0000-0000-00000000000b"),
    all_entrypoints_current: true,
    identities_match: true,
    cohort: DRAINED,
    transition_complete: true,
    receipt_bound: true,
    dispatch_lease_verified: true,
    route_covered: true,
    boot_provenance_bound: true,
    old_routes_isolated: true,
    lock_continuous: true,
};

#[test]
fn q01_allows_only_qualified_transition() {
    assert!(permits_activation(VALID));
}

#[test]
fn q02_refuses_same_boot_even_if_empty() {
    for boot in [
        VALID.staged_boot,
        Some("10000000-0000-0000-0000-00000000000A"),
    ] {
        assert!(!permits_activation(Evidence {
            current_boot: boot,
            ..VALID
        }));
    }
}

#[test]
fn q03_refuses_missing_or_malformed_boot_proof() {
    for boot in [
        None,
        Some("bad"),
        Some("20000000-0000-0000-0000-00000000000z"),
    ] {
        assert!(!permits_activation(Evidence {
            current_boot: boot,
            ..VALID
        }));
        assert!(!permits_activation(Evidence {
            staged_boot: boot,
            ..VALID
        }));
    }
}

#[test]
fn q04_refuses_old_entrypoint() {
    assert!(!permits_activation(Evidence {
        all_entrypoints_current: false,
        ..VALID
    }));
}

#[test]
fn q05_refuses_changed_identity() {
    assert!(!permits_activation(Evidence {
        identities_match: false,
        ..VALID
    }));
}

#[test]
fn q06_refuses_live_old_cohort() {
    for cohort in [
        Cohort {
            old_leader: true,
            ..DRAINED
        },
        Cohort {
            old_owner: true,
            ..DRAINED
        },
        Cohort {
            pending_grant: true,
            ..DRAINED
        },
        Cohort {
            waiting_ticket: true,
            ..DRAINED
        },
    ] {
        assert!(!permits_activation(Evidence { cohort, ..VALID }));
    }
}

#[test]
fn q07_refuses_partial_view() {
    assert!(!permits_activation(Evidence {
        cohort: Cohort {
            complete: false,
            ..DRAINED
        },
        ..VALID
    }));
}

#[test]
fn q08_refuses_interrupted_transition() {
    assert!(!permits_activation(Evidence {
        transition_complete: false,
        ..VALID
    }));
}

#[test]
fn q09_refuses_replaced_receipt() {
    assert!(!permits_activation(Evidence {
        receipt_bound: false,
        ..VALID
    }));
}

#[test]
fn q10_refuses_unverified_dispatch_lease() {
    assert!(!permits_activation(Evidence {
        dispatch_lease_verified: false,
        ..VALID
    }));
}

#[test]
fn q11_refuses_uncovered_launch_route() {
    assert!(!permits_activation(Evidence {
        route_covered: false,
        ..VALID
    }));
}

#[test]
fn q12_refuses_nil_boot_id() {
    let nil = Some("00000000-0000-0000-0000-000000000000");
    assert!(!permits_activation(Evidence {
        current_boot: nil,
        ..VALID
    }));
    assert!(!permits_activation(Evidence {
        staged_boot: nil,
        ..VALID
    }));
}

#[test]
fn q13_refuses_unbound_boot_provenance() {
    assert!(!permits_activation(Evidence {
        boot_provenance_bound: false,
        ..VALID
    }));
}

#[test]
fn q14_refuses_old_paths_with_managed_queue_access() {
    assert!(!permits_activation(Evidence {
        old_routes_isolated: false,
        ..VALID
    }));
}

#[test]
fn q15_refuses_lost_dispatch_lock() {
    assert!(!permits_activation(Evidence {
        lock_continuous: false,
        ..VALID
    }));
}

#[test]
fn q16_refuses_an_unknown_held_reservation() {
    assert!(!permits_activation(Evidence {
        cohort: Cohort {
            unknown_held: true,
            ..DRAINED
        },
        ..VALID
    }));
}

#[test]
fn q17_refuses_an_old_controller_without_owner_record() {
    assert!(!permits_activation(Evidence {
        cohort: Cohort {
            old_controller: true,
            ..DRAINED
        },
        ..VALID
    }));
}

fn parse_darwin_boot_bytes(bytes: &[u8]) -> Option<[u8; 36]> {
    let uuid = bytes.strip_suffix(b"\0")?;
    boot_identity(std::str::from_utf8(uuid).ok()?)
}

#[cfg(target_os = "macos")]
fn read_darwin_boot_identity() -> Option<[u8; 36]> {
    use std::ffi::{c_char, c_int, c_void};

    unsafe extern "C" {
        fn sysctlbyname(
            name: *const c_char,
            old_value: *mut c_void,
            old_len: *mut usize,
            new_value: *mut c_void,
            new_len: usize,
        ) -> c_int;
    }

    let mut bytes = [0_u8; 37];
    let mut length = bytes.len();
    // SAFETY: The name is NUL-terminated, length describes the writable
    // buffer, and the null new value requests a read without changing state.
    let result = unsafe {
        sysctlbyname(
            c"kern.bootsessionuuid".as_ptr(),
            bytes.as_mut_ptr().cast(),
            &mut length,
            std::ptr::null_mut(),
            0,
        )
    };
    if result != 0 {
        return None;
    }
    parse_darwin_boot_bytes(bytes.get(..length)?)
}

#[test]
fn darwin_boot_parser_requires_one_canonical_identity_and_terminator() {
    let valid = b"10000000-0000-0000-0000-00000000000A\0";
    assert_eq!(
        parse_darwin_boot_bytes(valid),
        Some(*b"10000000-0000-0000-0000-00000000000a")
    );
    for malformed in [
        &valid[..36],
        b"10000000-0000-0000-0000-00000000000A\0\0",
        b"10000000-0000-0000-0000-00000000000Z\0",
        b"00000000-0000-0000-0000-000000000000\0",
        b"10000000-0000-0000-0000-00000000000A\n",
    ] {
        assert!(parse_darwin_boot_bytes(malformed).is_none());
    }
}

#[cfg(target_os = "macos")]
#[test]
fn darwin_boot_reader_agrees_with_system_utility_without_exposing_identity() {
    let reference = std::process::Command::new("/usr/sbin/sysctl")
        .args(["-n", "kern.bootsessionuuid"])
        .output()
        .expect("system utility is available");
    assert!(
        reference.status.success(),
        "system utility refused boot identity"
    );
    let reference = std::str::from_utf8(&reference.stdout)
        .ok()
        .and_then(|text| text.strip_suffix('\n'))
        .and_then(boot_identity)
        .expect("system utility returned a valid boot identity");
    let first = read_darwin_boot_identity().expect("native boot identity is available");
    let second = read_darwin_boot_identity().expect("repeated boot identity is available");
    assert!(
        first == reference && second == reference,
        "boot identities disagree"
    );
}
