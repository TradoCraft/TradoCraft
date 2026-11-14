//! Authentication (who are you) and authorisation (what may you do).
//!
//! Production uses OpenID Connect: clients send an access token issued by the
//! identity provider (e.g. Microsoft Entra ID or Keycloak) and the API verifies
//! its signature against the provider's JWKS. Development mode trusts an
//! `X-Dev-User` header and must never be enabled on a reachable server.
//!
//! The active legal entity is chosen with the `X-Company-Id` header and
//! defaults to the user's default membership.

use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use uuid::Uuid;

pub use crate::identity::Claims;
use crate::identity::{
    normalize_issuer, peek_issuer, EmailPolicy, IdentityProviders, ProviderConfig, ProviderSource,
};

use crate::modules::{effective_disabled, permission_module, Module};
use crate::{AppError, AppState};

pub const DEV_USER_HEADER: &str = "x-dev-user";
pub const COMPANY_HEADER: &str = "x-company-id";

#[allow(clippy::large_enum_variant)]
pub enum AuthConfig {
    Dev {
        default_email: Option<String>,
    },
    /// OpenID Connect against the configured identity providers (ADR 0055).
    Oidc(IdentityProviders),
    /// No staff sign-in at all: every staff route answers 401. Used by the customer-facing
    /// portal server, which serves no staff routes (ADR 0050).
    Disabled,
}

/// Permissions are checked in code; roles are granted per company and map to permissions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Permission {
    CustomersRead,
    CustomersWrite,
    ProductsRead,
    ProductsWrite,
    PricesWrite,
    QuotationsRead,
    QuotationsWrite,
    /// Import configured quotations from an external configurator
    /// (`POST /quotations/configured`, ADR 0033).
    QuotationsImport,
    OpportunitiesRead,
    OpportunitiesWrite,
    BomRead,
    BomWrite,
    SerialsRead,
    SerialsWrite,
    /// Create and change customer rebates.
    RebatesWrite,
    /// Record the periods in which a customer is closed and cannot receive deliveries.
    ClosuresWrite,
    /// Price a quotation on an earlier price list than its quote date.
    PricesBackdate,
    HelpdeskRead,
    /// Create tickets, write internal notes, change status and links.
    HelpdeskWrite,
    /// Send e-mails to customers.
    HelpdeskReply,
    /// Manage SLA policies, teams and helpdesk settings.
    HelpdeskAdmin,
    /// Manage prepared answers.
    AnswersWrite,
    /// Read the knowledge base, including internal and draft entries.
    KbRead,
    /// Write knowledge base entries (drafts, edits, images, versions).
    KbWrite,
    /// Manage knowledge base categories and publish, unpublish or archive entries.
    KbAdmin,
    OrdersRead,
    OrdersWrite,
    /// Create and change the people at customers (contacts) and their portal access.
    ContactsWrite,
    /// See repairs and their photos.
    RepairsRead,
    /// Register repairs, change their status, add notes and photos (in one's own departments).
    RepairsWrite,
    /// Route a repair to a department, and work on repairs of any department.
    RepairsRoute,
    /// Match a parcel with an announced repair, or create a repair from a parcel (intake).
    RepairsIntake,
    /// Mark a repair's warranty void (misuse) and remove that override.
    RepairsWarrantyVoid,
    /// See incoming parcels and their photos.
    PackagesRead,
    /// Register incoming parcels, edit and photograph them, and refuse one unopened.
    PackagesWrite,
    /// Open a parcel and decide what it is: a repair, something else, or to be returned.
    PackagesOpen,
    /// Create and change the workshop departments and who belongs to them (site admin).
    DepartmentsWrite,
    /// See field jobs: one's own as a technician, all as a planner or read-only role.
    FieldRead,
    /// Work on one's own jobs: start, complete, tick tasks, log work, add photos.
    FieldWork,
    /// Plan jobs and assign technicians.
    FieldPlan,
    /// See stock, moves and availability.
    InventoryRead,
    /// Receive, issue, transfer, reserve and count stock.
    InventoryWrite,
    /// Warehouses, locations, units of measure, reversals, posting counts and adjustments.
    InventoryAdmin,
    /// See and change standard cost (and anything derived from it).
    InventoryCost,
    /// Handle shipping requests: ask carriers, enter the quoted cost, and send a quotation
    /// before its shipping cost is known.
    ShippingManage,
    /// Administer the company's users (invite, roles, deactivate) and which modules are on.
    UsersAdmin,
    /// See the planning board: technicians, their calendars and the jobs on them.
    PlanningRead,
    /// Schedule and assign jobs on the board, record absences, set the skills a job needs.
    PlanningWrite,
    /// Manage working hours, the skills catalogue, technicians' skills and planning settings.
    PlanningAdmin,
    /// See suppliers, price lists and purchase orders.
    PurchasingRead,
    /// Create and edit suppliers, price lists and purchase orders.
    PurchasingWrite,
    /// Approve purchase orders.
    PurchasingApprove,
    /// Receive goods against purchase orders.
    GoodsReceipt,
    /// See supplier invoices, their match report and the finance settings (ADR 0046).
    FinanceRead,
    /// Register, edit, match, dispute and delete supplier invoices.
    FinanceWrite,
    /// Approve supplier invoices (also against a failed match, with a reason), record payment
    /// and change the match tolerances.
    FinanceApprove,
    /// Build configurators: models, revisions, tables, formulas, activation (ADR 0034).
    ConfiguratorDesign,
    /// Run configurators, save configurations and turn them into quotations (ADR 0034).
    ConfiguratorUse,
    /// See delivery notes, their lines and the delivery settings.
    DeliveryRead,
    /// Plan deliveries for orders: create and edit delivery notes (planned date, carrier, picking), cancel them.
    DeliveryWrite,
    /// Ship a delivery note: takes the stock out and records the tracking reference.
    DeliveryShip,
    /// Plan a delivery on a day the customer is closed when the company's closure policy requires an override.
    DeliveryOverrideClosure,
    /// Change the delivery settings, such as what happens when a delivery is planned on a closure.
    DeliveryAdmin,
    /// See production orders, their components and the production queues.
    ProductionRead,
    /// Release orders to production, create production orders, change dates and divisions, cancel them.
    ProductionWrite,
    /// Start and complete production orders: consume components, record output and scrap.
    ProductionRun,
    /// Manage the production divisions and which division makes which product.
    ProductionAdmin,
    /// Run the company's shared reports and one's own (ADR 0042). A report only shows the
    /// objects the user may read.
    ReportsRead,
    /// Create, change and delete one's own reports and share them with the company.
    ReportsWrite,
    /// Configure the identity providers of the installation (ADR 0055). Also requires the admin
    /// role in the installation's primary company.
    IdentityAdmin,
    /// See the audit trail of the company: the history of a record and the company-wide view
    /// (ADR 0059). The trail holds what every module recorded, so it is for administrators. Named
    /// `.view` and not `.read` on purpose: every `.read` permission belongs to the read-only
    /// viewer role (see `viewer_is_read_only`), and the viewer must not see the trail.
    AuditView,
    /// Use the to-do list: create, change, complete and delete one's own items and the ones handed
    /// over to oneself (ADR 0061). Not a `.read` permission, so the read-only viewer role has none.
    TodoUse,
    /// Use the data import screen: upload files, map their columns, run and read import jobs
    /// (ADR 0064). Running an import also needs the write permission of the entity.
    ImportsAdmin,
}

