//! To-do items (ADR 0061): private checklists of one user, optionally handed to a colleague of the
//! same company, two levels deep, optionally linked to the record the user was working on.

mod link;
mod reminders;
mod routes;

pub use link::TodoLinkKind;
pub use reminders::send_due_reminders;
pub use routes::{router, TodoScope};
