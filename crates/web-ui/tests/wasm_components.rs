#![cfg(target_arch = "wasm32")]

use leptos::prelude::*;
use leptos::task::tick;
use leptos_router::components::Router;
use leptos_router::components::Routes;
use tradocraft_api_client::{EnvKind, EnvironmentInfo, WorkerState, WorkerStatus};
use tradocraft_web_ui::api::{Company, ConnectionMode, Me};
use tradocraft_web_ui::components::banners::{EnvironmentBanner, WorkerBanner};
use tradocraft_web_ui::components::shell::AppShell;
use tradocraft_web_ui::components::tutorial_overlay::TutorialOverlay;
use tradocraft_web_ui::pages::admin::AdminPage;
use tradocraft_web_ui::pages::home::HomePage;
use tradocraft_web_ui::pages::login::LoginPage;
use tradocraft_web_ui::pages::products::ProductsPage;
use tradocraft_web_ui::pages::setup::SetupPage;
use tradocraft_web_ui::state::{ActiveSession, AppContext};
use tradocraft_web_ui::tutorial::TutorialState;
use wasm_bindgen::JsCast;
use wasm_bindgen_test::{wasm_bindgen_test, wasm_bindgen_test_configure};
use web_sys::{Element, HtmlElement};

wasm_bindgen_test_configure!(run_in_browser);

struct ContainerGuard(HtmlElement);

impl ContainerGuard {
    fn new() -> Self {
        let document = web_sys::window()
            .expect("browser window")
            .document()
            .expect("browser document");
        let body = document.body().expect("document body");
        let div: HtmlElement = document
            .create_element("div")
            .expect("create test container div")
            .unchecked_into();
        body.append_child(&div)
            .expect("append test container to body");
        Self(div)
    }

    fn el(&self) -> &HtmlElement {
        &self.0
    }

    fn query(&self, selector: &str) -> Option<Element> {
        self.0.query_selector(selector).expect("valid CSS selector")
    }

    fn click(&self, selector: &str) {
        let el: HtmlElement = self
            .query(selector)
            .unwrap_or_else(|| panic!("expected element matching {selector}"))
            .unchecked_into();
        el.click();
    }

    fn text(&self, selector: &str) -> String {
        self.query(selector)
            .unwrap_or_else(|| panic!("expected element matching {selector}"))
            .text_content()
            .unwrap_or_default()
    }
}

impl Drop for ContainerGuard {
    fn drop(&mut self) {
        self.0.remove();
    }
}

#[wasm_bindgen_test]
async fn login_page_renders_auth_modes_and_dev_chips() {
    let guard = ContainerGuard::new();
    let _handle = leptos::mount::mount_to(guard.el().clone(), || {
        provide_context(AppContext::new());
        view! {
            <Router>
                <LoginPage />
            </Router>
        }
    });
    tick().await;

    assert!(guard.query("[data-target=\"login-submit\"]").is_some());
    assert!(guard.query("[data-target=\"login-mode-dev\"]").is_some());
    assert!(guard.query("[data-target=\"login-mode-bearer\"]").is_some());
    assert!(guard.query("[data-target=\"login-mode-mock\"]").is_some());
    assert!(guard.query("[data-target=\"login-demo-admin\"]").is_some());
    assert!(guard.query("[data-target=\"login-demo-sales\"]").is_some());
    assert!(guard.query("[data-target=\"login-demo-viewer\"]").is_some());
}

#[wasm_bindgen_test]
async fn tutorial_overlay_toggles_narrator_and_chapter_map() {
    let guard = ContainerGuard::new();
    let state = RwSignal::new(TutorialState::new());
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! {
            <Router>
                <TutorialOverlay state=state />
            </Router>
        }
    });
    tick().await;

    assert!(guard.query("[data-target=\"tutorial-open\"]").is_some());
    assert!(guard.query("[data-target=\"tutorial-narrator\"]").is_none());

    guard.click("[data-target=\"tutorial-open\"]");
    tick().await;

    assert!(guard.query("[data-target=\"tutorial-narrator\"]").is_some());
    assert!(guard
        .text("[data-target=\"tutorial-narrator\"]")
        .contains("Step 1 / 5"));

    state.update(TutorialState::next_step);
    tick().await;

    assert_eq!(state.get_untracked().step_idx, 1);
    assert!(guard
        .text("[data-target=\"tutorial-narrator\"]")
        .contains("Step 2 / 5"));

    assert!(guard
        .query("[data-target=\"tutorial-chapter-map-modal\"]")
        .is_none());
    state.update(|s| s.show_map = true);
    tick().await;

    assert!(guard
        .query("[data-target=\"tutorial-chapter-map-modal\"]")
        .is_some());
}