impl Permission {
    pub const ALL: [Permission; 73] = [
        Permission::CustomersRead,
        Permission::CustomersWrite,
        Permission::ProductsRead,
        Permission::ProductsWrite,
        Permission::PricesWrite,
        Permission::QuotationsRead,
        Permission::QuotationsWrite,
        Permission::QuotationsImport,
        Permission::OpportunitiesRead,
        Permission::OpportunitiesWrite,
        Permission::BomRead,
        Permission::BomWrite,
        Permission::SerialsRead,
        Permission::SerialsWrite,
        Permission::RebatesWrite,
        Permission::ClosuresWrite,
        Permission::PricesBackdate,
        Permission::HelpdeskRead,
        Permission::HelpdeskWrite,
        Permission::HelpdeskReply,
        Permission::HelpdeskAdmin,
        Permission::AnswersWrite,
        Permission::KbRead,
        Permission::KbWrite,
        Permission::KbAdmin,
        Permission::OrdersRead,
        Permission::OrdersWrite,
        Permission::ContactsWrite,
        Permission::RepairsRead,
        Permission::RepairsWrite,
        Permission::RepairsRoute,
        Permission::RepairsIntake,
        Permission::RepairsWarrantyVoid,
        Permission::PackagesRead,
        Permission::PackagesWrite,
        Permission::PackagesOpen,
        Permission::DepartmentsWrite,
        Permission::FieldRead,
        Permission::FieldWork,
        Permission::FieldPlan,
        Permission::InventoryRead,
        Permission::InventoryWrite,
        Permission::InventoryAdmin,
        Permission::InventoryCost,
        Permission::ShippingManage,
        Permission::UsersAdmin,
        Permission::PlanningRead,
        Permission::PlanningWrite,
        Permission::PlanningAdmin,
        Permission::PurchasingRead,
        Permission::PurchasingWrite,
        Permission::PurchasingApprove,
        Permission::GoodsReceipt,
        Permission::FinanceRead,
        Permission::FinanceWrite,
        Permission::FinanceApprove,
        Permission::ConfiguratorDesign,
        Permission::ConfiguratorUse,
        Permission::DeliveryRead,
        Permission::DeliveryWrite,
        Permission::DeliveryShip,
        Permission::DeliveryOverrideClosure,
        Permission::DeliveryAdmin,
        Permission::ProductionRead,
        Permission::ProductionWrite,
        Permission::ProductionRun,
        Permission::ProductionAdmin,
        Permission::ReportsRead,
        Permission::ReportsWrite,
        Permission::IdentityAdmin,
        Permission::AuditView,
        Permission::TodoUse,
        Permission::ImportsAdmin,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Permission::CustomersRead => "customers.read",
            Permission::CustomersWrite => "customers.write",
            Permission::ProductsRead => "products.read",
            Permission::ProductsWrite => "products.write",
            Permission::PricesWrite => "prices.write",
            Permission::QuotationsRead => "quotations.read",
            Permission::QuotationsWrite => "quotations.write",
            Permission::QuotationsImport => "quotations.import",
            Permission::OpportunitiesRead => "opportunities.read",
            Permission::OpportunitiesWrite => "opportunities.write",
            Permission::BomRead => "bom.read",
            Permission::BomWrite => "bom.write",
            Permission::SerialsRead => "serials.read",
            Permission::SerialsWrite => "serials.write",
            Permission::RebatesWrite => "rebates.write",
            Permission::ClosuresWrite => "closures.write",
            Permission::PricesBackdate => "prices.backdate",
            Permission::HelpdeskRead => "helpdesk.read",
            Permission::HelpdeskWrite => "helpdesk.write",
            Permission::HelpdeskReply => "helpdesk.reply",
            Permission::HelpdeskAdmin => "helpdesk.admin",
            Permission::AnswersWrite => "answers.write",
            Permission::KbRead => "kb.read",
            Permission::KbWrite => "kb.write",
            Permission::KbAdmin => "kb.admin",
            Permission::OrdersRead => "orders.read",
            Permission::OrdersWrite => "orders.write",
            Permission::ContactsWrite => "contacts.write",
            Permission::RepairsRead => "repairs.read",
            Permission::RepairsWrite => "repairs.write",
            Permission::RepairsRoute => "repairs.route",
            Permission::RepairsIntake => "repairs.intake",
            Permission::RepairsWarrantyVoid => "repairs.warranty_void",
            Permission::PackagesRead => "packages.read",
            Permission::PackagesWrite => "packages.write",
            Permission::PackagesOpen => "packages.open",
            Permission::DepartmentsWrite => "departments.write",
            Permission::FieldRead => "field.read",
            Permission::FieldWork => "field.work",
            Permission::FieldPlan => "field.plan",
            Permission::InventoryRead => "inventory.read",
            Permission::InventoryWrite => "inventory.write",
            Permission::InventoryAdmin => "inventory.admin",
            Permission::InventoryCost => "inventory.cost",
            Permission::ShippingManage => "shipping.manage",
            Permission::UsersAdmin => "users.admin",
            Permission::PlanningRead => "planning.read",
            Permission::PlanningWrite => "planning.write",
            Permission::PlanningAdmin => "planning.admin",
            Permission::PurchasingRead => "purchasing.read",
            Permission::PurchasingWrite => "purchasing.write",
            Permission::PurchasingApprove => "purchasing.approve",
            Permission::GoodsReceipt => "purchasing.receipt",
            Permission::FinanceRead => "finance.read",
            Permission::FinanceWrite => "finance.write",
            Permission::FinanceApprove => "finance.approve",
            Permission::ConfiguratorDesign => "configurator.design",
            Permission::ConfiguratorUse => "configurator.use",
            Permission::DeliveryRead => "delivery.read",
            Permission::DeliveryWrite => "delivery.write",
            Permission::DeliveryShip => "delivery.ship",
            Permission::DeliveryOverrideClosure => "delivery.override_closure",
            Permission::DeliveryAdmin => "delivery.admin",
            Permission::ProductionRead => "production.read",
            Permission::ProductionWrite => "production.write",
            Permission::ProductionRun => "production.run",
            Permission::ProductionAdmin => "production.admin",
            Permission::ReportsRead => "reports.read",
            Permission::ReportsWrite => "reports.write",
            Permission::IdentityAdmin => "identity.admin",
            Permission::AuditView => "audit.view",
            Permission::TodoUse => "todo.use",
            Permission::ImportsAdmin => "imports.admin",
        }
    }
}

