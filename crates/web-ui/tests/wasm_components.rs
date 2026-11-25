#![cfg(target_arch = "wasm32")]

use leptos::prelude::*;
use leptos::task::tick;
use leptos_router::components::Router;
use tradocraft_web_ui::components::tutorial_overlay::TutorialOverlay;
use tradocraft_web_ui::pages::login::LoginPage;
use tradocraft_web_ui::pages::products::ProductsPage;
use tradocraft_web_ui::state::AppContext;
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