#[wasm_bindgen_test]
async fn products_page_unauthenticated_shows_sign_in_link() {
    let guard = ContainerGuard::new();
    let _handle = leptos::mount::mount_to(guard.el().clone(), || {
        provide_context(AppContext::new());
        view! {
            <Router>
                <ProductsPage />
            </Router>
        }
    });
    tick().await;

    assert!(guard.query("[data-target=\"products-go-login\"]").is_some());
}

fn me_with(permissions: &[&str]) -> Me {
    Me {
        user_id: uuid::Uuid::nil(),
        email: "admin@example.com".into(),
        display_name: "Admin".into(),
        company: Company {
            id: uuid::Uuid::nil(),
            name: "Demo".into(),
            vat_number: None,
            street: String::new(),
            postal_code: String::new(),
            city: String::new(),
            country_code: "BE".into(),
            currency: "EUR".into(),
            email: None,
            phone: None,
            iban: None,
            default_language: "en".into(),
            languages: vec!["en".into()],
            is_primary: true,
            quotation_single_line_items: true,
            autosave_minutes: 5,
        },
        roles: vec![],
        permissions: permissions.iter().map(|p| p.to_string()).collect(),
        modules: vec![],
        memberships: vec![],
    }
}

/// Mounts the admin page for a user with `permissions` (offline mode: the sections' requests fail
/// with a message instead of reaching a server).
fn mount_admin(guard: &ContainerGuard, permissions: &'static [&'static str]) -> impl Sized {
    leptos::mount::mount_to(guard.el().clone(), move || {
        let ctx = AppContext::new();
        ctx.session.set(Some(ActiveSession {
            connection: ConnectionMode::MockDemo,
            me: me_with(permissions),
        }));
        provide_context(ctx);
        view! {
            <Router>
                // The test page is served at `/`; the admin page reads its section from the route.
                <Routes fallback=|| "no route matched">
                    <leptos_router::components::Route path=leptos_router::path!("") view=AdminPage/>
                </Routes>
            </Router>
        }
    })
}

#[wasm_bindgen_test]
async fn admin_page_shows_only_the_permitted_sections() {
    let guard = ContainerGuard::new();
    let _handle = mount_admin(&guard, &["users.admin", "audit.view"]);
    tick().await;

    for key in ["users", "modules", "company", "vat", "audit"] {
        assert!(
            guard
                .query(&format!("[data-target=\"admin-section-{key}\"]"))
                .is_some(),
            "section {key} should be offered"
        );
    }
    for key in ["zones", "attributes", "identity", "import"] {
        assert!(
            guard
                .query(&format!("[data-target=\"admin-section-{key}\"]"))
                .is_none(),
            "section {key} should be hidden"
        );
    }
    // Without a section in the path the first permitted one is shown.
    assert!(guard.query("[data-target=\"admin-users\"]").is_some());
}

#[wasm_bindgen_test]
async fn admin_page_without_permissions_says_so() {
    let guard = ContainerGuard::new();
    let _handle = mount_admin(&guard, &["products.read"]);
    tick().await;

    assert!(guard.query("[data-target=\"admin-no-access\"]").is_some());
    assert!(guard.query("[data-target=\"admin-sections\"]").is_none());
}

#[wasm_bindgen_test]
async fn admin_page_with_one_section_shows_no_switcher() {
    let guard = ContainerGuard::new();
    let _handle = mount_admin(&guard, &["prices.write"]);
    tick().await;

    assert!(guard.query("[data-target=\"admin-sections\"]").is_none());
    assert!(guard.query("[data-target=\"admin-zones\"]").is_some());
    // Offline mode: the request fails with a message instead of panicking.
    tick().await;
    assert!(guard
        .query("[data-target=\"admin-zones-load-error\"]")
        .is_some());
}