/// The roles that exist. Roles are fixed in code (ADR 0004); the user administration picks from
/// this list.
pub const ROLES: [&str; 17] = [
    "admin",
    "sales_manager",
    "sales",
    "support",
    "production",
    "warehouse",
    "product_manager",
    "workshop",
    "technician",
    "dispatcher",
    "logistics",
    "viewer",
    "purchaser",
    // Accounts payable: supplier invoices and the three-way match (ADR 0046).
    "finance",
    // Incoming parcels and the repair hand-over (ADR 0030).
    "goods_in",
    "repair_intake",
    // A service account for systems that push data in, e.g. a product configurator (ADR 0033).
    "integration",
];

/// Role → permission mapping. Kept in code (reviewed, tested) rather than data for now.
pub fn role_grants(role: &str, p: Permission) -> bool {
    use Permission::*;
    // Everyone who works in the company has a to-do list, except the read-only viewer and the
    // integration service account (ADR 0061).
    if p == TodoUse {
        return ROLES
            .iter()
            .any(|r| *r == role && !matches!(role, "viewer" | "integration"));
    }
    match role {
        "admin" => true,
        "sales_manager" => {
            role_grants("sales", p)
                || matches!(
                    p,
                    RebatesWrite
                        | PricesBackdate
                        | QuotationsImport
                        | ConfiguratorDesign
                        | AnswersWrite
                        | RepairsRoute
                        | RepairsIntake
                        | RepairsWarrantyVoid
                        | PackagesOpen
                        | FieldPlan
                        | PlanningRead
                        | PlanningWrite
                        | DeliveryOverrideClosure
                        | ProductionWrite
                )
        }
        "sales" => matches!(
            p,
            CustomersRead
                | ClosuresWrite
                | CustomersWrite
                | ProductsRead
                | QuotationsRead
                | QuotationsWrite
                | OpportunitiesRead
                | OpportunitiesWrite
                | BomRead
                | SerialsRead
                | HelpdeskRead
                | HelpdeskWrite
                | HelpdeskReply
                | KbRead
                | OrdersRead
                | OrdersWrite
                | ContactsWrite
                | RepairsRead
                | RepairsWrite
                | PackagesRead
                | FieldRead
                | InventoryRead
                | ConfiguratorUse
                | DeliveryRead
                | DeliveryWrite
                | ProductionRead
                | ReportsRead
                | ReportsWrite
        ),
        // First-line customer service: answers e-mails, maintains prepared answers.
        "support" => matches!(
            p,
            CustomersRead
                | ClosuresWrite
                | ProductsRead
                | QuotationsRead
                | OpportunitiesRead
                | OpportunitiesWrite
                | BomRead
                | SerialsRead
                | HelpdeskRead
                | HelpdeskWrite
                | HelpdeskReply
                | AnswersWrite
                | KbRead
                | KbWrite
                | ContactsWrite
                | RepairsRead
                | RepairsWrite
                | RepairsRoute
                | RepairsIntake
                | PackagesRead
                | PackagesOpen
                | OrdersRead
                | InventoryRead
                | DeliveryRead
                | ProductionRead
                | ReportsRead
        ),
        // Production asks questions through internal notes; sales talks to the customer.
        "production" => matches!(
            p,
            CustomersRead
                | ProductsRead
                | BomRead
                | SerialsRead
                | SerialsWrite
                | OrdersRead
                | HelpdeskRead
                | HelpdeskWrite
                | KbRead
                | InventoryRead
                | InventoryWrite
                | PurchasingRead
                | DeliveryRead
                | ProductionRead
                | ProductionWrite
                | ProductionRun
        ),
        // Stores: receives, issues, transfers and counts stock; never sees cost.
        "warehouse" => matches!(
            p,
            ProductsRead
                | BomRead
                | SerialsRead
                | OrdersRead
                | InventoryRead
                | InventoryWrite
                | PurchasingRead
                | GoodsReceipt
                | DeliveryRead
                | DeliveryWrite
                | DeliveryShip
                | ProductionRead
                | ProductionRun
        ),
        "product_manager" => matches!(
            p,
            CustomersRead
                | ProductsRead
                | ProductsWrite
                | PricesWrite
                | QuotationsRead
                | OpportunitiesRead
                | BomRead
                | BomWrite
                | SerialsRead
                | SerialsWrite
                | OrdersRead
                | HelpdeskRead
                | KbRead
                | KbWrite
                | InventoryRead
                | InventoryCost
                | ConfiguratorDesign
                | ProductionRead
        ),
        // The workshop: works on repairs routed to the departments one belongs to.
        "workshop" => matches!(
            p,
            CustomersRead
                | ProductsRead
                | RepairsRead
                | RepairsWrite
                | RepairsWarrantyVoid
                | BomRead
                | SerialsRead
                | InventoryRead
        ),
        // Field technician: sees and works on their own jobs only.
        "technician" => matches!(p, FieldRead | FieldWork),
        "dispatcher" => matches!(
            p,
            CustomersRead
                | ClosuresWrite
                | FieldRead
                | FieldPlan
                | RepairsRead
                | PackagesRead
                | HelpdeskRead
                | ContactsWrite
                | PlanningRead
                | PlanningWrite
                | DeliveryRead
        ),
        // Logistics: asks carriers for quotes and enters the shipping cost on quotations.
        "logistics" => matches!(
            p,
            CustomersRead
                | ClosuresWrite
                | ProductsRead
                | QuotationsRead
                | OrdersRead
                | InventoryRead
                | ShippingManage
                | PurchasingRead
                | PackagesRead
                | PackagesWrite
                | DeliveryRead
                | DeliveryWrite
                | DeliveryShip
                | DeliveryOverrideClosure
        ),
        "viewer" => matches!(
            p,
            RepairsRead
                | PackagesRead
                | FieldRead
                | PlanningRead
                | CustomersRead
                | ProductsRead
                | QuotationsRead
                | OpportunitiesRead
                | BomRead
                | SerialsRead
                | HelpdeskRead
                | KbRead
                | OrdersRead
                | InventoryRead
                | PurchasingRead
                | FinanceRead
                | DeliveryRead
                | ProductionRead
                | ReportsRead
        ),
        // Purchasing: manages suppliers, price lists, purchase orders and goods receipt.
        "purchaser" => matches!(
            p,
            CustomersRead
                | ProductsRead
                | InventoryRead
                | InventoryCost
                | BomRead
                | KbRead
                | PurchasingRead
                | PurchasingWrite
                | PurchasingApprove
                | GoodsReceipt
                | FinanceRead
        ),
        // Accounts payable: registers, matches, approves and pays supplier invoices (ADR 0046).
        "finance" => matches!(
            p,
            CustomersRead
                | ProductsRead
                | InventoryRead
                | PurchasingRead
                | FinanceRead
                | FinanceWrite
                | FinanceApprove
                | ReportsRead
        ),
        // The receiving dock: registers and photographs incoming parcels (ADR 0030, step 1).
        "goods_in" => matches!(
            p,
            CustomersRead | PackagesRead | PackagesWrite | RepairsRead
        ),
        // Repair intake: opens parcels, checks and photographs, matches announced repairs,
        // routes to a department (ADR 0030, steps 2 to 4).
        "repair_intake" => matches!(
            p,
            CustomersRead
                | ProductsRead
                | SerialsRead
                | PackagesRead
                | PackagesWrite
                | PackagesOpen
                | RepairsRead
                | RepairsWrite
                | RepairsIntake
                | RepairsRoute
                | HelpdeskRead
                | HelpdeskWrite
        ),
        // A system account (e.g. an external product configurator): imports configured quotations
        // and reads back what it created. It cannot send, accept or edit quotations by hand.
        "integration" => matches!(
            p,
            QuotationsImport | QuotationsRead | CustomersRead | ProductsRead
        ),
        _ => false,
    }
}

