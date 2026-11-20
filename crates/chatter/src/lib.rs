//! Chatter on records (ADR 0086): notes, curated change messages, followers and scheduled
//! activities, addressed by `(record_kind, record_id)` without a foreign key to the record.

mod kind;
mod routes;
mod track;

pub use kind::RecordKind;
pub use routes::router;
pub use track::{log, track};