#[wasm_bindgen_test]
async fn app_shell_gates_navigation_by_session_and_permissions() {
    let guard = ContainerGuard::new();
    let ctx = AppContext::new();
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        provide_context(ctx);
        view! {
            <Router>
                <AppShell>
                    <div>"body"</div>
                </AppShell>
            </Router>
        }
    });
    tick().await;

    // Signed-out visitors only see public destinations.
    assert!(guard.query("[data-target=\"nav-kb\"]").is_some());
    assert!(guard.query("[data-target=\"nav-portal\"]").is_some());
    assert!(guard.query("[data-target=\"nav-home\"]").is_none());
    assert!(guard.query("[data-target=\"nav-products\"]").is_none());
    assert!(guard.query("[data-target=\"nav-admin\"]").is_none());

    ctx.session.set(Some(ActiveSession {
        connection: ConnectionMode::MockDemo,
        me: me_with(&["products.read", "quotations.read"]),
    }));
    tick().await;

    assert!(guard.query("[data-target=\"nav-home\"]").is_some());
    assert!(guard.query("[data-target=\"nav-products\"]").is_some());
    assert!(guard.query("[data-target=\"nav-quotations\"]").is_some());
    assert!(guard.query("[data-target=\"nav-admin\"]").is_none());
    assert!(guard.query("[data-target=\"nav-finance\"]").is_none());
}

#[wasm_bindgen_test]
async fn home_page_renders_only_permitted_cards_and_empty_fallback() {
    let guard = ContainerGuard::new();
    let ctx = AppContext::new();
    ctx.session.set(Some(ActiveSession {
        connection: ConnectionMode::MockDemo,
        me: me_with(&["products.read"]),
    }));
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        provide_context(ctx);
        view! {
            <Router>
                <HomePage />
            </Router>
        }
    });
    tick().await;

    assert!(guard.query("[data-target=\"home-empty\"]").is_some());
    assert!(guard.query("[data-target=\"home-card-todo\"]").is_none());
    assert!(guard
        .query("[data-target=\"home-card-helpdesk\"]")
        .is_none());

    ctx.session.set(Some(ActiveSession {
        connection: ConnectionMode::MockDemo,
        me: me_with(&["todo.use", "quotations.read"]),
    }));
    tick().await;

    assert!(guard.query("[data-target=\"home-empty\"]").is_none());
    assert!(guard.query("[data-target=\"home-card-todo\"]").is_some());
    assert!(guard
        .query("[data-target=\"home-card-quotations\"]")
        .is_some());
    assert!(guard
        .query("[data-target=\"home-card-helpdesk\"]")
        .is_none());
    assert!(guard
        .query("[data-target=\"home-card-purchasing\"]")
        .is_none());
}

#[wasm_bindgen_test]
async fn banners_reflect_environment_and_worker_state() {
    let guard = ContainerGuard::new();
    let ctx = AppContext::new();
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        provide_context(ctx);
        view! {
            <div>
                <EnvironmentBanner />
                <WorkerBanner />
            </div>
        }
    });
    tick().await;

    assert!(guard.query("[data-target=\"env-banner\"]").is_none());
    assert!(guard.query("[data-target=\"worker-banner\"]").is_none());

    ctx.environment.set(Some(EnvironmentInfo {
        name: "tutorial".into(),
        kind: EnvKind::Tutorial,
        db_name: "db".into(),
        version: "0.4.0".into(),
        instance_id: "inst".into(),
    }));
    ctx.worker_status.set(Some(WorkerStatus {
        state: WorkerState::NeverSeen,
        last_beat_at: None,
        age_seconds: None,
        started_at: None,
        interval_seconds: None,
        late_after_seconds: None,
        version: None,
        host: None,
        last_outage: None,
    }));
    tick().await;

    assert!(guard
        .query("[data-target=\"env-banner-tutorial\"]")
        .is_some());
    assert!(guard.query("[data-target=\"worker-banner\"]").is_some());

    ctx.environment.set(Some(EnvironmentInfo {
        name: "prod".into(),
        kind: EnvKind::Live,
        db_name: "db".into(),
        version: "0.4.0".into(),
        instance_id: "inst".into(),
    }));
    ctx.worker_status.set(Some(WorkerStatus {
        state: WorkerState::Running,
        last_beat_at: None,
        age_seconds: None,
        started_at: None,
        interval_seconds: None,
        late_after_seconds: None,
        version: None,
        host: None,
        last_outage: None,
    }));
    tick().await;

    assert!(guard.query("[data-target=\"env-banner\"]").is_none());
    assert!(guard.query("[data-target=\"worker-banner\"]").is_none());
}

#[wasm_bindgen_test]
async fn setup_page_renders_without_panicking() {
    let guard = ContainerGuard::new();
    let _handle = leptos::mount::mount_to(guard.el().clone(), || {
        provide_context(AppContext::new());
        view! {
            <Router>
                <SetupPage />
            </Router>
        }
    });
    tick().await;

    assert!(guard.query("[data-target=\"setup-page\"]").is_some());
}