#[derive(Debug, Clone)]
pub struct CurrentUser {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub company_id: Uuid,
    pub roles: Vec<String>,
    /// Modules switched off for this user in this company (the company's plus their own).
    pub disabled_modules: Vec<Module>,
}

impl CurrentUser {
    /// The module that switches this permission off for the user, if any.
    fn disabling_module(&self, p: Permission) -> Option<Module> {
        permission_module(p).filter(|m| self.disabled_modules.contains(m))
    }

    /// Whether the user's modules are enabled for this module.
    pub fn module_enabled(&self, m: Module) -> bool {
        !self.disabled_modules.contains(&m)
    }

    pub fn can(&self, p: Permission) -> bool {
        self.disabling_module(p).is_none() && self.roles.iter().any(|r| role_grants(r, p))
    }

    pub fn require(&self, p: Permission) -> Result<(), AppError> {
        if self.can(p) {
            return Ok(());
        }
        match self.disabling_module(p) {
            Some(m) if self.roles.iter().any(|r| role_grants(r, p)) => Err(AppError::Forbidden(
                format!("module {} is disabled ({})", m.code(), p.as_str()),
            )),
            _ => Err(AppError::Forbidden(format!(
                "missing permission {}",
                p.as_str()
            ))),
        }
    }

    pub fn permissions(&self) -> Vec<Permission> {
        Permission::ALL
            .into_iter()
            .filter(|p| self.can(*p))
            .collect()
    }
}

#[derive(sqlx::FromRow)]
struct UserRow {
    id: Uuid,
    email: String,
    display_name: String,
    oidc_subject: Option<String>,
}

#[derive(sqlx::FromRow)]
struct MembershipRow {
    company_id: Uuid,
    roles: Vec<String>,
    disabled_modules: Vec<String>,
    user_disabled_modules: Vec<String>,
    active: bool,
}

/// The membership of a user in a company: the requested one, or the default one when `company_id`
/// is None. The one place that reads roles and disabled modules, for a request and for a stored
/// user alike.
async fn find_membership(
    db: &sqlx::PgPool,
    user_id: Uuid,
    company_id: Option<Uuid>,
) -> Result<MembershipRow, AppError> {
    let membership: Option<MembershipRow> = sqlx::query_as(
        "SELECT uc.company_id, uc.roles, c.disabled_modules,
                uc.disabled_modules AS user_disabled_modules, uc.active
         FROM core.user_companies uc JOIN core.companies c ON c.id = uc.company_id
         WHERE uc.user_id = $1 AND (uc.company_id = $2 OR ($2 IS NULL AND uc.is_default))",
    )
    .bind(user_id)
    .bind(company_id)
    .fetch_optional(db)
    .await?;
    membership.ok_or_else(|| AppError::Forbidden("no access to the requested company".into()))
}

impl CurrentUser {
    fn assemble(
        user_id: Uuid,
        email: String,
        display_name: String,
        membership: MembershipRow,
    ) -> Result<CurrentUser, AppError> {
        if !membership.active {
            return Err(AppError::Forbidden(
                "your access to this company has been deactivated".into(),
            ));
        }
        Ok(CurrentUser {
            user_id,
            email,
            display_name,
            company_id: membership.company_id,
            roles: membership.roles,
            disabled_modules: effective_disabled(
                &membership.disabled_modules,
                &membership.user_disabled_modules,
            ),
        })
    }

