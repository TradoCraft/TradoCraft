pub mod api;
pub mod components;
pub mod pages;
pub mod state;
pub mod tutorial;

use leptos::prelude::*;
use leptos_router::components::{Redirect, Route, Router, Routes};
use leptos_router::path;

use crate::components::shell::AppShell;
use crate::pages::customers::CustomersPage;
use crate::pages::helpdesk::HelpdeskPage;
use crate::pages::kb::KbPage;
use crate::pages::login::LoginPage;
use crate::pages::orders::OrdersPage;
use crate::pages::placeholder::PlaceholderPage;
use crate::pages::portal::PortalPage;
use crate::pages::products::ProductsPage;
use crate::pages::quotations::QuotationsPage;
use crate::pages::suppliers::SuppliersPage;
use crate::state::{apply_theme_to_dom, AppContext};

#[component]
pub fn App() -> impl IntoView {
    let ctx = AppContext::new();
    provide_context(ctx);

    Effect::new(move |_| {
        apply_theme_to_dom(ctx.theme.get());
    });

    view! {
        <Router base="/app">
            <Routes fallback=|| view! {
                <AppShell>
                    <PlaceholderPage title="Not found" route="404" />
                </AppShell>
            }>
                <Route path=path!("") view=|| view! { <Redirect path="/products" /> } />
                <Route path=path!("/login") view=LoginPage />
                <Route
                    path=path!("/products")
                    view=|| view! {
                        <AppShell>
                            <ProductsPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/customers")
                    view=|| view! {
                        <AppShell>
                            <CustomersPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/price-lists")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Price Lists" route="/price-lists" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/opportunities")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Opportunities" route="/opportunities" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/quotations")
                    view=|| view! {
                        <AppShell>
                            <QuotationsPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/orders")
                    view=|| view! {
                        <AppShell>
                            <OrdersPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/kb")
                    view=|| view! {
                        <AppShell>
                            <KbPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/portal")
                    view=|| view! {
                        <AppShell>
                            <PortalPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/delivery")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Delivery" route="/delivery" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/helpdesk")
                    view=|| view! {
                        <AppShell>
                            <HelpdeskPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/repairs")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Repairs" route="/repairs" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/production")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Production" route="/production" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/stock")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Inventory" route="/stock" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/purchasing")
                    view=|| view! {
                        <AppShell>
                            <SuppliersPage />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/finance")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Finance" route="/finance" />
                        </AppShell>
                    }
                />
                <Route
                    path=path!("/admin")
                    view=|| view! {
                        <AppShell>
                            <PlaceholderPage title="Admin" route="/admin" />
                        </AppShell>
                    }
                />
            </Routes>
        </Router>
    }
}

#[cfg(target_arch = "wasm32")]
pub fn mount_app() {
    console_error_panic_hook::set_once();
    leptos::mount::mount_to_body(App);
}
