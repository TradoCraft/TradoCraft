#![cfg(target_arch = "wasm32")]

use leptos::prelude::*;
use leptos::task::tick;
use leptos_router::components::Router;
use leptos_router::components::Routes;
use tradocraft_api_client::{EnvKind, EnvironmentInfo, WorkerState, WorkerStatus};
use tradocraft_web_ui::api::{Company, ConnectionMode, Me};
use tradocraft_web_ui::components::banners::{EnvironmentBanner, WorkerBanner};
use tradocraft_web_ui::components::feedback::{Feedback, FeedbackView};
use tradocraft_web_ui::components::inputs::{DecimalInput, SearchPicker};
use tradocraft_web_ui::components::modal::{ConfirmDialog, Modal};
use tradocraft_web_ui::components::shell::AppShell;
use tradocraft_web_ui::components::table::{EntityTable, FilterChip, TableColumn, TableQuery};
use tradocraft_web_ui::components::tabs::{SegmentTab, SegmentedTabs};
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
use web_sys::{
    Element, Event, EventInit, HtmlElement, HtmlInputElement, KeyboardEvent, KeyboardEventInit,
};

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

    fn set_input(&self, selector: &str, value: &str) {
        let input: HtmlInputElement = self
            .query(selector)
            .unwrap_or_else(|| panic!("expected input matching {selector}"))
            .unchecked_into();
        input.set_value(value);
        let init = EventInit::new();
        init.set_bubbles(true);
        let ev = Event::new_with_event_init_dict("input", &init).expect("input event");
        input.dispatch_event(&ev).expect("dispatch input");
    }

    fn dispatch(&self, selector: &str, event_type: &str) {
        let el = self
            .query(selector)
            .unwrap_or_else(|| panic!("expected element matching {selector}"));
        let init = EventInit::new();
        init.set_bubbles(true);
        let ev = Event::new_with_event_init_dict(event_type, &init).expect("dom event");
        el.dispatch_event(&ev).expect("dispatch dom event");
    }

    fn press_key(&self, selector: &str, key: &str) {
        let el = self
            .query(selector)
            .unwrap_or_else(|| panic!("expected element matching {selector}"));
        let init = KeyboardEventInit::new();
        init.set_key(key);
        init.set_bubbles(true);
        let ev =
            KeyboardEvent::new_with_keyboard_event_init_dict("keydown", &init).expect("key event");
        el.dispatch_event(&ev).expect("dispatch key event");
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

#[wasm_bindgen_test]
async fn feedback_view_renders_error_notice_and_dismisses() {
    let guard = ContainerGuard::new();
    let fb = Feedback::new();
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! { <FeedbackView fb prefix="demo" dismissible=true /> }
    });
    tick().await;

    assert!(guard.query("[data-target=\"demo-error\"]").is_none());
    fb.fail("Something went wrong");
    tick().await;
    assert_eq!(
        guard.text("[data-target=\"demo-error\"]"),
        "Something went wrong×"
    );

    guard.click("[data-target=\"demo-error-dismiss\"]");
    tick().await;
    assert!(guard.query("[data-target=\"demo-error\"]").is_none());

    fb.ok("Saved cleanly");
    tick().await;
    assert!(guard.query("[data-target=\"demo-notice\"]").is_some());
}

#[wasm_bindgen_test]
async fn segmented_tabs_hides_single_tab_and_switches_active() {
    let guard = ContainerGuard::new();
    let tabs = RwSignal::new(vec![SegmentTab::new("one", "Only one")]);
    let active = RwSignal::new("one".to_string());
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! {
            <Router>
                <SegmentedTabs
                    tabs=tabs
                    active=active
                    on_select=Callback::new(move |k| active.set(k))
                    target="hub-tabs"
                />
            </Router>
        }
    });
    tick().await;
    assert!(guard.query("[data-target=\"hub-tabs\"]").is_none());

    tabs.set(vec![
        SegmentTab::new("suppliers", "Suppliers"),
        SegmentTab::new("orders", "Purchase orders").with_badge("4"),
    ]);
    active.set("suppliers".to_string());
    tick().await;

    assert!(guard.query("[data-target=\"hub-tabs\"]").is_some());
    guard.click("[data-target=\"hub-tabs-orders\"]");
    tick().await;
    assert_eq!(active.get_untracked(), "orders");
}

#[wasm_bindgen_test]
async fn modal_and_confirm_dialog_open_confirm_and_close() {
    let guard = ContainerGuard::new();
    let open = RwSignal::new(false);
    let confirm_open = RwSignal::new(false);
    let confirmed = RwSignal::new(0_u32);
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! {
            <div>
                <Modal
                    open=open
                    title="Edit item"
                    on_close=Callback::new(move |()| open.set(false))
                    target="edit-modal"
                >
                    <p data-target="modal-body-text">"Body"</p>
                </Modal>
                <ConfirmDialog
                    open=confirm_open
                    title="Delete record"
                    message="This cannot be undone."
                    destructive=true
                    target="del-confirm"
                    on_confirm=Callback::new(move |()| {
                        confirmed.update(|n| *n += 1);
                        confirm_open.set(false);
                    })
                    on_cancel=Callback::new(move |()| confirm_open.set(false))
                />
            </div>
        }
    });
    tick().await;

    open.set(true);
    tick().await;
    assert!(guard.query("[data-target=\"edit-modal\"]").is_some());
    guard.press_key("[data-target=\"edit-modal\"]", "Escape");
    tick().await;
    assert!(guard.query("[data-target=\"edit-modal\"]").is_none());

    confirm_open.set(true);
    tick().await;
    guard.click("[data-target=\"del-confirm-confirm\"]");
    tick().await;
    assert_eq!(confirmed.get_untracked(), 1);
    assert!(guard.query("[data-target=\"del-confirm\"]").is_none());
}

