//! Administration: one destination with a section per area, each shown only with its permission.
//! Mirrors `app/lib/features/admin/admin_page.dart` (without the site baseline types and the
//! configurator builder shortcut). Every section is deep-linkable as `/admin/<section>`.

pub mod attributes;
pub mod audit;
pub mod company;
pub mod modules;
pub mod users;
pub mod vat;
pub mod zones;

use std::future::Future;

use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use leptos_router::hooks::use_params_map;
use tradocraft_api_client::{ApiError, Client};

use crate::api::{resolve_base_url, ConnectionMode};
use crate::pages::set_alive;
use crate::state::{ActiveSession, AppContext};

/// The sections of the administration, in the order Flutter shows them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdminSection {
    Users,
    Modules,
    Company,
    Vat,
    Zones,
    Attributes,
    Audit,
}

impl AdminSection {
    pub const ALL: [AdminSection; 7] = [
        AdminSection::Users,
        AdminSection::Modules,
        AdminSection::Company,
        AdminSection::Vat,
        AdminSection::Zones,
        AdminSection::Attributes,
        AdminSection::Audit,
    ];

    /// The path segment: `/admin/<key>`.
    pub fn key(self) -> &'static str {
        match self {
            Self::Users => "users",
            Self::Modules => "modules",
            Self::Company => "company",
            Self::Vat => "vat",
            Self::Zones => "zones",
            Self::Attributes => "attributes",
            Self::Audit => "audit",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Users => "Users",
            Self::Modules => "Modules",
            Self::Company => "Company",
            Self::Vat => "VAT rates",
            Self::Zones => "Price zones",
            Self::Attributes => "Attributes",
            Self::Audit => "Audit trail",
        }
    }

    pub fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|s| s.key() == key)
    }

    /// Whether a user holding the permissions `can` answers for may open the section. Mirrors the
    /// gating of the Flutter admin page.
    pub fn allowed(self, can: &impl Fn(&str) -> bool) -> bool {
        match self {
            // User administration needs users.admin; price zones are open to prices.write.
            Self::Users | Self::Modules | Self::Company | Self::Vat => can("users.admin"),
            Self::Zones => can("prices.write"),
            Self::Attributes => can("products.write"),
            Self::Audit => can("audit.view"),
        }
    }
}

/// The sections the permissions allow, in display order.
pub fn allowed_sections(can: impl Fn(&str) -> bool) -> Vec<AdminSection> {
    AdminSection::ALL
        .into_iter()
        .filter(|s| s.allowed(&can))
        .collect()
}

/// The section to show for the requested path segment: the requested one when it is allowed,
/// else the first allowed one; none when nothing is allowed.
pub fn pick_section(requested: Option<&str>, allowed: &[AdminSection]) -> Option<AdminSection> {
    requested
        .and_then(AdminSection::from_key)
        .filter(|s| allowed.contains(s))
        .or_else(|| allowed.first().copied())
}

pub(crate) fn live_client(connection: &ConnectionMode) -> Result<Client, ApiError> {
    match connection {
        ConnectionMode::Live(session) => {
            let mut resolved = session.clone();
            resolved.base_url = resolve_base_url(&session.base_url);
            Ok(Client::from_session(resolved))
        }
        ConnectionMode::MockDemo => Err(ApiError::InvalidConfig(
            "Administration needs a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
                .to_string(),
        )),
    }
}

/// Runs `f` against the live API and hands the result to `done`, unless the signed-in session is
/// gone. `done` runs after the page may have been left: it must start with a [`set_alive`] check.
pub(crate) fn spawn_api<T, F, Fut, D>(ctx: AppContext, f: F, done: D)
where
    T: 'static,
    F: FnOnce(Client) -> Fut + 'static,
    Fut: Future<Output = Result<T, ApiError>> + 'static,
    D: FnOnce(Result<T, ApiError>) + 'static,
{
    let Some(session) = ctx.session.get_untracked() else {
        return;
    };
    spawn_local(async move {
        let res = match live_client(&session.connection) {
            Ok(client) => f(client).await,
            Err(err) => Err(err),
        };
        done(res);
    });
}

/// Reloads `GET /api/v1/me` into the session: module switches and company settings change the
/// permissions and the company the rest of the app sees.
pub(crate) fn refresh_me(ctx: AppContext) {
    spawn_api(
        ctx,
        |c| async move { c.me().await },
        move |res| {
            if let Ok(me) = res {
                ctx.session.try_update(|s| {
                    if let Some(ActiveSession { me: current, .. }) = s.as_mut() {
                        *current = me;
                    }
                });
            }
        },
    );
}

