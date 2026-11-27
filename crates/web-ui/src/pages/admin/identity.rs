//! Administration, section "Identity providers" (ADR 0052): list, add, edit, test and delete the
//! providers of the installation. Only administrators of the primary company may change them; the
//! server answers 403 to anybody else. Changes that can lock people out are refused with 409 and
//! repeated after confirmation. Mirrors `identity_providers_page.dart` and
//! `identity_provider_dialog.dart`.

use std::collections::BTreeMap;

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use tradocraft_api_client::identity::{
    IdentityProviderInfo, IdentityProviderInput, IdentityProviderTest, IdentityProviderTestResult,
};
use tradocraft_api_client::ApiError;
use uuid::Uuid;

use super::{spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

/// Signature algorithms the server accepts (never HS*, EdDSA or none).
pub(crate) const ALGORITHMS: [&str; 8] = [
    "RS256", "RS384", "RS512", "ES256", "ES384", "PS256", "PS384", "PS512",
];

/// The 409 codes that mean a change could lock somebody out and can be repeated with confirmation.
const LOCKOUT_CODES: [&str; 2] = ["last_identity_provider", "own_identity_provider"];

const READ_ONLY_NOTICE: &str = "You are not an administrator of the installation's primary company, so these settings are not available to you. Ask an administrator of that company.";

/// The ready-made starting points of the form.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Preset {
    Entra,
    Google,
    Generic,
}

impl Preset {
    fn key(self) -> &'static str {
        match self {
            Self::Entra => "entra",
            Self::Google => "google",
            Self::Generic => "generic",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Entra => "Microsoft Entra ID",
            Self::Google => "Google",
            Self::Generic => "Generic OpenID Connect",
        }
    }
}

/// The issuer of a Microsoft Entra ID tenant.
pub(crate) fn entra_issuer(tenant: &str) -> String {
    format!("https://login.microsoftonline.com/{}/v2.0", tenant.trim())
}

/// Whether `d` (lower case, no `@`) looks like a domain name such as `example.com`.
pub(crate) fn looks_like_domain(d: &str) -> bool {
    let labels: Vec<&str> = d.split('.').collect();
    labels.len() >= 2
        && labels.iter().all(|l| {
            !l.is_empty()
                && !l.starts_with('-')
                && !l.ends_with('-')
                && l.chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        })
}

/// Whether `s` is an `https://` URL with a host.
pub(crate) fn is_https_url(s: &str) -> bool {
    let Some(rest) = s.trim().strip_prefix("https://") else {
        return false;
    };
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = host.rsplit('@').next().unwrap_or("");
    let host = host.split(':').next().unwrap_or("");
    !host.is_empty() && !host.contains(char::is_whitespace)
}

/// A domain as typed: trimmed, lower case, without a leading `@`.
fn clean_domain(raw: &str) -> String {
    raw.trim().to_lowercase().replacen('@', "", 1)
}

/// What the provider editor holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct IdpDraft {
    pub name: String,
    pub tenant: String,
    pub issuer: String,
    pub audience: String,
    pub client_id: String,
    pub scopes: String,
    pub email_claim: String,
    pub verified_claim: String,
    pub policy: String,
    pub token_use: String,
    pub domains: Vec<String>,
    pub domain_input: String,
    pub algorithms: Vec<String>,
    pub enabled: bool,
    pub preset: Option<Preset>,
    pub sample: String,
}

impl Default for IdpDraft {
    fn default() -> Self {
        Self {
            name: String::new(),
            tenant: String::new(),
            issuer: String::new(),
            audience: String::new(),
            client_id: String::new(),
            scopes: "openid profile email".into(),
            email_claim: "email".into(),
            verified_claim: "email_verified".into(),
            policy: "require_verified_claim".into(),
            token_use: "id_token".into(),
            domains: Vec::new(),
            domain_input: String::new(),
            algorithms: ALGORITHMS.iter().map(|a| a.to_string()).collect(),
            enabled: true,
            preset: None,
            sample: String::new(),
        }
    }
}

impl IdpDraft {
    fn from_provider(p: &IdentityProviderInfo) -> Self {
        let mut algorithms = p.algorithms.clone();
        if algorithms.is_empty() {
            algorithms = ALGORITHMS.iter().map(|a| a.to_string()).collect();
        }
        Self {
            name: p.name.clone(),
            issuer: p.issuer.clone(),
            audience: p.audience.clone(),
            client_id: p.client_id.clone().unwrap_or_default(),
            scopes: p.scopes.clone(),
            email_claim: p.email_claim.clone(),
            verified_claim: p.verified_claim.clone(),
            policy: p.email_policy.clone(),
            token_use: p.token_use.clone(),
            domains: p.allowed_email_domains.clone(),
            algorithms,
            enabled: p.enabled,
            ..Self::default()
        }
    }

