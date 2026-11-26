//! Knowledge base: categories and entries in five languages with simple Markdown, full-text
//! search per language, versions, tags, related entries, images, and reading for staff, for
//! logged-in customers (via the portal crate) and for the public.

mod documents;
mod mail_merge;
pub mod model;
pub mod public;
pub mod reader;
pub mod staff;
pub mod text;
pub mod unsubscribe;

use tradocraft_core::AppState;
use utoipa_axum::router::OpenApiRouter;

pub fn router() -> OpenApiRouter<AppState> {
    staff::router()
        .merge(public::router())
        .merge(documents::router())
        .merge(mail_merge::router())
        .merge(unsubscribe::router())
}
