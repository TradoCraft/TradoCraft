//! To-do items (ADR 0061): private checklists of one user, optionally handed to a colleague of the
//! same company, two levels deep, optionally linked to the record the user was working on.

mod link;
mod routes;

pub use link::TodoLinkKind;
pub use routes::{router, TodoScope};