    /// Fills the form from a preset.
    pub fn apply_preset(&mut self, p: Preset) {
        self.preset = Some(p);
        match p {
            Preset::Entra => {
                self.name = "Microsoft Entra ID".into();
                self.issuer = entra_issuer(&self.tenant);
                self.policy = "trust_provider_email".into();
                self.verified_claim = "xms_edov".into();
                self.token_use = "access_token".into();
            }
            Preset::Google => {
                self.name = "Google".into();
                self.issuer = "https://accounts.google.com".into();
                self.token_use = "id_token".into();
                self.policy = "require_verified_claim".into();
                self.verified_claim = "email_verified".into();
            }
            Preset::Generic => {
                self.token_use = "id_token".into();
                self.policy = "require_verified_claim".into();
                self.verified_claim = "email_verified".into();
            }
        }
    }

    /// Adds the typed domain; an error when it does not look like one.
    pub fn add_domain(&mut self) -> Result<(), String> {
        let d = clean_domain(&self.domain_input);
        if d.is_empty() {
            return Ok(());
        }
        if !looks_like_domain(&d) {
            return Err(format!("{d} does not look like a domain."));
        }
        if !self.domains.contains(&d) {
            self.domains.push(d);
        }
        self.domain_input.clear();
        Ok(())
    }

    /// The field errors (keyed `name`, `issuer`, `audience`, `domains`, `algs`); empty when valid.
    pub fn validate(&self) -> BTreeMap<&'static str, String> {
        let mut e = BTreeMap::new();
        if self.name.trim().is_empty() {
            e.insert("name", "A name is required.".to_string());
        }
        if !is_https_url(&self.issuer) {
            e.insert("issuer", "The issuer must be an https:// URL.".to_string());
        }
        if self.audience.trim().is_empty() {
            e.insert("audience", "The audience is required.".to_string());
        }
        let pending = clean_domain(&self.domain_input);
        if !pending.is_empty() && !looks_like_domain(&pending) {
            e.insert("domains", format!("{pending} does not look like a domain."));
        }
        if self.algorithms.is_empty() {
            e.insert("algs", "Select at least one algorithm.".to_string());
        }
        e
    }

    /// The domains, including a typed one that was not confirmed with Enter yet.
    pub fn all_domains(&self) -> Vec<String> {
        let mut out = self.domains.clone();
        let pending = clean_domain(&self.domain_input);
        if !pending.is_empty() && !out.contains(&pending) {
            out.push(pending);
        }
        out
    }

    pub fn to_input(&self, confirm_lockout: bool) -> IdentityProviderInput {
        let opt = |s: &str| {
            let t = s.trim();
            (!t.is_empty()).then(|| t.to_string())
        };
        IdentityProviderInput {
            name: self.name.trim().to_string(),
            issuer: self.issuer.trim().to_string(),
            audience: self.audience.trim().to_string(),
            client_id: opt(&self.client_id),
            scopes: opt(&self.scopes),
            token_use: Some(self.token_use.clone()),
            email_claim: opt(&self.email_claim),
            email_policy: Some(self.policy.clone()),
            verified_claim: opt(&self.verified_claim),
            allowed_email_domains: Some(self.all_domains()),
            algorithms: Some(
                ALGORITHMS
                    .iter()
                    .filter(|a| self.algorithms.iter().any(|x| x == *a))
                    .map(|a| a.to_string())
                    .collect(),
            ),
            enabled: Some(self.enabled),
            confirm_lockout: confirm_lockout.then_some(true),
        }
    }
}

/// The e-mail rule of a provider in words.
pub(crate) fn rule_text(p: &IdentityProviderInfo) -> String {
    let base = match p.email_policy.as_str() {
        "trust_provider_email" => {
            "Links people by e-mail and trusts the provider's address".to_string()
        }
        "subject_only" => "Only existing subjects: no linking by e-mail".to_string(),
        _ => format!(
            "Links people by e-mail when the claim {} is true",
            p.verified_claim
        ),
    };
    if p.email_policy == "subject_only" || p.allowed_email_domains.is_empty() {
        base
    } else {
        format!("{base}, only for {}", p.allowed_email_domains.join(", "))
    }
}

/// The lock-out code of a 409 that can be confirmed, if `err` is one.
pub(crate) fn lockout_code(err: &ApiError) -> Option<&'static str> {
    let code = err.code()?;
    LOCKOUT_CODES.into_iter().find(|c| *c == code)
}

fn lockout_text(code: &str) -> &'static str {
    if code == "last_identity_provider" {
        "This is the last enabled identity provider and the server has no OIDC_ISSUER fallback. If you continue, nobody can sign in until the server's configuration is fixed."
    } else {
        "You are signed in through this provider. If you continue, you will be signed out and cannot sign in again unless another provider accepts you."
    }
}

/// The change waiting for a lock-out confirmation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pending {
    Delete(Uuid),
    Save,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Editor {
    New,
    Edit(Uuid),
}

/// One line of the test report: ok (true), failed (false) or information (none).
fn report_line(ok: Option<bool>, text: String) -> impl IntoView {
    let (mark, label) = match ok {
        Some(true) => ("\u{2714}", "OK"),
        Some(false) => ("\u{2716}", "Failed"),
        None => ("\u{2139}", "Info"),
    };
    let style = if ok == Some(false) {
        "color: var(--error);"
    } else {
        ""
    };
    view! {
        <li style=style>
            <span aria-label=label>{mark}</span>
            " "
            {text}
        </li>
    }
}

