//! Administration, section "Users": the members of the active company with their roles, module
//! switches and status, plus the identity link. Mirrors `users_page.dart`, `user_dialog.dart` and
//! `link_identity_dialog.dart`.

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use tradocraft_api_client::admin::{
    AdminUser, AdminUserCreate, AdminUserUpdate, ModuleInfo, OidcSubjectInput, RoleInfo,
};
use tradocraft_api_client::identity::IdentityProviderInfo;
use uuid::Uuid;

use super::{
    bump, is_current, module_name, module_names, role_name, spawn_api, Feedback, FeedbackView,
};
use crate::pages::set_alive;
use crate::state::AppContext;

/// Which members the list shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ActiveFilter {
    All,
    Active,
    Inactive,
}

impl ActiveFilter {
    fn key(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Active => "active",
            Self::Inactive => "inactive",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::All => "All members",
            Self::Active => "Active members",
            Self::Inactive => "Deactivated members",
        }
    }

    fn from_key(key: &str) -> Self {
        match key {
            "active" => Self::Active,
            "inactive" => Self::Inactive,
            _ => Self::All,
        }
    }
}

/// The endpoint returns every member; search (name or e-mail) and the status filter run here.
pub(crate) fn filter_users(
    users: &[AdminUser],
    query: &str,
    filter: ActiveFilter,
) -> Vec<AdminUser> {
    let needle = query.trim().to_lowercase();
    users
        .iter()
        .filter(|u| match filter {
            ActiveFilter::All => true,
            ActiveFilter::Active => u.active,
            ActiveFilter::Inactive => !u.active,
        })
        .filter(|u| {
            needle.is_empty()
                || u.display_name.to_lowercase().contains(&needle)
                || u.email.to_lowercase().contains(&needle)
        })
        .cloned()
        .collect()
}

/// What the user editor holds.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct UserDraft {
    pub email: String,
    pub name: String,
    pub roles: Vec<String>,
    pub disabled: Vec<String>,
    pub active: bool,
}

impl UserDraft {
    fn from_user(u: &AdminUser) -> Self {
        Self {
            email: u.email.clone(),
            name: u.display_name.clone(),
            roles: u.roles.clone(),
            disabled: u.disabled_modules.clone(),
            active: u.active,
        }
    }

    /// A name, at least one role and, for a new member, an e-mail address (as Flutter checks).
    pub fn valid(&self, creating: bool) -> bool {
        !self.name.trim().is_empty()
            && !self.roles.is_empty()
            && (!creating || self.email.contains('@'))
    }

    /// The chosen roles in catalogue order, so the stored arrays are stable.
    pub fn ordered_roles(&self, catalogue: &[RoleInfo]) -> Vec<String> {
        catalogue
            .iter()
            .filter(|r| self.roles.contains(&r.role))
            .map(|r| r.role.clone())
            .collect()
    }

    fn sorted_disabled(&self) -> Vec<String> {
        let mut out = self.disabled.clone();
        out.sort();
        out.dedup();
        out
    }

    pub fn to_create(&self, catalogue: &[RoleInfo]) -> AdminUserCreate {
        AdminUserCreate {
            email: self.email.trim().to_string(),
            display_name: self.name.trim().to_string(),
            roles: self.ordered_roles(catalogue),
            disabled_modules: self.sorted_disabled(),
        }
    }

    pub fn to_update(&self, catalogue: &[RoleInfo]) -> AdminUserUpdate {
        AdminUserUpdate {
            display_name: self.name.trim().to_string(),
            roles: self.ordered_roles(catalogue),
            disabled_modules: self.sorted_disabled(),
            active: self.active,
        }
    }
}

/// The server refuses dropping your own admin role (409), so that box cannot be unticked.
pub(crate) fn role_locked(is_self: bool, role: &str, selected: bool) -> bool {
    is_self && role == "admin" && selected
}

fn set_member(list: &mut Vec<String>, item: &str, on: bool) {
    if on {
        if !list.iter().any(|x| x == item) {
            list.push(item.to_string());
        }
    } else {
        list.retain(|x| x != item);
    }
}