    /// The user `user_id` as they act in `company_id` right now, for work done on their behalf
    /// outside a request (a background import job): the same roles and disabled modules a request
    /// of theirs would see. Fails with `Forbidden` when the user no longer exists or is
    /// deactivated, is not a member of the company, or their membership is deactivated.
    pub async fn for_member(
        db: &sqlx::PgPool,
        user_id: Uuid,
        company_id: Uuid,
    ) -> Result<CurrentUser, AppError> {
        let user: UserRow = sqlx::query_as(
            "SELECT id, email, display_name, oidc_subject FROM core.users
             WHERE id = $1 AND active",
        )
        .bind(user_id)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::Forbidden("the user no longer exists or is deactivated".into()))?;
        let membership = find_membership(db, user_id, Some(company_id)).await?;
        CurrentUser::assemble(user.id, user.email, user.display_name, membership)
    }
}

impl FromRequestParts<AppState> for CurrentUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let user = match state.auth.as_ref() {
            AuthConfig::Dev { default_email } => {
                let email = header(parts, DEV_USER_HEADER)
                    .map(str::to_string)
                    .or_else(|| default_email.clone())
                    .ok_or(AppError::Unauthorized)?;
                find_user_by_email(state, &email)
                    .await?
                    .ok_or(AppError::Unauthorized)?
            }
            AuthConfig::Oidc(verifier) => {
                let token = header(parts, "authorization")
                    .and_then(|h| h.strip_prefix("Bearer "))
                    .ok_or(AppError::Unauthorized)?;
                let verified = verifier.verify(token).await?;
                resolve_oidc_user(state, &verified.provider, &verified.claims).await?
            }
            AuthConfig::Disabled => return Err(AppError::Unauthorized),
        };

        let requested_company = match header(parts, COMPANY_HEADER) {
            Some(v) => Some(
                Uuid::parse_str(v)
                    .map_err(|_| AppError::Validation("invalid X-Company-Id".into()))?,
            ),
            None => None,
        };
        let membership = find_membership(&state.db, user.id, requested_company).await?;
        CurrentUser::assemble(user.id, user.email, user.display_name, membership)
    }
}

fn header<'a>(parts: &'a Parts, name: &str) -> Option<&'a str> {
    parts
        .headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty())
}

async fn find_user_by_email(state: &AppState, email: &str) -> Result<Option<UserRow>, AppError> {
    Ok(sqlx::query_as(
        "SELECT id, email, display_name, oidc_subject FROM core.users
         WHERE lower(email) = lower($1) AND active",
    )
    .bind(email)
    .fetch_optional(&state.db)
    .await?)
}

/// What signing in with a verified identity would do, without doing it.
#[derive(Debug, Clone)]
pub struct BindingPreview {
    /// `existing_subject` (already bound), `would_bind` (first sign-in binds by e-mail) or `refused`.
    pub outcome: &'static str,
    /// The user it resolves to.
    pub user_id: Option<Uuid>,
    /// That user's e-mail address.
    pub user_email: Option<String>,
    /// Why it is refused.
    pub reason: Option<String>,
}

struct Decision {
    preview: BindingPreview,
    user: Option<UserRow>,
    bind: bool,
    subject: String,
}

/// The value stored in `core.users.oidc_subject`: issuer-qualified (`<issuer>|<sub>`) for database
/// providers, because the same `sub` can repeat across issuers; legacy unqualified for the
/// environment provider (ADR 0055).
pub fn stored_subject(cfg: &ProviderConfig, sub: &str) -> String {
    match cfg.source {
        ProviderSource::Env => sub.to_string(),
        ProviderSource::Database => format!("{}|{}", cfg.issuer, sub),
    }
}

fn refused(reason: &str, subject: String) -> Decision {
    Decision {
        preview: BindingPreview {
            outcome: "refused",
            user_id: None,
            user_email: None,
            reason: Some(reason.into()),
        },
        user: None,
        bind: false,
        subject,
    }
}

async fn decide(
    state: &AppState,
    cfg: &ProviderConfig,
    claims: &Claims,
) -> Result<Decision, AppError> {
    let subject = stored_subject(cfg, &claims.sub);
    let by_subject: Option<UserRow> = sqlx::query_as(
        "SELECT id, email, display_name, oidc_subject FROM core.users WHERE oidc_subject = $1 AND active",
    )
    .bind(&subject)
    .fetch_optional(&state.db)
    .await?;
    if let Some(u) = by_subject {
        return Ok(Decision {
            preview: BindingPreview {
                outcome: "existing_subject",
                user_id: Some(u.id),
                user_email: Some(u.email.clone()),
                reason: None,
            },
            user: Some(u),
            bind: false,
            subject,
        });
    }
    // The first sign-in binds the account by e-mail, as the provider's policy allows (ADR 0047:
    // the bootstrap admin is pre-provisioned by e-mail).
    match cfg.email_policy {
        EmailPolicy::SubjectOnly => {
            return Ok(refused(
                "policy subject_only: no user has this subject set",
                subject,
            ))
        }
        EmailPolicy::RequireVerifiedClaim => {
            if claims.verified(cfg) != Some(true) {
                return Ok(refused(
                    &format!(
                        "the claim {} does not confirm the e-mail address",
                        cfg.verified_claim
                    ),
                    subject,
                ));
            }
        }
        EmailPolicy::TrustProviderEmail => {}
    }
    let Some(email) = claims.email(cfg) else {
        return Ok(refused(
            &format!("the token has no {} claim", cfg.email_claim),
            subject,
        ));
    };
    if !cfg.allowed_email_domains.is_empty() {
        let domain = email.rsplit_once('@').map(|(_, d)| d.to_lowercase());
        if !domain.is_some_and(|d| cfg.allowed_email_domains.contains(&d)) {
            return Ok(refused("the e-mail domain is not allowed", subject));
        }
    }
    let Some(user) = find_user_by_email(state, &email).await? else {
        return Ok(refused("no active user has this e-mail address", subject));
    };
    if user.oidc_subject.is_some() {
        // Bound to a different identity: refuse rather than silently re-bind.
        return Ok(refused(
            "the user is bound to a different identity",
            subject,
        ));
    }
    Ok(Decision {
        preview: BindingPreview {
            outcome: "would_bind",
            user_id: Some(user.id),
            user_email: Some(user.email.clone()),
            reason: None,
        },
        user: Some(user),
        bind: true,
        subject,
    })
}

/// What a verified identity would resolve to, without binding anything.
pub async fn preview_binding(
    state: &AppState,
    cfg: &ProviderConfig,
    claims: &Claims,
) -> Result<BindingPreview, AppError> {
    Ok(decide(state, cfg, claims).await?.preview)
}

