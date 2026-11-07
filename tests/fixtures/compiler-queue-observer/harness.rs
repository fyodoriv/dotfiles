include!("receipts.rs");

#[derive(Debug)]
struct HarnessResult {
    accepted: bool,
    inputs: usize,
    reason: &'static str,
    receipt: Option<Vec<u8>>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SubjectResponse {
    verdict: Verdict,
}

fn run_harness<F>(mut subject: F) -> HarnessResult
where
    F: FnMut(&serde_json::Value) -> Result<Vec<u8>, ()>,
{
    fn refuse(inputs: usize, reason: &'static str) -> HarnessResult {
        HarnessResult {
            accepted: false,
            inputs,
            reason,
            receipt: None,
        }
    }

    let Ok(packet) = serde_json::from_str::<serde_json::Value>(OBSERVATIONS) else {
        return refuse(0, "fixture_invalid");
    };
    let Some(cases) = packet.get("cases").and_then(serde_json::Value::as_array) else {
        return refuse(0, "fixture_invalid");
    };
    let mut outcomes = serde_json::Map::new();
    for (index, case) in cases.iter().enumerate() {
        let Some(id) = case.get("id").and_then(serde_json::Value::as_str) else {
            return refuse(index, "fixture_invalid");
        };
        let Some(observation) = case.get("observation").filter(|value| value.is_object()) else {
            return refuse(index, "fixture_invalid");
        };
        let Ok(bytes) = subject(observation) else {
            return refuse(index + 1, "subject_error");
        };
        if bytes.len() > 1024 {
            return refuse(index + 1, "response_limit");
        }
        let Ok(response) = serde_json::from_slice::<SubjectResponse>(&bytes) else {
            return refuse(index + 1, "invalid_response");
        };
        let verdict = match response.verdict {
            Verdict::Owned => "owned",
            Verdict::Outside => "outside",
            Verdict::Unknown => "unknown",
        };
        if outcomes
            .insert(id.to_owned(), serde_json::Value::String(verdict.into()))
            .is_some()
        {
            return refuse(index + 1, "fixture_invalid");
        }
    }
    let Ok(receipt) = serde_json::to_vec(&serde_json::json!({"version": 2, "outcomes": outcomes}))
    else {
        return refuse(cases.len(), "receipt_invalid");
    };
    let accepted = accepts(&receipt, b"");
    HarnessResult {
        accepted,
        inputs: cases.len(),
        reason: if accepted {
            "accepted"
        } else {
            "verdict_mismatch"
        },
        receipt: Some(receipt),
    }
}

fn valid_response(verdict: Verdict) -> Vec<u8> {
    let name = match verdict {
        Verdict::Owned => "owned",
        Verdict::Outside => "outside",
        Verdict::Unknown => "unknown",
    };
    format!(r#"{{"verdict":"{name}"}}"#).into_bytes()
}

#[test]
fn accepts_the_white_box_control_and_delivers_only_observations() {
    let packet: serde_json::Value = serde_json::from_str(OBSERVATIONS).unwrap();
    let cases = packet["cases"].as_array().unwrap();
    let answers: Vec<_> = expected().values().copied().collect();
    let mut seen = 0;
    let result = run_harness(|observation| {
        assert!(observation.get("id").is_none());
        assert!(observation.get("expected").is_none());
        assert!(observation == &cases[seen]["observation"]);
        let answer = answers[seen];
        seen += 1;
        Ok(valid_response(answer))
    });
    assert!(result.accepted);
    assert_eq!(result.reason, "accepted");
    assert_eq!(seen, 24);
    assert_eq!(result.inputs, 24);
    assert!(result.receipt.is_some());
    for marker in [
        b"FIXTURE_PRIVATE_ARGV".as_slice(),
        b"FIXTURE_PRIVATE_PATH",
        b"FIXTURE_PRIVATE_PROJECT",
    ] {
        assert!(!result
            .receipt
            .as_ref()
            .unwrap()
            .windows(marker.len())
            .any(|part| part == marker));
    }
    assert!(!format!("{result:?}").contains("FIXTURE_PRIVATE"));
}

#[test]
fn rejects_the_twelve_registered_invalid_controls() {
    let controls: Vec<(&str, Result<Vec<u8>, ()>, &str, usize)> = vec![
        (
            "always_unknown",
            Ok(valid_response(Verdict::Unknown)),
            "verdict_mismatch",
            24,
        ),
        (
            "always_owned",
            Ok(valid_response(Verdict::Owned)),
            "verdict_mismatch",
            24,
        ),
        ("invalid_json", Ok(b"{".to_vec()), "invalid_response", 1),
        (
            "duplicate",
            Ok(br#"{"verdict":"owned","verdict":"owned"}"#.to_vec()),
            "invalid_response",
            1,
        ),
        (
            "extra",
            Ok(br#"{"verdict":"owned","extra":true}"#.to_vec()),
            "invalid_response",
            1,
        ),
        (
            "private_marker",
            Ok(br#"{"verdict":"FIXTURE_PRIVATE_ARGV"}"#.to_vec()),
            "invalid_response",
            1,
        ),
        ("callback_error", Err(()), "subject_error", 1),
        ("invalid_utf8", Ok(vec![0xff]), "invalid_response", 1),
        ("empty", Ok(vec![]), "invalid_response", 1),
        ("oversized", Ok(vec![b' '; 1025]), "response_limit", 1),
        (
            "invalid_verdict",
            Ok(br#"{"verdict":"maybe"}"#.to_vec()),
            "invalid_response",
            1,
        ),
        (
            "trailing_data",
            Ok(br#"{"verdict":"owned"} trailing"#.to_vec()),
            "invalid_response",
            1,
        ),
    ];
    assert_eq!(controls.len(), 12);
    for (name, response, reason, inputs) in controls {
        let result = run_harness(|_| response.clone());
        assert!(!result.accepted, "invalid control accepted: {name}");
        assert_eq!(result.reason, reason, "wrong rejection: {name}");
        assert_eq!(result.inputs, inputs, "wrong input count: {name}");
        if let Some(receipt) = &result.receipt {
            assert!(!receipt
                .windows(b"FIXTURE_PRIVATE".len())
                .any(|part| part == b"FIXTURE_PRIVATE"));
        }
        assert!(!format!("{result:?}").contains("FIXTURE_PRIVATE"));
    }
}