fn ok_text(label: &str, ok: Option<bool>) -> String {
    format!(
        "{label}: {}",
        if ok == Some(true) { "OK" } else { "Failed" }
    )
}

fn report_view(r: IdentityProviderTestResult) -> impl IntoView {
    let mut lines: Vec<AnyView> = vec![report_line(
        Some(r.discovery_reachable),
        "Discovery document reachable".into(),
    )
    .into_any()];
    if r.discovery_reachable {
        lines.push(
            report_line(
                Some(r.issuer_match),
                "Issuer matches the discovery document".into(),
            )
            .into_any(),
        );
    }
    if let Some(e) = &r.error {
        lines
            .push(report_line(Some(false), format!("Could not read the provider: {e}")).into_any());
    }
    if r.key_count > 0 {
        lines.push(
            report_line(
                Some(true),
                format!(
                    "{} signing keys, algorithms: {}",
                    r.key_count,
                    r.key_algorithms.join(", ")
                ),
            )
            .into_any(),
        );
    }
    if let Some(c) = &r.claims_supported {
        lines.push(
            report_line(
                None,
                format!("Claims the provider says it supports: {}", c.join(", ")),
            )
            .into_any(),
        );
    }
    let token = r.token.map(|t| {
        let mut tl: Vec<AnyView> = vec![report_line(
            Some(t.signature_ok),
            ok_text("Signature", Some(t.signature_ok)),
        )
        .into_any()];
        if t.audience_ok.is_some() {
            tl.push(report_line(t.audience_ok, ok_text("Audience", t.audience_ok)).into_any());
        }
        if t.expiry_ok.is_some() {
            tl.push(report_line(t.expiry_ok, ok_text("Not expired", t.expiry_ok)).into_any());
        }
        if let Some(reason) = t.reason.clone().filter(|_| !t.valid) {
            tl.push(report_line(Some(false), reason).into_any());
        }
        if let Some(email) = &t.email {
            tl.push(report_line(None, format!("E-mail found: {email}")).into_any());
        } else if t.valid {
            tl.push(
                report_line(Some(false), "No e-mail address found in the token".into()).into_any(),
            );
        }
        if let Some(v) = t.email_verified {
            tl.push(
                report_line(
                    Some(v),
                    if v {
                        "The provider marks the address as verified".into()
                    } else {
                        "The address is not marked as verified".into()
                    },
                )
                .into_any(),
            );
        }
        if let Some(b) = t.binding {
            let text = match b.outcome.as_str() {
                "would_bind" => format!("Would sign in as {}", b.user_email.unwrap_or_default()),
                "existing_subject" => {
                    format!("Already linked to {}", b.user_email.unwrap_or_default())
                }
                _ => format!("Would be refused: {}", b.reason.unwrap_or_default()),
            };
            tl.push(report_line(Some(b.outcome != "refused"), text).into_any());
        }
        view! {
            <h4 style="margin: var(--space-sm) 0 0;">"Sample token"</h4>
            <ul style="list-style: none; padding: 0; margin: 0;">{tl}</ul>
        }
    });
    view! {
        <div class="tc-card" data-target="admin-idp-report" role="status" style="margin-top: var(--space-md);">
            <ul style="list-style: none; padding: 0; margin: 0;">{lines}</ul>
            {token}
            <p class="tc-label" style="margin-bottom: 0;">
                "Testing reads the provider and checks the token only. Nothing is linked or stored."
            </p>
        </div>
    }
}