/// Users are provisioned in the ERP (with roles); the identity provider only proves who they are.
/// On first login the subject is bound to the user found by e-mail, as the provider's policy allows.
async fn resolve_oidc_user(
    state: &AppState,
    cfg: &ProviderConfig,
    claims: &Claims,
) -> Result<UserRow, AppError> {
    let d = decide(state, cfg, claims).await?;
    let user = d.user.ok_or(AppError::Unauthorized)?;
    if d.bind {
        let done = sqlx::query(
            "UPDATE core.users SET oidc_subject = $1 WHERE id = $2 AND oidc_subject IS NULL",
        )
        .bind(&d.subject)
        .bind(user.id)
        .execute(&state.db)
        .await?;
        if done.rows_affected() != 1 {
            // Another sign-in bound the user first: only the same identity may continue.
            let now: Option<String> =
                sqlx::query_scalar("SELECT oidc_subject FROM core.users WHERE id = $1")
                    .bind(user.id)
                    .fetch_optional(&state.db)
                    .await?
                    .flatten();
            if now.as_deref() != Some(d.subject.as_str()) {
                return Err(AppError::Unauthorized);
            }
        }
    }
    Ok(user)
}

/// Resolves (and on first sign-in binds) the user a verified identity of `cfg` belongs to;
/// returns the user id. Public so the binding can be tested without minting a signed token.
pub async fn bind_oidc_user(
    state: &AppState,
    cfg: &ProviderConfig,
    claims: &Claims,
) -> Result<Uuid, AppError> {
    Ok(resolve_oidc_user(state, cfg, claims).await?.id)
}

/// The issuer of the caller's bearer token (unverified; use only after [`CurrentUser`] succeeded
/// in the same handler). None in dev mode.
#[derive(Debug, Clone)]
pub struct CallerIssuer(pub Option<String>);

