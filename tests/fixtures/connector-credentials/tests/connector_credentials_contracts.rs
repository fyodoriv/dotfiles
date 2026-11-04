#[allow(dead_code)]
#[path = "../src/connector_credentials.rs"]
mod connector_credentials;

use serde_json::Value;

fn check(id: &str) {
    let registry: Value =
        serde_json::from_str(include_str!("fixtures/connector-contracts.json")).unwrap();
    let case = registry["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == id)
        .unwrap();
    assert_eq!(case["layer"], "pure-contract");
    let actual =
        serde_json::to_value(connector_credentials::Replay::evaluate(&case["input"])).unwrap();
    assert_eq!(
        actual, case["expected"],
        "fixed machine credential contract {id}"
    );
}

macro_rules! cases {
    ($($name:ident),+ $(,)?) => {$(#[test] fn $name() { check(stringify!($name)); })+};
}

cases!(
    c01_stale_github_token,
    c02_stale_gh_token,
    c02_both_conflicting,
    c03_no_environment_tokens,
    c04_ordinary_gh_token,
    c04_ordinary_github_token,
    c04_ordinary_both_precedence,
    c05_missing_executable,
    c05_failed_lookup,
    c05_timeout_lookup,
    c05_empty_token,
    c05_multiline_token,
    c05_control_token,
    c05_oversized_token,
    c06_absent_readonly,
    c06_absent_refresh,
    c06_repeat_matching,
    c07_stale_readonly,
    c07_stale_refresh,
    c08_matching,
    c09_gui_unknown,
    c09_keyring_unknown,
    c10_fixture_covered_remove,
    c10_unqualified_coverage,
    c10_remove_readonly,
    c11_explicit_env_consumer,
    c11_unrelated_gh_token_preserved,
    c12_rejected_write,
    c12_mismatching_recheck,
    c12_unknown_recheck,
    c13_failure_marker_discarded,
    c13_success_fixture_sink_only,
    c14_list_mode,
    c14_override_discovery,
    c14_non_macos,
    c14_unconfigured,
    c14_unknown_policy,
);

#[test]
fn native_authority_and_fixture_registry_stay_separate() {
    assert!(!connector_credentials::native_available());
    assert!(!connector_credentials::native_callback_coverage());
    let registry: Value =
        serde_json::from_str(include_str!("fixtures/connector-contracts.json")).unwrap();
    let cases = registry["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 37);
    let ids: std::collections::BTreeSet<_> =
        cases.iter().map(|v| v["id"].as_str().unwrap()).collect();
    assert_eq!(ids.len(), cases.len());
    assert!(cases.iter().all(|case| case["layer"] == "pure-contract"));
    let groups: std::collections::BTreeSet<_> =
        cases.iter().map(|v| v["group"].as_str().unwrap()).collect();
    assert_eq!(groups.len(), 14);
    assert_eq!(registry["native_qualification"], "unavailable-not-run");
}