#[component]
pub fn IdentitySection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();

    let providers = RwSignal::new(Option::<Vec<IdentityProviderInfo>>::None);
    let forbidden = RwSignal::new(false);
    let load_error = RwSignal::new(Option::<String>::None);
    let reload = RwSignal::new(0_u64);

    let editor = RwSignal::new(Option::<Editor>::None);
    let editor_gen = RwSignal::new(0_u64);
    let draft = RwSignal::new(IdpDraft::default());
    let errors = RwSignal::new(BTreeMap::<&'static str, String>::new());
    let save_error = RwSignal::new(Option::<String>::None);
    let busy = RwSignal::new(false);
    let testing = RwSignal::new(false);
    let report = RwSignal::new(Option::<IdentityProviderTestResult>::None);
    let test_error = RwSignal::new(Option::<String>::None);
    let confirm_delete = RwSignal::new(Option::<Uuid>::None);
    let lockout = RwSignal::new(Option::<(Pending, &'static str)>::None);

    let primary = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .filter(|a| a.me.company.is_primary)
                .map(|a| a.me.company.name.clone())
        })
    });

    Effect::new(move |_| {
        let _ = reload.get();
        load_error.set(None);
        spawn_api(
            ctx,
            |c| async move { c.list_identity_providers().await },
            move |res| match res {
                Ok(list) => {
                    if set_alive(providers, Some(list)) {
                        forbidden.set(false);
                    }
                }
                Err(err) if err.status() == Some(403) => {
                    set_alive(forbidden, true);
                }
                Err(err) => {
                    set_alive(load_error, Some(err.user_message()));
                }
            },
        );
    });

    let open = move |target: Editor, d: IdpDraft| {
        draft.set(d);
        errors.set(BTreeMap::new());
        save_error.set(None);
        report.set(None);
        test_error.set(None);
        lockout.set(None);
        editor_gen.update(|g| *g = g.wrapping_add(1));
        editor.set(Some(target));
    };

    let validate = move || {
        let e = draft.with_untracked(IdpDraft::validate);
        let ok = e.is_empty();
        errors.set(e);
        ok
    };

    let do_save = move |confirm: bool| {
        let Some(target) = editor.get_untracked() else {
            return;
        };
        let input = draft.with_untracked(|d| d.to_input(confirm));
        busy.set(true);
        save_error.set(None);
        let gen = editor_gen.get_untracked();
        spawn_api(
            ctx,
            move |c| async move {
                match target {
                    Editor::New => c.create_identity_provider(&input).await,
                    Editor::Edit(id) => c.update_identity_provider(id, &input).await,
                }
            },
            move |res| {
                if !set_alive(busy, false) {
                    return;
                }
                let still_open = editor_gen.get_untracked() == gen;
                match res {
                    Ok(_) => {
                        if still_open {
                            editor.set(None);
                        }
                        fb.ok("Identity provider saved");
                        reload.update(|n| *n += 1);
                    }
                    Err(err) => {
                        if !still_open {
                            fb.fail(err.user_message());
                        } else if let (false, Some(code)) = (confirm, lockout_code(&err)) {
                            lockout.set(Some((Pending::Save, code)));
                        } else if err.status() == Some(403) {
                            save_error.set(Some(READ_ONLY_NOTICE.into()));
                        } else {
                            save_error.set(Some(format!(
                                "The server refused these settings: {}",
                                err.user_message()
                            )));
                        }
                    }
                }
            },
        );
    };

    let do_delete = move |id: Uuid, confirm: bool| {
        confirm_delete.set(None);
        spawn_api(
            ctx,
            move |c| async move { c.delete_identity_provider(id, confirm).await },
            move |res| match res {
                Ok(()) => {
                    if fb.ok("Identity provider deleted") {
                        reload.update(|n| *n += 1);
                    }
                }
                Err(err) => {
                    if let (false, Some(code)) = (confirm, lockout_code(&err)) {
                        set_alive(lockout, Some((Pending::Delete(id), code)));
                    } else {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    let on_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        if validate() {
            do_save(false);
        }
    };

    let on_test = move |_| {
        if !validate() {
            return;
        }
        testing.set(true);
        report.set(None);
        test_error.set(None);
        let body = draft.with_untracked(|d| IdentityProviderTest {
            config: Some(d.to_input(false)),
            id: None,
            sample_token: {
                let t = d.sample.trim();
                (!t.is_empty()).then(|| t.to_string())
            },
        });
        spawn_api(
            ctx,
            move |c| async move { c.test_identity_provider(&body).await },
            move |res| {
                if !set_alive(testing, false) {
                    return;
                }
                match res {
                    Ok(r) => report.set(Some(r)),
                    Err(err) => test_error.set(Some(err.user_message())),
                }
            },
        );
    };

    let field_error = move |key: &'static str| {
        move || {
            errors.with(|e| e.get(key).cloned()).map(|msg| {
                view! { <span class="tc-label" style="color: var(--error);" data-target=format!("admin-idp-error-{key}")>{msg}</span> }
            })
        }
    };

    let text_field = move |id: &'static str,
                           label: &'static str,
                           get: fn(&IdpDraft) -> String,
                           set: fn(&mut IdpDraft, String)| {
        view! {
            <div class="tc-field">
                <label class="tc-label" for=id>{label}</label>
                <input id=id data-target=id class="tc-input" type="text"
                    prop:value=move || draft.with(get)
                    on:input=move |ev| draft.update(|d| set(d, event_target_value(&ev))) />
            </div>
        }
    };

    view! {
        <section data-target="admin-identity" aria-labelledby="admin-identity-title">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h2 id="admin-identity-title" class="tc-page-title" style="font-size: 18px;">"Identity providers"</h2>
                <button type="button" data-target="admin-idp-add" class="tc-btn tc-btn-primary"
                    disabled=move || providers.with(Option::is_none)
                    on:click=move |_| open(Editor::New, IdpDraft::default())>
                    "Add provider"
                </button>
            </div>
            <p style="color: var(--on-surface-variant);">
                "Identity providers decide who can sign in to TradoCraft. People are still created in the ERP; the provider only proves who someone is."
            </p>
            <div class="tc-card" style="margin-bottom: var(--space-md);" data-target="admin-idp-primary">
                {move || match primary.get() {
                    Some(name) => view! {
                        <strong>{format!("Primary company: {name}")}</strong>
                        <p class="tc-label" style="margin-bottom: 0;">"Only administrators of the installation's primary company can change these settings."</p>
                    }.into_any(),
                    None => view! {
                        <p style="margin: 0;">"Only administrators of the installation's primary company can change these settings."</p>
                    }.into_any(),
                }}
            </div>
            <FeedbackView fb prefix="admin-identity" />

            {move || lockout.get().map(|(pending, code)| view! {
                <div class="tc-card" role="alertdialog" aria-labelledby="admin-idp-lockout-title" data-target="admin-idp-lockout" style="margin-bottom: var(--space-md); border-color: var(--error);">
                    <h3 id="admin-idp-lockout-title" style="margin-top: 0;">"This can lock people out"</h3>
                    <p>{lockout_text(code)}</p>
                    <div class="tc-toolbar">
                        <button type="button" class="tc-btn tc-btn-primary" data-target="admin-idp-lockout-confirm"
                            on:click=move |_| {
                                lockout.set(None);
                                match pending {
                                    Pending::Delete(id) => do_delete(id, true),
                                    Pending::Save => do_save(true),
                                }
                            }>
                            "Continue anyway"
                        </button>
                        <button type="button" class="tc-btn" data-target="admin-idp-lockout-cancel" on:click=move |_| lockout.set(None)>"Cancel"</button>
                    </div>
                </div>
            })}

            <Show when=move || editor.with(Option::is_some)>
                <form class="tc-card" data-target="admin-idp-editor" on:submit=on_save style="margin-bottom: var(--space-md);" aria-labelledby="admin-idp-editor-title">
                    <h3 id="admin-idp-editor-title" style="margin-top: 0;">
                        {move || if editor.get() == Some(Editor::New) { "Add identity provider" } else { "Edit identity provider" }}
                    </h3>
                    <Show when=move || editor.get() == Some(Editor::New)>
                        <div class="tc-field">
                            <span class="tc-label" id="admin-idp-preset-label">"Start from"</span>
                            <div class="tc-chip-row" role="group" aria-labelledby="admin-idp-preset-label">
                                {[Preset::Entra, Preset::Google, Preset::Generic].into_iter().map(|p| view! {
                                    <button type="button" class="tc-chip" data-target=format!("admin-idp-preset-{}", p.key())
                                        aria-pressed=move || (draft.with(|d| d.preset) == Some(p)).to_string()
                                        on:click=move |_| draft.update(|d| d.apply_preset(p))>
                                        {p.label()}
                                    </button>
                                }).collect_view()}
                            </div>
                        </div>
                    </Show>
                    <div class="tc-form-grid">
                        <div class="tc-field">
                            <label class="tc-label" for="admin-idp-name">"Name"</label>
                            <input id="admin-idp-name" data-target="admin-idp-name" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.name.clone())
                                on:input=move |ev| draft.update(|d| d.name = event_target_value(&ev)) />
                            {field_error("name")}
                        </div>
                        <Show when=move || draft.with(|d| d.preset == Some(Preset::Entra))>
                            <div class="tc-field">
                                <label class="tc-label" for="admin-idp-tenant">"Tenant id (directory id)"</label>
                                <input id="admin-idp-tenant" data-target="admin-idp-tenant" class="tc-input" type="text"
                                    prop:value=move || draft.with(|d| d.tenant.clone())
                                    on:input=move |ev| draft.update(|d| {
                                        d.tenant = event_target_value(&ev);
                                        d.issuer = entra_issuer(&d.tenant);
                                    }) />
                            </div>
                        </Show>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-idp-issuer">"Issuer URL"</label>
                            <input id="admin-idp-issuer" data-target="admin-idp-issuer" class="tc-input" type="url"
                                prop:value=move || draft.with(|d| d.issuer.clone())
                                on:input=move |ev| draft.update(|d| d.issuer = event_target_value(&ev)) />
                            {field_error("issuer")}
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-idp-audience">"Audience"</label>
                            <input id="admin-idp-audience" data-target="admin-idp-audience" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.audience.clone())
                                on:input=move |ev| draft.update(|d| d.audience = event_target_value(&ev)) />
                            <Show when=move || draft.with(|d| d.preset == Some(Preset::Entra))>
                                <span class="tc-label">"The application (client) id of your Entra app registration"</span>
                            </Show>
                            {field_error("audience")}
                        </div>
                        {text_field("admin-idp-client-id", "Client id (public client, no secret)", |d| d.client_id.clone(), |d, v| d.client_id = v)}
                        {text_field("admin-idp-scopes", "Scopes", |d| d.scopes.clone(), |d, v| d.scopes = v)}
                        {text_field("admin-idp-email-claim", "E-mail claim", |d| d.email_claim.clone(), |d, v| d.email_claim = v)}
                    </div>

                    <fieldset style="border: none; padding: 0; margin: var(--space-md) 0 0;" data-target="admin-idp-token-use">
                        <legend class="tc-label">"Token to send (not used for sign-in yet)"</legend>
                        {[("id_token", "ID token", "Default. Works with Keycloak and most OpenID Connect providers: the audience is the client id."),
                          ("access_token", "Access token", "For Microsoft Entra ID: the access token of your own API (scope api://<client-id>/access_as_user).")]
                            .into_iter().map(|(value, title, body)| view! {
                                <label class="tc-checkbox-row" style="align-items: flex-start;">
                                    <input type="radio" name="admin-idp-token-use" value=value data-target=format!("admin-idp-token-use-{value}")
                                        prop:checked=move || draft.with(|d| d.token_use == value)
                                        on:change=move |_| draft.update(|d| d.token_use = value.to_string()) />
                                    <span><strong>{title}</strong><span class="tc-label" style="display: block;">{body}</span></span>
                                </label>
                            }).collect_view()}
                    </fieldset>

                    <fieldset style="border: none; padding: 0; margin: var(--space-md) 0 0;" data-target="admin-idp-rule">
                        <legend class="tc-label">"How may an e-mail address be used to link a person?"</legend>
                        <Show when=move || draft.with(|d| d.preset == Some(Preset::Entra))>
                            <p class="tc-label">"Entra ID: either trust the provider's e-mail and list your allowed domains (a tenant only holds your own people), or require the claim xms_edov, which Entra only sends when you add it as an optional claim in the app registration."</p>
                        </Show>
                        {[("require_verified_claim", "Require a verified claim (recommended)", "The first sign-in is linked to the ERP user with the same e-mail address only when the token carries a claim, such as email_verified, saying the provider checked that address. Risk: if the provider does not really check addresses, the claim is worthless and a stranger could take over a user."),
                          ("trust_provider_email", "Trust the provider's e-mail address", "The address in the token is accepted without any verification claim. Only use this for a directory where your company controls every address, such as a single Entra tenant, and add allowed domains. Risk: if people can set their own address at the provider, they can sign in as any user."),
                          ("subject_only", "Only existing subjects", "Nobody is linked by e-mail. An administrator links each user to an identity at the provider (Users, Link identity). Safest, but more work.")]
                            .into_iter().map(|(value, title, body)| view! {
                                <label class="tc-checkbox-row" style="align-items: flex-start;">
                                    <input type="radio" name="admin-idp-rule" value=value data-target=format!("admin-idp-rule-{value}")
                                        prop:checked=move || draft.with(|d| d.policy == value)
                                        on:change=move |_| draft.update(|d| d.policy = value.to_string()) />
                                    <span><strong>{title}</strong><span class="tc-label" style="display: block;">{body}</span></span>
                                </label>
                            }).collect_view()}
                    </fieldset>
                    <Show when=move || draft.with(|d| d.policy == "require_verified_claim")>
                        {text_field("admin-idp-verified-claim", "Verified claim", |d| d.verified_claim.clone(), |d, v| d.verified_claim = v)}
                    </Show>
                    <Show when=move || draft.with(|d| d.policy != "subject_only")>
                        <div class="tc-field" style="margin-top: var(--space-sm);">
                            <div class="tc-chip-row" data-target="admin-idp-domains">
                                {move || draft.with(|d| d.domains.clone()).into_iter().map(|dom| {
                                    let dom_rm = dom.clone();
                                    view! {
                                        <span class="tc-chip" data-target=format!("admin-idp-domain-{dom}")>
                                            {dom.clone()}
                                            " "
                                            <button type="button" class="tc-btn tc-btn-ghost tc-btn-sm" aria-label=format!("Remove {dom}")
                                                on:click=move |_| draft.update(|d| d.domains.retain(|x| *x != dom_rm))>
                                                "\u{d7}"
                                            </button>
                                        </span>
                                    }
                                }).collect_view()}
                            </div>
                            <label class="tc-label" for="admin-idp-domain-input">"Allowed e-mail domains"</label>
                            <input id="admin-idp-domain-input" data-target="admin-idp-domain-input" class="tc-input" type="text"
                                aria-describedby="admin-idp-domain-hint"
                                prop:value=move || draft.with(|d| d.domain_input.clone())
                                on:input=move |ev| draft.update(|d| d.domain_input = event_target_value(&ev))
                                on:keydown=move |ev| {
                                    if ev.key() == "Enter" {
                                        ev.prevent_default();
                                        let mut res = Ok(());
                                        draft.update(|d| res = d.add_domain());
                                        errors.update(|e| match res {
                                            Ok(()) => { e.remove("domains"); }
                                            Err(msg) => { e.insert("domains", msg); }
                                        });
                                    }
                                } />
                            <span id="admin-idp-domain-hint" class="tc-label">"Type a domain and press Enter, for example example.com"</span>
                            {field_error("domains")}
                        </div>
                    </Show>
                    <label class="tc-checkbox-row" style="margin-top: var(--space-sm);">
                        <input type="checkbox" data-target="admin-idp-enabled"
                            prop:checked=move || draft.with(|d| d.enabled)
                            on:change=move |ev| {
                                let on = event_target_checked(&ev);
                                draft.update(|d| d.enabled = on);
                            } />
                        "Enabled"
                    </label>
                    <details data-target="admin-idp-advanced" style="margin-top: var(--space-sm);">
                        <summary>"Advanced"</summary>
                        <fieldset style="border: none; padding: 0; margin: var(--space-sm) 0 0;">
                            <legend class="tc-label">"Accepted signature algorithms"</legend>
                            <div class="tc-checkbox-grid">
                                {ALGORITHMS.into_iter().map(|a| view! {
                                    <label class="tc-checkbox-row">
                                        <input type="checkbox" data-target=format!("admin-idp-alg-{a}")
                                            prop:checked=move || draft.with(|d| d.algorithms.iter().any(|x| x == a))
                                            on:change=move |ev| {
                                                let on = event_target_checked(&ev);
                                                draft.update(|d| {
                                                    d.algorithms.retain(|x| x != a);
                                                    if on { d.algorithms.push(a.to_string()); }
                                                });
                                            } />
                                        {a}
                                    </label>
                                }).collect_view()}
                            </div>
                            {field_error("algs")}
                        </fieldset>
                    </details>
                    <div class="tc-field" style="margin-top: var(--space-sm);">
                        <label class="tc-label" for="admin-idp-sample-token">"Sample token (optional)"</label>
                        <textarea id="admin-idp-sample-token" data-target="admin-idp-sample-token" class="tc-input" rows="2"
                            aria-describedby="admin-idp-sample-hint"
                            prop:value=move || draft.with(|d| d.sample.clone())
                            on:input=move |ev| draft.update(|d| d.sample = event_target_value(&ev))></textarea>
                        <span id="admin-idp-sample-hint" class="tc-label">"Paste an access token of a person from this provider to see how it would be handled."</span>
                    </div>
                    <Show when=move || testing.get()>
                        <p class="tc-label" role="status">"Testing..."</p>
                    </Show>
                    {move || test_error.get().map(|msg| view! {
                        <div class="tc-alert-error" role="alert" data-target="admin-idp-test-error" style="margin-top: var(--space-sm);">{msg}</div>
                    })}
                    {move || report.get().map(report_view)}
                    {move || save_error.get().map(|msg| view! {
                        <div class="tc-alert-error" role="alert" data-target="admin-idp-save-error" style="margin-top: var(--space-sm);">{msg}</div>
                    })}
                    <div class="tc-toolbar" style="margin-top: var(--space-md);">
                        <button type="submit" data-target="admin-idp-save" class="tc-btn tc-btn-primary" disabled=move || busy.get()>
                            {move || if busy.get() { "Saving..." } else { "Save" }}
                        </button>
                        <button type="button" data-target="admin-idp-test" class="tc-btn" disabled=move || busy.get() || testing.get() on:click=on_test>
                            "Test"
                        </button>
                        <button type="button" class="tc-btn" disabled=move || busy.get() on:click=move |_| editor.set(None)>"Cancel"</button>
                    </div>
                </form>
            </Show>

            {move || if forbidden.get() {
                view! {
                    <div class="tc-alert-error" role="alert" data-target="admin-idp-readonly">{READ_ONLY_NOTICE}</div>
                }.into_any()
            } else if let Some(msg) = load_error.get() {
                view! {
                    <div class="tc-alert-error" role="alert" data-target="admin-idp-load-error">
                        {msg}
                        " "
                        <button type="button" class="tc-btn tc-btn-sm" data-target="admin-idp-retry" on:click=move |_| reload.update(|n| *n += 1)>"Retry"</button>
                    </div>
                }.into_any()
            } else {
                match providers.get() {
                    None => view! { <p class="tc-label">"Loading identity providers..."</p> }.into_any(),
                    Some(list) if list.is_empty() => view! { <p data-target="admin-idp-none">"No identity providers configured yet."</p> }.into_any(),
                    Some(list) => view! {
                        <ul data-target="admin-idp-list" style="list-style: none; margin: 0; padding: 0;">
                            {list.into_iter().map(|p| {
                                let key = p.id.map(|i| i.to_string()).unwrap_or_else(|| "env".into());
                                let rule = rule_text(&p);
                                let draft_of = IdpDraft::from_provider(&p);
                                let question = format!("Delete identity provider {}? People who sign in through it can no longer do so.", p.name);
                                let id = p.id;
                                view! {
                                    <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=format!("admin-idp-{key}")>
                                        <div style="display: flex; gap: var(--space-sm); flex-wrap: wrap; align-items: flex-start;">
                                            <div style="flex: 1; min-width: 240px;">
                                                <strong>{p.name.clone()}</strong>
                                                <div class="tc-label tc-mono">{p.issuer.clone()}</div>
                                                <div class="tc-label">{rule}</div>
                                                {p.read_only.then(|| view! {
                                                    <div class="tc-label">"Set by the server's OIDC_ISSUER / OIDC_AUDIENCE. It cannot be changed here; it stays available as an emergency fallback."</div>
                                                })}
                                                <div style="margin-top: var(--space-xs);">
                                                    <span class="tc-badge">{if p.enabled { "Enabled" } else { "Disabled" }}</span>
                                                    " "
                                                    <span class="tc-badge">{if p.source == "env" { "Server environment" } else { "Saved in the app" }}</span>
                                                </div>
                                            </div>
                                            {(!p.read_only).then_some(id).flatten().map(|id| {
                                                let name = p.name.clone();
                                                view! {
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-idp-edit-{id}")
                                                        aria-label=format!("Edit {name}")
                                                        on:click=move |_| open(Editor::Edit(id), draft_of.clone())>"Edit"</button>
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-idp-delete-{id}")
                                                        aria-label=format!("Delete {name}")
                                                        on:click=move |_| confirm_delete.set(Some(id))>"Delete"</button>
                                                }
                                            })}
                                        </div>
                                        {id.map(|id| view! {
                                            <Show when=move || confirm_delete.get() == Some(id)>
                                                <div class="tc-toolbar" role="alert" style="margin-top: var(--space-sm);">
                                                    <span>{question.clone()}</span>
                                                    <button type="button" class="tc-btn tc-btn-primary tc-btn-sm" data-target="admin-idp-delete-confirm"
                                                        on:click=move |_| do_delete(id, false)>"Delete"</button>
                                                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| confirm_delete.set(None)>"Cancel"</button>
                                                </div>
                                            </Show>
                                        })}
                                    </li>
                                }
                            }).collect_view()}
                        </ul>
                    }.into_any(),
                }
            }}
        </section>
    }
}

