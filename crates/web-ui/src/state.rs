use leptos::prelude::*;
use tradocraft_api_client::{EnvironmentInfo, WorkerStatus};

use crate::api::{ConnectionMode, Me};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeMode {
    Dark,
    Light,
}

impl ThemeMode {
    pub fn as_attr(self) -> &'static str {
        match self {
            Self::Dark => "dark",
            Self::Light => "light",
        }
    }

    pub fn toggle(self) -> Self {
        match self {
            Self::Dark => Self::Light,
            Self::Light => Self::Dark,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveSession {
    pub connection: ConnectionMode,
    pub me: Me,
}

/// Workspace tab metadata per ADR 0041 (Overview + open detail tabs).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceTab {
    pub id: String,
    pub title: String,
    pub route: String,
    pub subtitle: String,
}

#[derive(Clone, Copy)]
pub struct AppContext {
    pub session: RwSignal<Option<ActiveSession>>,
    pub draft_connection: RwSignal<ConnectionMode>,
    pub theme: RwSignal<ThemeMode>,
    pub tabs: RwSignal<Vec<WorkspaceTab>>,
    pub active_tab: RwSignal<Option<String>>,
    pub environment: RwSignal<Option<EnvironmentInfo>>,
    pub worker_status: RwSignal<Option<WorkerStatus>>,
}

impl AppContext {
    pub fn new() -> Self {
        Self {
            session: RwSignal::new(None),
            draft_connection: RwSignal::new(ConnectionMode::default()),
            theme: RwSignal::new(ThemeMode::Dark),
            tabs: RwSignal::new(Vec::new()),
            active_tab: RwSignal::new(None),
            environment: RwSignal::new(None),
            worker_status: RwSignal::new(None),
        }
    }

    pub fn open_tab(&self, tab: WorkspaceTab) {
        let id = tab.id.clone();
        self.tabs.update(|list| {
            if !list.iter().any(|t| t.id == id) {
                list.push(tab);
            }
        });
        self.active_tab.set(Some(id));
    }

    pub fn close_tab(&self, id: &str) {
        self.tabs.update(|list| list.retain(|t| t.id != id));
        if self.active_tab.get_untracked().as_deref() == Some(id) {
            self.active_tab.set(None);
        }
    }

    pub fn sign_out(&self) {
        self.session.set(None);
        self.tabs.set(Vec::new());
        self.active_tab.set(None);
        self.worker_status.set(None);
    }
}

impl Default for AppContext {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_arch = "wasm32")]
pub fn apply_theme_to_dom(mode: ThemeMode) {
    if let Some(doc) = web_sys::window().and_then(|w| w.document()) {
        if let Some(root) = doc.document_element() {
            let _ = root.set_attribute("data-theme", mode.as_attr());
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub fn apply_theme_to_dom(_mode: ThemeMode) {}