impl FromRequestParts<AppState> for CallerIssuer {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        Ok(CallerIssuer(match state.auth.as_ref() {
            AuthConfig::Dev { .. } | AuthConfig::Disabled => None,
            AuthConfig::Oidc(_) => header(parts, "authorization")
                .and_then(|h| h.strip_prefix("Bearer "))
                .and_then(peek_issuer)
                .map(|i| normalize_issuer(&i)),
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sales_cannot_change_prices_or_products() {
        assert!(role_grants("sales", Permission::QuotationsWrite));
        assert!(!role_grants("sales", Permission::PricesWrite));
        assert!(!role_grants("sales", Permission::ProductsWrite));
    }

    #[test]
    fn viewer_is_read_only() {
        for p in Permission::ALL {
            assert_eq!(role_grants("viewer", p), p.as_str().ends_with(".read"));
        }
    }

    #[test]
    fn only_managers_change_rebates_or_backdate_prices() {
        for p in [Permission::RebatesWrite, Permission::PricesBackdate] {
            assert!(role_grants("sales_manager", p));
            assert!(role_grants("admin", p));
            assert!(!role_grants("sales", p));
        }
        assert!(role_grants("sales_manager", Permission::QuotationsWrite));
    }

    #[test]
    fn production_cannot_email_customers() {
        assert!(role_grants("production", Permission::HelpdeskWrite));
        assert!(!role_grants("production", Permission::HelpdeskReply));
        assert!(role_grants("sales", Permission::HelpdeskReply));
    }

    #[test]
    fn only_admins_manage_sla_policies_and_teams() {
        assert!(role_grants("admin", Permission::HelpdeskAdmin));
        for r in ["sales", "sales_manager", "support", "production", "viewer"] {
            assert!(!role_grants(r, Permission::HelpdeskAdmin), "{r}");
        }
    }

    #[test]
    fn knowledge_base_rights_follow_the_roles() {
        for p in [Permission::KbRead, Permission::KbWrite, Permission::KbAdmin] {
            assert!(role_grants("admin", p));
        }
        for r in ["support", "product_manager"] {
            assert!(role_grants(r, Permission::KbRead) && role_grants(r, Permission::KbWrite));
            assert!(!role_grants(r, Permission::KbAdmin), "{r}");
        }
        for r in ["sales", "sales_manager", "production", "viewer"] {
            assert!(role_grants(r, Permission::KbRead), "{r}");
            assert!(!role_grants(r, Permission::KbWrite), "{r}");
        }
        for r in ["technician", "workshop", "dispatcher"] {
            assert!(!role_grants(r, Permission::KbRead), "{r}");
        }
    }

    #[test]
    fn contacts_are_maintained_by_sales_and_support_only() {
        for r in ["admin", "sales", "sales_manager", "support"] {
            assert!(role_grants(r, Permission::ContactsWrite), "{r}");
        }
        for r in ["production", "product_manager", "viewer"] {
            assert!(!role_grants(r, Permission::ContactsWrite), "{r}");
        }
    }

    #[test]
    fn only_admins_create_departments() {
        for r in [
            "sales",
            "sales_manager",
            "support",
            "workshop",
            "dispatcher",
            "technician",
            "viewer",
        ] {
            assert!(!role_grants(r, Permission::DepartmentsWrite), "{r}");
        }
        assert!(role_grants("admin", Permission::DepartmentsWrite));
    }

    #[test]
    fn workshop_and_field_roles_are_narrow() {
        // The workshop works on repairs but does not route them; technicians cannot plan.
        assert!(role_grants("workshop", Permission::RepairsWrite));
        assert!(!role_grants("workshop", Permission::RepairsRoute));
        assert!(role_grants("support", Permission::RepairsRoute));
        // Only the workshop and the escalation owner may declare a warranty void.
        for r in ["workshop", "sales_manager", "admin"] {
            assert!(role_grants(r, Permission::RepairsWarrantyVoid), "{r}");
        }
        for r in [
            "support",
            "sales",
            "repair_intake",
            "goods_in",
            "viewer",
            "dispatcher",
        ] {
            assert!(!role_grants(r, Permission::RepairsWarrantyVoid), "{r}");
        }
        assert!(role_grants("technician", Permission::FieldWork));
        assert!(!role_grants("technician", Permission::FieldPlan));
        assert!(!role_grants("technician", Permission::RepairsRead));
        assert!(!role_grants("technician", Permission::CustomersRead));
        assert!(role_grants("dispatcher", Permission::FieldPlan));
        assert!(!role_grants("dispatcher", Permission::FieldWork));
    }

    #[test]
    fn package_rights_follow_the_hand_over_steps() {
        // Step 1: the dock registers and photographs, but cannot open, match or route.
        for p in [Permission::PackagesRead, Permission::PackagesWrite] {
            assert!(role_grants("goods_in", p), "{}", p.as_str());
        }
        for p in [
            Permission::PackagesOpen,
            Permission::RepairsIntake,
            Permission::RepairsRoute,
            Permission::RepairsWrite,
        ] {
            assert!(!role_grants("goods_in", p), "{}", p.as_str());
        }
        assert!(role_grants("goods_in", Permission::RepairsRead));
        // Steps 2 to 4.
        for p in [
            Permission::PackagesRead,
            Permission::PackagesWrite,
            Permission::PackagesOpen,
            Permission::RepairsIntake,
            Permission::RepairsRoute,
            Permission::RepairsWrite,
        ] {
            assert!(role_grants("repair_intake", p), "{}", p.as_str());
        }
        assert!(!role_grants("repair_intake", Permission::UsersAdmin));
        // Triage roles that exist already.
        for r in ["support", "sales_manager"] {
            for p in [
                Permission::RepairsIntake,
                Permission::PackagesRead,
                Permission::PackagesOpen,
            ] {
                assert!(role_grants(r, p), "{r} {}", p.as_str());
            }
            assert!(!role_grants(r, Permission::PackagesWrite), "{r}");
        }
        assert!(role_grants("sales", Permission::PackagesRead));
        assert!(!role_grants("sales", Permission::PackagesOpen));
        assert!(!role_grants("sales", Permission::RepairsIntake));
        for r in ["dispatcher", "viewer"] {
            assert!(role_grants(r, Permission::PackagesRead), "{r}");
            assert!(!role_grants(r, Permission::PackagesWrite), "{r}");
        }
        assert!(role_grants("logistics", Permission::PackagesRead));
        assert!(role_grants("logistics", Permission::PackagesWrite));
        assert!(!role_grants("logistics", Permission::PackagesOpen));
        // The workshop and field roles are unchanged in this phase.
        for r in ["workshop", "technician", "warehouse", "production"] {
            assert!(!role_grants(r, Permission::PackagesWrite), "{r}");
            assert!(!role_grants(r, Permission::PackagesOpen), "{r}");
            assert!(!role_grants(r, Permission::RepairsIntake), "{r}");
        }
    }

    #[test]
    fn configured_quotation_import() {
        assert!(ROLES.contains(&"integration"));
        let granted: Vec<Permission> = Permission::ALL
            .into_iter()
            .filter(|p| role_grants("integration", *p))
            .collect();
        assert_eq!(
            granted,
            [
                Permission::CustomersRead,
                Permission::ProductsRead,
                Permission::QuotationsRead,
                Permission::QuotationsImport,
            ]
        );
        for r in ["admin", "sales_manager"] {
            assert!(role_grants(r, Permission::QuotationsImport), "{r}");
        }
        for r in ["sales", "support", "viewer", "logistics", "product_manager"] {
            assert!(!role_grants(r, Permission::QuotationsImport), "{r}");
        }
    }

    #[test]
    fn production_rights_follow_the_roles() {
        use Permission::*;
        let who = |p: Permission| -> Vec<&str> {
            ROLES
                .iter()
                .copied()
                .filter(|r| role_grants(r, p))
                .collect()
        };
        // Planning and running are separate; only the administrator keeps the divisions.
        assert_eq!(who(ProductionAdmin), vec!["admin"]);
        assert_eq!(
            who(ProductionWrite),
            vec!["admin", "sales_manager", "production"]
        );
        assert_eq!(who(ProductionRun), vec!["admin", "production", "warehouse"]);
        for r in ["sales", "support", "product_manager", "viewer"] {
            assert!(role_grants(r, ProductionRead), "{r}");
            assert!(!role_grants(r, ProductionWrite), "{r}");
        }
        for r in ["technician", "logistics", "goods_in", "integration"] {
            assert!(!role_grants(r, ProductionRead), "{r}");
        }
    }

    #[test]
    fn delivery_rights_follow_the_roles() {
        use Permission::*;
        let who = |p: Permission| -> Vec<&str> {
            ROLES
                .iter()
                .copied()
                .filter(|r| role_grants(r, p))
                .collect()
        };
        // Planning and shipping are separate; only the administrator changes the settings.
        assert_eq!(who(DeliveryAdmin), vec!["admin"]);
        assert_eq!(who(DeliveryShip), vec!["admin", "warehouse", "logistics"]);
        assert_eq!(
            who(DeliveryWrite),
            vec!["admin", "sales_manager", "sales", "warehouse", "logistics"]
        );
        assert_eq!(
            who(DeliveryOverrideClosure),
            vec!["admin", "sales_manager", "logistics"]
        );
        for r in ["support", "viewer", "dispatcher", "production"] {
            assert!(role_grants(r, DeliveryRead), "{r}");
            assert!(!role_grants(r, DeliveryWrite), "{r}");
        }
        for r in ["technician", "goods_in", "integration"] {
            assert!(!role_grants(r, DeliveryRead), "{r}");
        }
    }

    #[test]
    fn configurator_rights_follow_the_roles() {
        for r in ["admin", "product_manager", "sales_manager"] {
            assert!(role_grants(r, Permission::ConfiguratorDesign), "{r}");
        }
        for r in ["admin", "sales", "sales_manager"] {
            assert!(role_grants(r, Permission::ConfiguratorUse), "{r}");
        }
        for r in ROLES
            .iter()
            .filter(|r| !["admin", "product_manager", "sales_manager"].contains(r))
        {
            assert!(!role_grants(r, Permission::ConfiguratorDesign), "{r}");
        }
        for r in [
            "viewer",
            "support",
            "integration",
            "product_manager",
            "logistics",
        ] {
            assert!(!role_grants(r, Permission::ConfiguratorUse), "{r}");
        }
    }

    #[test]
    fn inventory_rights_follow_the_roles() {
        for p in [
            Permission::InventoryRead,
            Permission::InventoryWrite,
            Permission::InventoryAdmin,
            Permission::InventoryCost,
        ] {
            assert!(role_grants("admin", p));
        }
        for r in ["sales", "sales_manager", "support", "viewer", "workshop"] {
            assert!(role_grants(r, Permission::InventoryRead), "{r}");
            assert!(!role_grants(r, Permission::InventoryWrite), "{r}");
        }
        for r in ["production", "warehouse"] {
            assert!(role_grants(r, Permission::InventoryWrite), "{r}");
            assert!(!role_grants(r, Permission::InventoryAdmin), "{r}");
        }
        // Cost is not for sales, the warehouse or production.
        for r in [
            "sales",
            "sales_manager",
            "support",
            "production",
            "warehouse",
            "viewer",
        ] {
            assert!(!role_grants(r, Permission::InventoryCost), "{r}");
        }
        assert!(role_grants("product_manager", Permission::InventoryCost));
        assert!(!role_grants("technician", Permission::InventoryRead));
    }

    #[test]
    fn shipping_is_for_logistics_and_admins_only() {
        for r in ["admin", "logistics"] {
            assert!(role_grants(r, Permission::ShippingManage), "{r}");
        }
        for r in [
            "sales",
            "sales_manager",
            "support",
            "production",
            "warehouse",
            "product_manager",
            "viewer",
            "technician",
            "purchaser",
        ] {
            assert!(!role_grants(r, Permission::ShippingManage), "{r}");
        }
        assert!(role_grants("logistics", Permission::QuotationsRead));
        assert!(!role_grants("logistics", Permission::QuotationsWrite));
    }

    #[test]
    fn purchasing_rights_follow_the_roles() {
        for p in [
            Permission::PurchasingRead,
            Permission::PurchasingWrite,
            Permission::PurchasingApprove,
            Permission::GoodsReceipt,
        ] {
            assert!(role_grants("admin", p));
            assert!(role_grants("purchaser", p));
        }
        // Warehouse can read purchasing and receive goods.
        assert!(role_grants("warehouse", Permission::PurchasingRead));
        assert!(role_grants("warehouse", Permission::GoodsReceipt));
        assert!(!role_grants("warehouse", Permission::PurchasingWrite));
        assert!(!role_grants("warehouse", Permission::PurchasingApprove));

        // Logistics, production, and viewer can read purchasing only.
        for r in ["logistics", "production", "viewer"] {
            assert!(role_grants(r, Permission::PurchasingRead), "{r}");
            assert!(!role_grants(r, Permission::PurchasingWrite), "{r}");
            assert!(!role_grants(r, Permission::PurchasingApprove), "{r}");
            assert!(!role_grants(r, Permission::GoodsReceipt), "{r}");
        }
    }

    #[test]
    fn finance_rights_follow_the_roles() {
        for p in [
            Permission::FinanceRead,
            Permission::FinanceWrite,
            Permission::FinanceApprove,
        ] {
            assert!(role_grants("admin", p));
            assert!(role_grants("finance", p));
            assert_eq!(p.as_str().split('.').next(), Some("finance"));
        }
        // The purchaser sees invoices but cannot register or approve them.
        assert!(role_grants("purchaser", Permission::FinanceRead));
        assert!(!role_grants("purchaser", Permission::FinanceWrite));
        assert!(!role_grants("purchaser", Permission::FinanceApprove));
        // The viewer reads everything (every `.read` permission), but cannot write or approve.
        assert!(role_grants("viewer", Permission::FinanceRead));
        assert!(!role_grants("viewer", Permission::FinanceWrite));
        for r in ["sales", "warehouse", "logistics", "production"] {
            assert!(!role_grants(r, Permission::FinanceRead), "{r}");
        }
    }

    #[test]
    fn only_admins_administer_users() {
        assert!(role_grants("admin", Permission::UsersAdmin));
        for r in ROLES.iter().filter(|r| **r != "admin") {
            assert!(!role_grants(r, Permission::UsersAdmin), "{r}");
        }
    }

    #[test]
    fn only_admins_administer_identity() {
        for r in ROLES {
            assert_eq!(
                role_grants(r, Permission::IdentityAdmin),
                r == "admin",
                "{r}"
            );
        }
    }

    #[test]
    fn everyone_but_the_viewer_and_the_integration_account_has_a_to_do_list() {
        for r in ROLES {
            assert_eq!(
                role_grants(r, Permission::TodoUse),
                !matches!(r, "viewer" | "integration"),
                "{r}"
            );
        }
        assert_eq!(Permission::TodoUse.as_str(), "todo.use");
        assert!(!role_grants("nobody", Permission::TodoUse));
    }

    #[test]
    fn only_admins_administer_imports() {
        for r in ROLES {
            assert_eq!(
                role_grants(r, Permission::ImportsAdmin),
                r == "admin",
                "{r}"
            );
        }
        assert_eq!(Permission::ImportsAdmin.as_str(), "imports.admin");
    }

    #[test]
    fn only_admins_view_the_audit_trail() {
        for r in ROLES {
            assert_eq!(role_grants(r, Permission::AuditView), r == "admin", "{r}");
        }
        assert_eq!(Permission::AuditView.as_str(), "audit.view");
    }

    #[test]
    fn every_listed_role_grants_something_and_the_list_has_no_duplicates() {
        for r in ROLES {
            assert!(Permission::ALL.iter().any(|p| role_grants(r, *p)), "{r}");
        }
        let mut sorted = ROLES.to_vec();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), ROLES.len());
    }

    fn user(roles: &[&str], disabled: &[Module]) -> CurrentUser {
        CurrentUser {
            user_id: Uuid::nil(),
            email: "a@example.com".into(),
            display_name: "A".into(),
            company_id: Uuid::nil(),
            roles: roles.iter().map(|r| r.to_string()).collect(),
            disabled_modules: disabled.to_vec(),
        }
    }

    #[test]
    fn a_disabled_module_removes_its_permissions_and_says_why() {
        let u = user(&["admin"], &[Module::Kb]);
        assert!(!u.can(Permission::KbRead));
        assert!(u.can(Permission::QuotationsRead));
        assert!(u.can(Permission::UsersAdmin));
        let msg = u.require(Permission::KbWrite).unwrap_err().to_string();
        assert!(msg.contains("module kb is disabled"), "{msg}");
        assert!(!u.permissions().contains(&Permission::KbRead));
        // Not granted by the role at all: the plain message.
        let v = user(&["viewer"], &[Module::Kb]);
        let msg = v
            .require(Permission::ProductsWrite)
            .unwrap_err()
            .to_string();
        assert!(msg.contains("missing permission"), "{msg}");
    }

    #[test]
    fn unknown_role_grants_nothing() {
        assert!(Permission::ALL.iter().all(|p| !role_grants("intern", *p)));
    }
}