#[cfg(test)]
mod tests {
    use tradocraft_api_client::ErrorBody;

    use super::*;

    #[test]
    fn checks_domains_and_https_urls() {
        assert!(looks_like_domain("example.com"));
        assert!(looks_like_domain("mail.ex-ample.co.uk"));
        assert!(!looks_like_domain("example"));
        assert!(!looks_like_domain("-ex.com"));
        assert!(!looks_like_domain("Example.com"));
        assert!(!looks_like_domain("ex..com"));
        assert!(is_https_url("https://accounts.google.com"));
        assert!(is_https_url(" https://id.example:8443/realms/x "));
        assert!(!is_https_url("http://id.example"));
        assert!(!is_https_url("https://"));
    }

    #[test]
    fn presets_fill_the_form() {
        let mut d = IdpDraft {
            tenant: "abc".into(),
            ..IdpDraft::default()
        };
        d.apply_preset(Preset::Entra);
        assert_eq!(d.issuer, "https://login.microsoftonline.com/abc/v2.0");
        assert_eq!(d.policy, "trust_provider_email");
        assert_eq!(d.token_use, "access_token");
        d.apply_preset(Preset::Google);
        assert_eq!(d.issuer, "https://accounts.google.com");
        assert_eq!(d.verified_claim, "email_verified");
    }

