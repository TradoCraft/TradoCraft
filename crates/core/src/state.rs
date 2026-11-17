use std::path::PathBuf;
use std::sync::Arc;

use sqlx::PgPool;

use crate::auth::AuthConfig;
use crate::live_events::LiveEvents;

/// Where document templates live and which Typst binary renders them.
#[derive(Debug, Clone)]
pub struct DocumentConfig {
    pub typst_bin: PathBuf,
    pub template_dir: PathBuf,
}

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub auth: Arc<AuthConfig>,
    pub documents: Arc<DocumentConfig>,
    pub live_events: LiveEvents,
}