/// The success and error messages a section shows above its content.
#[derive(Clone, Copy)]
pub struct Feedback {
    pub error: RwSignal<Option<String>>,
    pub notice: RwSignal<Option<String>>,
}

impl Default for Feedback {
    fn default() -> Self {
        Self::new()
    }
}

impl Feedback {
    pub fn new() -> Self {
        Self {
            error: RwSignal::new(None),
            notice: RwSignal::new(None),
        }
    }

    /// Shows a success message. Returns false when the section was left meanwhile.
    pub fn ok(self, msg: impl Into<String>) -> bool {
        set_alive(self.error, None) && set_alive(self.notice, Some(msg.into()))
    }

    /// Shows an error. Returns false when the section was left meanwhile.
    pub fn fail(self, msg: impl Into<String>) -> bool {
        set_alive(self.notice, None) && set_alive(self.error, Some(msg.into()))
    }
}

/// Renders a [`Feedback`] as an error alert and a status line, with `data-target`s
/// `<prefix>-error` and `<prefix>-notice`.
#[component]
pub fn FeedbackView(fb: Feedback, prefix: &'static str) -> impl IntoView {
    view! {
        {move || fb.error.get().map(|msg| view! {
            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target=format!("{prefix}-error")>
                {msg}
            </div>
        })}
        {move || fb.notice.get().map(|msg| view! {
            <div class="tc-alert-success" style="margin-bottom: var(--space-md);" role="status" data-target=format!("{prefix}-notice")>
                {msg}
            </div>
        })}
    }
}

/// A file chosen in a browser file input.
#[allow(dead_code)] // `name` is read by the import wizard.
pub(crate) struct PickedFile {
    pub name: String,
    pub bytes: Vec<u8>,
}

/// Reads the file chosen in the `change` event's file input and clears the input so the same
/// file can be picked again. A file over `max_bytes` is refused with `too_big` before it is read.
/// `done` gets an empty error when the dialog was cancelled.
#[cfg(target_arch = "wasm32")]
pub(crate) fn begin_file_read(
    ev: leptos::ev::Event,
    max_bytes: usize,
    too_big: &'static str,
    done: impl FnOnce(Result<PickedFile, String>) + 'static,
) {
    use wasm_bindgen::JsCast;
    let Some(input) = ev
        .target()
        .and_then(|t| t.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        done(Err(String::new()));
        return;
    };
    let Some(file) = input.files().and_then(|list| list.get(0)) else {
        done(Err(String::new()));
        return;
    };
    input.set_value("");
    if file.size() as usize > max_bytes {
        done(Err(too_big.to_string()));
        return;
    }
    let name = file.name();
    spawn_local(async move {
        let result = wasm_bindgen_futures::JsFuture::from(file.array_buffer())
            .await
            .map(|buffer| PickedFile {
                name,
                bytes: js_sys::Uint8Array::new(&buffer).to_vec(),
            })
            .map_err(|_| "The file could not be read.".to_string());
        done(result);
    });
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn begin_file_read(
    _ev: leptos::ev::Event,
    _max_bytes: usize,
    _too_big: &'static str,
    done: impl FnOnce(Result<PickedFile, String>) + 'static,
) {
    done(Err("Choosing files needs the browser build.".to_string()))
}

/// Display name of a role code; unknown codes show as they are.
pub(crate) fn role_name(code: &str) -> &str {
    match code {
        "admin" => "Administrator",
        "sales_manager" => "Sales manager",
        "sales" => "Sales",
        "support" => "Support",
        "production" => "Production",
        "warehouse" => "Warehouse",
        "product_manager" => "Product manager",
        "workshop" => "Workshop",
        "technician" => "Technician",
        "dispatcher" => "Dispatcher",
        "logistics" => "Logistics",
        "viewer" => "Viewer",
        "finance" => "Finance",
        other => other,
    }
}

/// Display name of a module code; unknown codes show as they are.
pub(crate) fn module_name(code: &str) -> &str {
    match code {
        "customers" => "Customers",
        "products" => "Products",
        "sales" => "Sales",
        "engineering" => "Engineering",
        "inventory" => "Inventory",
        "helpdesk" => "Helpdesk",
        "kb" => "Knowledge base",
        "repairs" => "Repairs",
        "field" => "Field service",
        "delivery" => "Delivery",
        "production" => "Production",
        "finance" => "Finance",
        "todo" => "To-do",
        other => other,
    }
}

/// `names` of the module codes, comma separated.
pub(crate) fn module_names(codes: &[String]) -> String {
    codes
        .iter()
        .map(|c| module_name(c))
        .collect::<Vec<_>>()
        .join(", ")
}

/// `1.5 MB`, for the size of a file.
pub(crate) fn file_size(bytes: i64) -> String {
    if bytes < 1024 {
        format!("{bytes} B")
    } else if bytes < 1024 * 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    }
}