    #[test]
    fn validation_and_pending_domain() {
        let mut d = IdpDraft::default();
        let e = d.validate();
        assert!(e.contains_key("name") && e.contains_key("issuer") && e.contains_key("audience"));
        d.name = "Google".into();
        d.issuer = "https://accounts.google.com".into();
        d.audience = "app".into();
        d.domain_input = "nope".into();
        assert!(d.validate().contains_key("domains"));
        assert!(d.add_domain().is_err());
        d.domain_input = "@Example.COM".into();
        assert!(d.validate().is_empty());
        assert_eq!(d.all_domains(), vec!["example.com"]);
        d.add_domain().unwrap();
        assert_eq!(d.domains, vec!["example.com"]);
        assert!(d.domain_input.is_empty());
        d.algorithms = vec!["ES256".into(), "RS256".into()];
        let input = d.to_input(true);
        assert_eq!(input.algorithms.unwrap(), vec!["RS256", "ES256"]);
        assert_eq!(input.confirm_lockout, Some(true));
        assert_eq!(input.client_id, None);
        d.algorithms.clear();
        assert!(d.validate().contains_key("algs"));
    }

    #[test]
    fn lockout_codes_are_recognised() {
        let err = |code: &str| ApiError::Http {
            status: 409,
            body: Some(ErrorBody {
                error: "conflict".into(),
                code: Some(code.into()),
                message: String::new(),
            }),
            raw_body: String::new(),
        };
        assert_eq!(
            lockout_code(&err("own_identity_provider")),
            Some("own_identity_provider")
        );
        assert_eq!(lockout_code(&err("record_changed")), None);
    }

    #[test]
    fn rule_text_mentions_domains() {
        let p = IdentityProviderInfo {
            id: None,
            source: "env".into(),
            read_only: true,
            name: "Env".into(),
            issuer: "https://id".into(),
            audience: "a".into(),
            client_id: None,
            scopes: String::new(),
            token_use: "id_token".into(),
            algorithms: vec![],
            email_claim: "email".into(),
            email_policy: "trust_provider_email".into(),
            verified_claim: "email_verified".into(),
            allowed_email_domains: vec!["example.com".into()],
            enabled: true,
            created_at: None,
            updated_at: None,
        };
        assert_eq!(
            rule_text(&p),
            "Links people by e-mail and trusts the provider's address, only for example.com"
        );
    }
}