/// The line under a module switch: switched off company-wide and its requirements.
fn module_hint(m: &ModuleInfo) -> String {
    let mut parts = Vec::new();
    if !m.enabled {
        parts.push("Switched off for the whole company".to_string());
    }
    if !m.requires.is_empty() {
        parts.push(format!("Needs {}", module_names(&m.requires)));
    }
    parts.join(" \u{b7} ")
}

/// Which member the editor is open for.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Editor {
    New,
    Edit(AdminUser),
}

#[component]
pub fn UsersSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();

    let users = RwSignal::new(Vec::<AdminUser>::new());
    let loading = RwSignal::new(false);
    let reload = RwSignal::new(0_u64);
    let fetch_generation = StoredValue::new(0_u64);
    let search = RwSignal::new(String::new());
    let filter = RwSignal::new(ActiveFilter::All);

    let roles = RwSignal::new(Option::<Vec<RoleInfo>>::None);
    let modules = RwSignal::new(Option::<Vec<ModuleInfo>>::None);
    let catalogue_error = RwSignal::new(Option::<String>::None);

    let editor = RwSignal::new(Option::<Editor>::None);
    // Counts editor openings, so a slow save cannot close a newer editor.
    let editor_gen = RwSignal::new(0_u64);
    let draft = RwSignal::new(UserDraft::default());
    let saving = RwSignal::new(false);
    let editor_error = RwSignal::new(Option::<String>::None);

    let link_user = RwSignal::new(Option::<AdminUser>::None);
    let providers = RwSignal::new(Option::<Vec<IdentityProviderInfo>>::None);
    let link_issuer = RwSignal::new(String::new());
    let link_subject = RwSignal::new(String::new());
    let link_error = RwSignal::new(Option::<String>::None);
    let linking = RwSignal::new(false);
    // Counts link-editor openings (and closings): a provider list or a save answer belongs to
    // the opening that asked for it.
    let link_gen = StoredValue::new(0_u64);

    let me_id = Memo::new(move |_| ctx.session.with(|s| s.as_ref().map(|a| a.me.user_id)));
    let can_link = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| a.me.has_permission("identity.admin"))
        })
    });

    Effect::new(move |_| {
        let _ = reload.get();
        let req_gen = fetch_generation
            .try_update_value(|g| {
                *g += 1;
                *g
            })
            .unwrap_or(0);
        loading.set(true);
        spawn_api(
            ctx,
            |c| async move { c.list_admin_users().await },
            move |res| {
                if fetch_generation.try_get_value() != Some(req_gen) || !set_alive(loading, false) {
                    return;
                }
                match res {
                    Ok(list) => users.set(list),
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    });

    let load_catalogue = move || {
        catalogue_error.set(None);
        spawn_api(
            ctx,
            |c| async move {
                let r = c.list_roles().await?;
                let m = c.list_modules().await?;
                Ok((r, m))
            },
            move |res| match res {
                Ok((r, m)) => {
                    if set_alive(roles, Some(r)) {
                        modules.set(Some(m));
                    }
                }
                Err(err) => {
                    set_alive(catalogue_error, Some(err.user_message()));
                }
            },
        );
    };
    load_catalogue();

    let visible = Memo::new(move |_| {
        let q = search.get();
        let f = filter.get();
        users.with(|list| filter_users(list, &q, f))
    });

    let open_editor = move |target: Editor| {
        let d = match &target {
            Editor::New => UserDraft {
                active: true,
                ..UserDraft::default()
            },
            Editor::Edit(u) => UserDraft::from_user(u),
        };
        draft.set(d);
        editor_error.set(None);
        editor_gen.update(|g| *g = g.wrapping_add(1));
        bump(link_gen);
        link_user.set(None);
        editor.set(Some(target));
    };

    let editing_self = Memo::new(move |_| {
        editor.with(|e| match e {
            Some(Editor::Edit(u)) => me_id.get() == Some(u.user_id),
            _ => false,
        })
    });
    let creating = Memo::new(move |_| editor.with(|e| matches!(e, Some(Editor::New))));
    let draft_valid = Memo::new(move |_| draft.with(|d| d.valid(creating.get())));

    let on_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        let Some(target) = editor.get_untracked() else {
            return;
        };
        let Some(catalogue) = roles.get_untracked() else {
            return;
        };
        let d = draft.get_untracked();
        if !d.valid(matches!(target, Editor::New)) {
            editor_error.set(Some(
                "Enter a name, at least one role and, for a new user, an e-mail address."
                    .to_string(),
            ));
            return;
        }
        saving.set(true);
        let save_gen = editor_gen.get_untracked();
        let is_new = matches!(target, Editor::New);
        spawn_api(
            ctx,
            move |c| async move {
                match target {
                    Editor::New => c.create_admin_user(&d.to_create(&catalogue)).await,
                    Editor::Edit(u) => {
                        c.update_admin_user(u.user_id, &d.to_update(&catalogue))
                            .await
                    }
                }
            },
            move |res| {
                if !set_alive(saving, false) {
                    return;
                }
                let still_open = editor_gen.get_untracked() == save_gen;
                match res {
                    Ok(_) => {
                        if still_open {
                            editor.set(None);
                        }
                        fb.ok(if is_new { "User added" } else { "Saved" });
                        reload.update(|n| *n += 1);
                    }
                    Err(err) => {
                        if still_open {
                            editor_error.set(Some(err.user_message()));
                        } else {
                            fb.fail(err.user_message());
                        }
                    }
                }
            },
        );
    };

    let on_invite = move |id: Uuid| {
        saving.set(true);
        spawn_api(
            ctx,
            move |c| async move { c.invite_admin_user(id).await },
            move |res| {
                if !set_alive(saving, false) {
                    return;
                }
                match res {
                    Ok(()) => {
                        fb.ok("Invitation sent");
                    }
                    // Section-level, like the success: it stays visible when the editor closes.
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    let open_link = move |u: AdminUser| {
        editor.set(None);
        link_subject.set(String::new());
        link_issuer.set(String::new());
        link_error.set(None);
        providers.set(None);
        link_user.set(Some(u));
        let gen = bump(link_gen);
        spawn_api(
            ctx,
            |c| async move { c.list_identity_providers().await },
            move |res| {
                if !is_current(link_gen, gen) {
                    return;
                }
                match res {
                    Ok(all) => {
                        let saved: Vec<_> = all.into_iter().filter(|p| !p.read_only).collect();
                        let first = saved.first().map(|p| p.issuer.clone()).unwrap_or_default();
                        if set_alive(providers, Some(saved)) {
                            link_issuer.set(first);
                        }
                    }
                    Err(err) => {
                        set_alive(link_error, Some(err.user_message()));
                    }
                }
            },
        );
    };
    let close_link = move || {
        bump(link_gen);
        link_user.set(None);
    };

    // Saves the link, or removes it when `body` has no subject (the API's way to clear it).
    let submit_link = move |body: OidcSubjectInput| {
        let Some(user) = link_user.get_untracked() else {
            return;
        };
        let removing = body.subject.is_none();
        linking.set(true);
        let gen = link_gen.try_get_value().unwrap_or_default();
        spawn_api(
            ctx,
            move |c| async move { c.set_oidc_subject(user.user_id, &body).await },
            move |res| {
                if !set_alive(linking, false) {
                    return;
                }
                let still_open = is_current(link_gen, gen);
                match res {
                    Ok(()) => {
                        if still_open {
                            close_link();
                        }
                        fb.ok(if removing {
                            "Identity link removed"
                        } else {
                            "Identity link saved"
                        });
                    }
                    Err(err) => {
                        if still_open {
                            link_error.set(Some(err.user_message()));
                        } else {
                            fb.fail(err.user_message());
                        }
                    }
                }
            },
        );
    };
    let link_ready = Memo::new(move |_| {
        !link_issuer.with(String::is_empty) && !link_subject.with(|s| s.trim().is_empty())
    });

    let on_link_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        if !link_ready.get_untracked() {
            return;
        }
        submit_link(OidcSubjectInput {
            issuer: Some(link_issuer.get_untracked()),
            subject: Some(link_subject.get_untracked().trim().to_string()),
        });
    };

    view! {
        <section data-target="admin-users" aria-labelledby="admin-users-title">
            <h2 id="admin-users-title" class="tc-page-title" style="font-size: 18px;">"Users"</h2>
            <div class="tc-toolbar">
                <input
                    data-target="admin-users-search"
                    class="tc-input"
                    style="min-width: 260px;"
                    type="search"
                    placeholder="Search name or e-mail..."
                    aria-label="Search users"
                    prop:value=move || search.get()
                    on:input=move |ev| search.set(event_target_value(&ev))
                />
                <select
                    data-target="admin-users-filter"
                    class="tc-select"
                    aria-label="Member status"
                    on:change=move |ev| filter.set(ActiveFilter::from_key(&event_target_value(&ev)))
                >
                    {[ActiveFilter::All, ActiveFilter::Active, ActiveFilter::Inactive]
                        .into_iter()
                        .map(|f| view! {
                            <option value=f.key() selected=move || filter.get() == f>{f.label()}</option>
                        })
                        .collect_view()}
                </select>
                <button
                    type="button"
                    data-target="admin-users-refresh"
                    class="tc-btn"
                    disabled=move || loading.get()
                    on:click=move |_| reload.update(|n| *n += 1)
                >
                    {move || if loading.get() { "Loading..." } else { "Refresh" }}
                </button>
                <button
                    type="button"
                    data-target="admin-users-new"
                    class="tc-btn tc-btn-primary"
                    on:click=move |_| open_editor(Editor::New)
                >
                    "New user"
                </button>
            </div>

            <FeedbackView fb prefix="admin-users" />

            <Show when=move || editor.with(Option::is_some)>
                <form class="tc-card" data-target="admin-user-editor" on:submit=on_save style="margin-bottom: var(--space-md);" aria-labelledby="admin-user-editor-title">
                    <h3 id="admin-user-editor-title" style="margin-top: 0;">
                        {move || if creating.get() { "New user" } else { "Edit user" }}
                    </h3>
                    {move || catalogue_error.get().map(|msg| view! {
                        <div class="tc-alert-error" role="alert" data-target="admin-user-catalogue-error" style="margin-bottom: var(--space-md);">
                            {msg}
                            " "
                            <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| load_catalogue()>"Retry"</button>
                        </div>
                    })}
                    <div class="tc-form-grid">
                        {move || if creating.get() {
                            view! {
                                <div class="tc-field">
                                    <label class="tc-label" for="admin-user-email">"E-mail"</label>
                                    <input
                                        id="admin-user-email"
                                        data-target="admin-user-email"
                                        class="tc-input"
                                        type="email"
                                        autocomplete="off"
                                        prop:value=move || draft.with(|d| d.email.clone())
                                        on:input=move |ev| draft.update(|d| d.email = event_target_value(&ev))
                                    />
                                </div>
                            }.into_any()
                        } else {
                            view! {
                                <div class="tc-field">
                                    <span class="tc-label">"E-mail"</span>
                                    <span data-target="admin-user-email-text">{move || draft.with(|d| d.email.clone())}</span>
                                </div>
                            }.into_any()
                        }}
                        <div class="tc-field">
                            <label class="tc-label" for="admin-user-name">"Name"</label>
                            <input
                                id="admin-user-name"
                                data-target="admin-user-name"
                                class="tc-input"
                                type="text"
                                prop:value=move || draft.with(|d| d.name.clone())
                                on:input=move |ev| draft.update(|d| d.name = event_target_value(&ev))
                            />
                        </div>
                    </div>

                    <fieldset style="border: none; padding: 0; margin: var(--space-md) 0 0;" data-target="admin-user-roles">
                        <legend class="tc-label">"Roles"</legend>
                        {move || match roles.get() {
                            None => view! { <p class="tc-label">"Loading roles..."</p> }.into_any(),
                            Some(list) => view! {
                                <div class="tc-checkbox-grid">
                                    {list.into_iter().map(|r| {
                                        let role = r.role.clone();
                                        let role_check = role.clone();
                                        let role_lock = role.clone();
                                        let role_set = role.clone();
                                        let checked = move || draft.with(|d| d.roles.contains(&role_check));
                                        let locked = move || role_locked(editing_self.get(), &role_lock, draft.with(|d| d.roles.contains(&role_lock)));
                                        view! {
                                            <label class="tc-checkbox-row" title=format!("{} permissions", r.permissions.len())>
                                                <input
                                                    type="checkbox"
                                                    data-target=format!("admin-user-role-{role}")
                                                    prop:checked=checked
                                                    disabled=locked
                                                    on:change=move |ev| {
                                                        let on = event_target_checked(&ev);
                                                        draft.update(|d| set_member(&mut d.roles, &role_set, on));
                                                    }
                                                />
                                                {role_name(&role).to_string()}
                                            </label>
                                        }
                                    }).collect_view()}
                                </div>
                            }.into_any(),
                        }}
                        <Show when=move || editing_self.get()>
                            <p class="tc-label" data-target="admin-user-own-admin">"You cannot remove your own admin role."</p>
                        </Show>
                    </fieldset>

                    <fieldset style="border: none; padding: 0; margin: var(--space-md) 0 0;" data-target="admin-user-modules">
                        <legend class="tc-label">"Modules"</legend>
                        <p class="tc-label" style="margin-top: 0;">
                            "Switch modules off for this person. Modules the company has switched off cannot be turned back on here."
                        </p>
                        {move || match modules.get() {
                            None => view! { <p class="tc-label">"Loading modules..."</p> }.into_any(),
                            Some(list) => view! {
                                <div class="tc-checkbox-grid">
                                    {list.into_iter().map(|m| {
                                        let code = m.code.clone();
                                        let code_check = code.clone();
                                        let code_set = code.clone();
                                        let company_on = m.enabled;
                                        let hint = module_hint(&m);
                                        let hint_id = format!("admin-user-module-hint-{code}");
                                        view! {
                                            <label class="tc-checkbox-row">
                                                <input
                                                    type="checkbox"
                                                    data-target=format!("admin-user-module-{code}")
                                                    aria-describedby=hint_id.clone()
                                                    prop:checked=move || company_on && draft.with(|d| !d.disabled.contains(&code_check))
                                                    disabled=!company_on
                                                    on:change=move |ev| {
                                                        let on = event_target_checked(&ev);
                                                        draft.update(|d| set_member(&mut d.disabled, &code_set, !on));
                                                    }
                                                />
                                                <span>
                                                    {module_name(&code).to_string()}
                                                    <span id=hint_id class="tc-label" style="display: block;">{hint}</span>
                                                </span>
                                            </label>
                                        }
                                    }).collect_view()}
                                </div>
                            }.into_any(),
                        }}
                    </fieldset>

                    {move || match editor.get() {
                        Some(Editor::Edit(u)) => {
                            let id = u.user_id;
                            let invite = !u.has_signed_in && u.active;
                            view! {
                                <div style="margin-top: var(--space-md);">
                                    <label class="tc-checkbox-row">
                                        <input
                                            type="checkbox"
                                            data-target="admin-user-active"
                                            aria-describedby="admin-user-active-help"
                                            prop:checked=move || draft.with(|d| d.active)
                                            disabled=move || editing_self.get()
                                            on:change=move |ev| {
                                                let on = event_target_checked(&ev);
                                                draft.update(|d| d.active = on);
                                            }
                                        />
                                        "Active"
                                    </label>
                                    <p id="admin-user-active-help" class="tc-label" style="margin-top: 0;">
                                        {move || if editing_self.get() {
                                            "You cannot deactivate yourself."
                                        } else {
                                            "A deactivated member can no longer sign in to this company."
                                        }}
                                    </p>
                                    {invite.then(|| view! {
                                        <button
                                            type="button"
                                            data-target="admin-user-invite"
                                            class="tc-btn tc-btn-sm"
                                            disabled=move || saving.get()
                                            on:click=move |_| on_invite(id)
                                        >
                                            "Send invitation again"
                                        </button>
                                    })}
                                </div>
                            }.into_any()
                        }
                        _ => view! { <div></div> }.into_any(),
                    }}

                    {move || editor_error.get().map(|msg| view! {
                        <div class="tc-alert-error" style="margin-top: var(--space-md);" role="alert" data-target="admin-user-editor-error">
                            {msg}
                        </div>
                    })}
                    <div class="tc-toolbar" style="margin-top: var(--space-md);">
                        <button
                            type="submit"
                            data-target="admin-user-save"
                            class="tc-btn tc-btn-primary"
                            disabled=move || saving.get() || roles.with(Option::is_none) || !draft_valid.get()
                        >
                            {move || if saving.get() { "Saving..." } else { "Save" }}
                        </button>
                        <button type="button" data-target="admin-user-cancel" class="tc-btn" on:click=move |_| editor.set(None)>
                            "Cancel"
                        </button>
                    </div>
                </form>
            </Show>

            {move || link_user.get().map(|u| {
                let title = format!("Link identity of {}", u.display_name);
                view! {
                    <form class="tc-card" data-target="admin-link-editor" on:submit=on_link_save style="margin-bottom: var(--space-md);" aria-labelledby="admin-link-title">
                        <h3 id="admin-link-title" style="margin-top: 0;">{title}</h3>
                        <p style="color: var(--on-surface-variant);">
                            "Only needed for providers that use the rule 'Only existing subjects'. Choose the provider and enter the subject (the sub claim) this person has there."
                        </p>
                        {move || match providers.get() {
                            None => view! { <p class="tc-label">"Loading providers..."</p> }.into_any(),
                            Some(list) if list.is_empty() => view! {
                                <p data-target="admin-link-no-providers">"No identity providers are saved in the app yet."</p>
                            }.into_any(),
                            Some(list) => view! {
                                <div class="tc-form-grid">
                                    <div class="tc-field">
                                        <label class="tc-label" for="admin-link-provider">"Provider"</label>
                                        <select
                                            id="admin-link-provider"
                                            data-target="admin-link-provider"
                                            class="tc-select"
                                            on:change=move |ev| link_issuer.set(event_target_value(&ev))
                                        >
                                            {list.into_iter().map(|p| {
                                                let issuer = p.issuer.clone();
                                                let issuer_sel = issuer.clone();
                                                view! {
                                                    <option value=issuer selected=move || link_issuer.get() == issuer_sel>{p.name}</option>
                                                }
                                            }).collect_view()}
                                        </select>
                                    </div>
                                    <div class="tc-field">
                                        <label class="tc-label" for="admin-link-subject">"Subject (sub)"</label>
                                        <input
                                            id="admin-link-subject"
                                            data-target="admin-link-subject"
                                            class="tc-input"
                                            type="text"
                                            prop:value=move || link_subject.get()
                                            on:input=move |ev| link_subject.set(event_target_value(&ev))
                                        />
                                    </div>
                                </div>
                            }.into_any(),
                        }}
                        {move || link_error.get().map(|msg| view! {
                            <div class="tc-alert-error" style="margin-top: var(--space-md);" role="alert" data-target="admin-link-error">{msg}</div>
                        })}
                        <div class="tc-toolbar" style="margin-top: var(--space-md);">
                            <button type="submit" data-target="admin-link-save" class="tc-btn tc-btn-primary" disabled=move || linking.get() || !link_ready.get()>
                                "Save"
                            </button>
                            <button
                                type="button"
                                data-target="admin-link-remove"
                                class="tc-btn"
                                disabled=move || linking.get()
                                on:click=move |_| submit_link(OidcSubjectInput::default())
                            >
                                "Remove link"
                            </button>
                            <button type="button" class="tc-btn" disabled=move || linking.get() on:click=move |_| close_link()>
                                "Cancel"
                            </button>
                        </div>
                    </form>
                }
            })}

            <Show
                when=move || !visible.with(Vec::is_empty)
                fallback=move || view! {
                    <p data-target="admin-users-empty" style="color: var(--on-surface-variant); padding: var(--space-xl) 0;">
                        {move || if loading.get() { "Loading users..." } else { "No users found." }}
                    </p>
                }
            >
                <div class="tc-table-wrap">
                    <table class="tc-table" data-target="admin-users-table">
                        <thead>
                            <tr>
                                <th scope="col">"Name"</th>
                                <th scope="col">"E-mail"</th>
                                <th scope="col">"Roles"</th>
                                <th scope="col">"Disabled modules"</th>
                                <th scope="col">"Status"</th>
                                <th scope="col"><span class="tc-label">"Actions"</span></th>
                            </tr>
                        </thead>
                        <tbody>
                            <For
                                each=move || visible.get()
                                key=|u| format!("{}:{:?}:{:?}:{}:{}:{}", u.user_id, u.roles, u.disabled_modules, u.active, u.display_name, u.has_signed_in)
                                children=move |u| {
                                    let id = u.user_id;
                                    let roles_text = u.roles.iter().map(|r| role_name(r)).collect::<Vec<_>>().join(", ");
                                    let modules_text = module_names(&u.disabled_modules);
                                    let style = if u.active { "" } else { "opacity: 0.55;" };
                                    let edit_user = u.clone();
                                    let link = u.clone();
                                    view! {
                                        <tr data-target=format!("admin-user-row-{id}") style=style>
                                            <td>{u.display_name.clone()}</td>
                                            <td data-target="admin-user-email-cell">{u.email.clone()}</td>
                                            <td>{roles_text}</td>
                                            <td>{modules_text}</td>
                                            <td>
                                                <span class=if u.active { "tc-badge tc-badge-success" } else { "tc-badge" }>
                                                    {if u.active { "Active" } else { "inactive" }}
                                                </span>
                                                {(!u.has_signed_in).then(|| view! {
                                                    " "
                                                    <span class="tc-badge">"Not signed in yet"</span>
                                                })}
                                            </td>
                                            <td style="white-space: nowrap;">
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-sm"
                                                    data-target=format!("admin-user-edit-{id}")
                                                    aria-label=format!("Edit {}", u.display_name)
                                                    on:click=move |_| open_editor(Editor::Edit(edit_user.clone()))
                                                >
                                                    "Edit"
                                                </button>
                                                <Show when=move || can_link.get()>
                                                    {
                                                        let link = link.clone();
                                                        view! {
                                                            " "
                                                            <button
                                                                type="button"
                                                                class="tc-btn tc-btn-sm"
                                                                data-target=format!("admin-user-link-{id}")
                                                                on:click=move |_| open_link(link.clone())
                                                            >
                                                                "Link identity"
                                                            </button>
                                                        }
                                                    }
                                                </Show>
                                            </td>
                                        </tr>
                                    }
                                }
                            />
                        </tbody>
                    </table>
                </div>
            </Show>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn user(name: &str, email: &str, active: bool) -> AdminUser {
        AdminUser {
            user_id: Uuid::new_v4(),
            email: email.into(),
            display_name: name.into(),
            roles: vec!["sales".into()],
            disabled_modules: vec![],
            active,
            has_signed_in: true,
        }
    }

    fn role(code: &str) -> RoleInfo {
        RoleInfo {
            role: code.into(),
            permissions: vec![],
        }
    }

    #[test]
    fn filters_by_status_and_name_or_email() {
        let list = [
            user("Ann Peeters", "ann@example.com", true),
            user("Bob", "bob@shop.test", false),
        ];
        assert_eq!(filter_users(&list, "", ActiveFilter::All).len(), 2);
        assert_eq!(
            filter_users(&list, "", ActiveFilter::Active)[0].display_name,
            "Ann Peeters"
        );
        assert_eq!(
            filter_users(&list, "", ActiveFilter::Inactive)[0].display_name,
            "Bob"
        );
        assert_eq!(filter_users(&list, " SHOP ", ActiveFilter::All).len(), 1);
        assert_eq!(
            filter_users(&list, "peeters", ActiveFilter::Inactive).len(),
            0
        );
    }

    #[test]
    fn draft_needs_name_role_and_email_for_new_members() {
        let mut d = UserDraft {
            name: "Ann".into(),
            roles: vec!["sales".into()],
            ..UserDraft::default()
        };
        assert!(d.valid(false));
        assert!(!d.valid(true));
        d.email = "ann@example.com".into();
        assert!(d.valid(true));
        d.roles.clear();
        assert!(!d.valid(false));
    }

    #[test]
    fn roles_follow_the_catalogue_and_modules_are_sorted() {
        let d = UserDraft {
            email: " ann@example.com ".into(),
            name: " Ann ".into(),
            roles: vec!["support".into(), "admin".into()],
            disabled: vec!["todo".into(), "kb".into()],
            active: false,
        };
        let catalogue = [role("admin"), role("sales"), role("support")];
        let create = d.to_create(&catalogue);
        assert_eq!(create.email, "ann@example.com");
        assert_eq!(create.roles, vec!["admin", "support"]);
        assert_eq!(create.disabled_modules, vec!["kb", "todo"]);
        let update = d.to_update(&catalogue);
        assert_eq!(update.display_name, "Ann");
        assert!(!update.active);
    }

    #[test]
    fn own_admin_role_is_locked() {
        assert!(role_locked(true, "admin", true));
        assert!(!role_locked(true, "admin", false));
        assert!(!role_locked(false, "admin", true));
        assert!(!role_locked(true, "sales", true));
    }
}