#[wasm_bindgen_test]
async fn decimal_input_evaluates_expression_and_reports_invalid() {
    let guard = ContainerGuard::new();
    let value = RwSignal::new(String::new());
    let committed = RwSignal::new(Option::<String>::None);
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! {
            <DecimalInput
                value=value
                target="price"
                on_commit=Callback::new(move |dec: Option<rust_decimal::Decimal>| {
                    committed.set(dec.map(|d| d.to_string()));
                })
            />
        }
    });
    tick().await;

    guard.set_input("[data-target=\"price-field\"]", "200 + 10%");
    guard.press_key("[data-target=\"price-field\"]", "Enter");
    tick().await;
    assert_eq!(value.get_untracked(), "220");
    assert_eq!(committed.get_untracked().as_deref(), Some("220"));

    guard.set_input("[data-target=\"price-field\"]", "+= 10%");
    guard.dispatch("[data-target=\"price-field\"]", "blur");
    tick().await;
    assert_eq!(value.get_untracked(), "242");

    guard.set_input("[data-target=\"price-field\"]", "10 / 0");
    guard.dispatch("[data-target=\"price-field\"]", "blur");
    tick().await;
    assert!(guard.query("[data-target=\"price-error\"]").is_some());
}

#[wasm_bindgen_test]
async fn search_picker_searches_and_selects_option() {
    #[derive(Clone)]
    struct Item {
        name: String,
        code: String,
    }

    let guard = ContainerGuard::new();
    let selected = RwSignal::new(Option::<Item>::None);
    let search = Callback::new(
        |(query, reply): (String, Callback<Result<Vec<Item>, String>>)| {
            let items = vec![
                Item {
                    name: "Acme HVAC".to_string(),
                    code: "C-001".to_string(),
                },
                Item {
                    name: "Beta Cooling".to_string(),
                    code: "C-002".to_string(),
                },
            ]
            .into_iter()
            .filter(|it| it.name.to_lowercase().contains(&query.to_lowercase()))
            .collect();
            reply.run(Ok(items));
        },
    );

    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! {
            <SearchPicker
                search=search
                selected=selected
                display=Callback::new(|it: Item| it.name)
                subtitle=Callback::new(|it: Item| Some(it.code))
                target="customer-picker"
            />
        }
    });
    tick().await;

    guard.set_input("[data-target=\"customer-picker-input\"]", "acme");
    tick().await;
    assert!(guard
        .query("[data-target=\"customer-picker-menu\"]")
        .is_some());
    guard.click("[data-target=\"customer-picker-option-0\"]");
    tick().await;

    assert_eq!(
        selected.get_untracked().map(|i| i.code).as_deref(),
        Some("C-001")
    );
    guard.click("[data-target=\"customer-picker-clear\"]");
    tick().await;
    assert!(selected.get_untracked().is_none());
}

#[wasm_bindgen_test]
async fn entity_table_searches_sorts_filters_and_paginates() {
    #[derive(Clone)]
    struct Row {
        name: &'static str,
        qty: i32,
    }

    let guard = ContainerGuard::new();
    let query = RwSignal::new(TableQuery::new(2));
    let rows = RwSignal::new(vec![
        Row {
            name: "Pump",
            qty: 3,
        },
        Row {
            name: "Valve",
            qty: 7,
        },
    ]);
    let cols = vec![
        TableColumn::new("name", "Name", |r: Row| view! { {r.name} }.into_any()).sortable("name"),
        TableColumn::new("qty", "Qty", |r: Row| view! { {r.qty} }.into_any())
            .sortable("qty")
            .align_right(),
    ];
    let _handle = leptos::mount::mount_to(guard.el().clone(), move || {
        view! {
            <EntityTable
                columns=cols
                rows=rows
                query=query
                total=Signal::derive(|| 5usize)
                filters=vec![FilterChip::new("active", "Active only")]
                target="demo-table"
            />
        }
    });
    tick().await;

    assert_eq!(
        guard.text("[data-target=\"demo-table-range\"]"),
        "1\u{2013}2 of 5"
    );
    guard.set_input("[data-target=\"demo-table-search\"]", "pump");
    tick().await;
    assert_eq!(query.get_untracked().search, "pump");

    guard.click("[data-target=\"demo-table-filter-active\"]");
    tick().await;
    assert_eq!(
        query.get_untracked().active_filters,
        vec!["active".to_string()]
    );

    guard.click("[data-target=\"demo-table-sort-name\"]");
    tick().await;
    assert_eq!(query.get_untracked().sort_param().as_deref(), Some("name"));

    guard.click("[data-target=\"demo-table-next\"]");
    tick().await;
    assert_eq!(query.get_untracked().offset, 2);
}