#[component]
pub fn AdminPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let params = use_params_map();

    let allowed = Memo::new(move |_| {
        ctx.session.with(|s| match s {
            Some(active) => allowed_sections(|p| active.me.has_permission(p)),
            None => Vec::new(),
        })
    });
    let section = Memo::new(move |_| {
        let requested = params.with(|p| p.get("section"));
        allowed.with(|list| pick_section(requested.as_deref(), list))
    });
    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    view! {
        <div data-target="admin-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Administration"</h1>
                    <p class="tc-page-subtitle">
                        {move || section.get().map(|s| s.label()).unwrap_or("")}
                    </p>
                </div>
            </div>
            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">"Sign in to open the administration."</p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="admin-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <Show
                    when=move || !allowed.with(Vec::is_empty)
                    fallback=|| view! {
                        <div class="tc-card" data-target="admin-no-access">
                            <p style="margin: 0;">"You have no permission for any part of the administration."</p>
                        </div>
                    }
                >
                    <Show when=move || allowed.with(|l| l.len() > 1)>
                        <nav class="tc-inline-tabs" aria-label="Administration sections" data-target="admin-sections" style="margin-bottom: var(--space-md); flex-wrap: wrap;">
                            {move || allowed.get().into_iter().map(|s| {
                                let active = move || section.get() == Some(s);
                                view! {
                                    <A
                                        href=crate::components::shell::app_href(&format!("/admin/{}", s.key()))
                                        attr:class=move || if active() { "tc-inline-tab-btn tc-inline-tab-active" } else { "tc-inline-tab-btn" }
                                        attr:aria-current=move || active().then_some("page")
                                        attr:data-target=format!("admin-section-{}", s.key())
                                    >
                                        {s.label()}
                                    </A>
                                }
                            }).collect_view()}
                        </nav>
                    </Show>
                    {move || match section.get() {
                        Some(AdminSection::Users) => view! { <users::UsersSection /> }.into_any(),
                        Some(AdminSection::Modules) => view! { <modules::ModulesSection /> }.into_any(),
                        Some(AdminSection::Company) => view! { <company::CompanySection /> }.into_any(),
                        Some(AdminSection::Vat) => view! { <vat::VatSection /> }.into_any(),
                        Some(AdminSection::Zones) => view! { <zones::ZonesSection /> }.into_any(),
                        Some(AdminSection::Attributes) => view! { <attributes::AttributesSection /> }.into_any(),
                        Some(AdminSection::Audit) => view! { <audit::AuditSection /> }.into_any(),
                        None => view! { <div></div> }.into_any(),
                    }}
                </Show>
            </Show>
        </div>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sections_follow_the_permissions() {
        assert!(allowed_sections(|_| false).is_empty());
        assert_eq!(
            allowed_sections(|p| p == "users.admin"),
            vec![
                AdminSection::Users,
                AdminSection::Modules,
                AdminSection::Company,
                AdminSection::Vat
            ]
        );
        assert_eq!(
            allowed_sections(|p| p == "prices.write"),
            vec![AdminSection::Zones]
        );
        assert_eq!(
            allowed_sections(|p| p == "products.write"),
            vec![AdminSection::Attributes]
        );
    }

    #[test]
    fn picks_the_requested_section_or_the_first_allowed() {
        let allowed = [AdminSection::Users];
        assert_eq!(
            pick_section(Some("users"), &allowed),
            Some(AdminSection::Users)
        );
        assert_eq!(
            pick_section(Some("nope"), &allowed),
            Some(AdminSection::Users)
        );
        assert_eq!(pick_section(None, &allowed), Some(AdminSection::Users));
        assert_eq!(pick_section(Some("users"), &[]), None);
    }

    #[test]
    fn formats_file_sizes() {
        assert_eq!(file_size(512), "512 B");
        assert_eq!(file_size(1536), "1.5 KB");
        assert_eq!(file_size(3 * 1024 * 1024), "3.0 MB");
    }

    #[test]
    fn names_roles_and_modules() {
        assert_eq!(role_name("sales_manager"), "Sales manager");
        assert_eq!(role_name("custom"), "custom");
        assert_eq!(
            module_names(&["kb".into(), "todo".into()]),
            "Knowledge base, To-do"
        );
    }
}
