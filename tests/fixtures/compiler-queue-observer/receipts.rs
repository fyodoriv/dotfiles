use serde::de::{Error, MapAccess, Visitor};
use serde::{Deserialize, Deserializer};
use std::collections::BTreeMap;
use std::fmt;

const OUTPUT_CAP: usize = 8192;
const OBSERVATIONS: &str = include_str!("observations.json");

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Verdict {
    Owned,
    Outside,
    Unknown,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Receipt {
    version: u8,
    #[serde(deserialize_with = "unique_outcomes")]
    outcomes: BTreeMap<String, Verdict>,
}

fn unique_outcomes<'de, D>(decoder: D) -> Result<BTreeMap<String, Verdict>, D::Error>
where
    D: Deserializer<'de>,
{
    struct Outcomes;

    impl<'de> Visitor<'de> for Outcomes {
        type Value = BTreeMap<String, Verdict>;

        fn expecting(&self, message: &mut fmt::Formatter<'_>) -> fmt::Result {
            message.write_str("unique outcome keys")
        }

        fn visit_map<A: MapAccess<'de>>(self, mut input: A) -> Result<Self::Value, A::Error> {
            let mut outcomes = BTreeMap::new();
            while let Some((id, verdict)) = input.next_entry()? {
                if outcomes.insert(id, verdict).is_some() {
                    return Err(Error::custom("duplicate outcome key"));
                }
            }
            Ok(outcomes)
        }
    }

    decoder.deserialize_map(Outcomes)
}

fn expected() -> BTreeMap<String, Verdict> {
    (1..=24)
        .map(|i| {
            let verdict = match i {
                1 | 13 | 14 | 23 => Verdict::Owned,
                2 | 15 => Verdict::Outside,
                _ => Verdict::Unknown,
            };
            (format!("C{i:02}"), verdict)
        })
        .collect()
}

fn accepts(stdout: &[u8], stderr: &[u8]) -> bool {
    stdout.len() <= OUTPUT_CAP
        && stderr.is_empty()
        && serde_json::from_slice::<Receipt>(stdout)
            .is_ok_and(|receipt| receipt.version == 2 && receipt.outcomes == expected())
}

const CLEAN: &str = concat!(
    r#"{"version":2,"outcomes":{"C01":"owned","C02":"outside","C03":"unknown","C04":"unknown","#,
    r#""C05":"unknown","C06":"unknown","C07":"unknown","C08":"unknown","C09":"unknown","#,
    r#""C10":"unknown","C11":"unknown","C12":"unknown","C13":"owned","C14":"owned","C15":"outside","#,
    r#""C16":"unknown","C17":"unknown","C18":"unknown","C19":"unknown","C20":"unknown","#,
    r#""C21":"unknown","C22":"unknown","C23":"owned","C24":"unknown"}}"#,
);

#[test]
fn accepts_only_the_expected_receipt() {
    assert!(accepts(CLEAN.as_bytes(), b""));
    for (old, replacement) in [
        (r#""C13":"owned","#, ""),
        (r#""C24":"unknown""#, r#""C24":"owned""#),
        (r#""version":2"#, r#""version":2,"version":2"#),
        (r#""C13":"owned""#, r#""C13":"owned","C13":"owned""#),
    ] {
        assert!(CLEAN.contains(old));
        assert!(!accepts(CLEAN.replace(old, replacement).as_bytes(), b""));
    }
    let escaped = format!(
        r#"{}, "extra":"\u0046IXTURE_PRIVATE_ARGV"}}"#,
        &CLEAN[..CLEAN.len() - 1]
    );
    assert!(!accepts(escaped.as_bytes(), b""));
    assert!(!accepts(CLEAN.as_bytes(), b"FIXTURE_PRIVATE_ARGV"));
    assert!(!accepts(
        [CLEAN.as_bytes(), &[b' '; OUTPUT_CAP + 1]]
            .concat()
            .as_slice(),
        b""
    ));
    assert!(!accepts(CLEAN.as_bytes(), &[b' '; OUTPUT_CAP + 1]));
}

#[test]
fn includes_every_registered_observation() {
    let packet: serde_json::Value =
        serde_json::from_str(OBSERVATIONS).expect("parse sealed inputs");
    let cases = packet["cases"].as_array().expect("fixture cases");
    assert_eq!(cases.len(), 24);
    for (case, id) in cases.iter().zip(expected().keys()) {
        assert!(case["id"].as_str() == Some(id));
    }
    for case in [19, 20, 21] {
        let observation = &cases[case - 1]["observation"];
        let stable = observation["ancestry_before"] == observation["ancestry_after"];
        assert_eq!(stable, case != 19);
    }
}
