//! Shared inventory comparison; source discovery and the audit remain open.
pub use migration_inventory_core::{validate, Entry, Error, Identity, Kind, State};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_core_rejects_a_missing_embedded_program() {
        let id = Identity {
            path: "bin/tool".into(),
            kind: Kind::Embedded,
            boundary: "python-body".into(),
            source_digest: "a".repeat(40),
        };
        assert!(validate(&[id.clone()], &[]).contains(&Error::MissingEntry(id)));
    }
}
