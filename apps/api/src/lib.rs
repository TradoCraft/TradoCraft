//! HTTP application: wires the business modules into one API.

use axum::Router;
use tower_http::trace::TraceLayer;
use tradocraft_core::companies::BootstrapConfig;
use tradocraft_core::cors::CorsConfig;
use tradocraft_core::environment::EnvironmentConfig;
use tradocraft_core::identity::IdpSettings;
use tradocraft_core::vies::ViesConfig;
use tradocraft_core::AppState;
use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
use utoipa::openapi::OpenApi as OpenApiDoc;
use utoipa::{Modify, OpenApi};
use utoipa_axum::router::OpenApiRouter;
use utoipa_scalar::{Scalar, Servable};

pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("../../migrations");

/// Development seed data: one company, five price zones, users, customers and products.
pub const DEV_SEED_SQL: &str = include_str!("../../../seed/dev_seed.sql");

#[derive(OpenApi)]
#[openapi(
    info(title = "tradocraft API", description = "Business platform API (CRM, products, pricing, sales, engineering, helpdesk, customer portal)."),
    // Query parameters are not collected from the routes: list the enums they use.
    components(schemas(tradocraft_todo::TodoScope)),
    modifiers(&Security),
    security(("bearer" = [])),
    tags(
        (name = "core", description = "Users and companies"),
        (name = "admin", description = "Installation administration: identity providers and who may sign in"),
        (name = "audit", description = "The audit trail: the history of a record and the company-wide view, for administrators"),
        (name = "crm", description = "Customers and opportunities"),
        (name = "products", description = "Products, price zones and price lists"),
        (name = "sales", description = "Quotations, pricing and orders"),
        (name = "favorites", description = "Company-wide favorites for sales lines: a main product with its options and comments, no prices"),
        (name = "engineering", description = "Bills of materials and serial numbers"),
        (name = "helpdesk", description = "Tickets, e-mail and prepared answers"),
        (name = "reports", description = "User-defined reports: build, save, share, run and export"),
        (name = "imports", description = "Data import: upload spreadsheets and CSV files, map their columns, dry-run and apply, with a history of the runs"),
        (name = "todo", description = "To-do items: private checklists with sub-items, hand-over to a colleague and links to records"),
        (name = "kb", description = "Knowledge base: entries in five languages, search, versions, public reading"),
        (name = "repairs", description = "Repairs, workshop departments and photos"),
        (name = "field", description = "Field jobs for technicians: tasks, work logs and photos"),
        (name = "inventory", description = "Warehouses, stock moves, lots, reservations and counts"),
        (name = "planning", description = "Planning board: technician calendars, absences, skills, conflicts and suggestions"),
        (name = "purchasing", description = "Suppliers, price lists, purchase orders and goods receipts"),
        (name = "finance", description = "Supplier invoices (AP register), the three-way match, approval and payment status"),
        (name = "delivery", description = "Delivery notes for sales orders: planning, picking, shipping and the closure policy"),
        (name = "production", description = "Production orders from the BOM: divisions, release, component reservation, completion and output"),
        (name = "configurator", description = "Admin-defined product configurators: models, revisions, formulas, evaluation and saved configurations"),
        (name = "portal", description = "Customer portal: login for contacts, their tickets and profile"),
    )
)]
struct ApiDoc;

struct Security;

impl Modify for Security {
    fn modify(&self, openapi: &mut OpenApiDoc) {
        let components = openapi.components.get_or_insert_with(Default::default);
        components.add_security_scheme(
            "bearer",
            SecurityScheme::Http(
                HttpBuilder::new()
                    .scheme(HttpAuthScheme::Bearer)
                    .bearer_format("JWT")
                    .build(),
            ),
        );
    }
}

fn api() -> (Router<AppState>, OpenApiDoc) {
    let v1 = OpenApiRouter::new()
        .merge(tradocraft_core::company::router())
        .merge(tradocraft_core::environment::router())
        .merge(tradocraft_core::companies::router())
        .merge(tradocraft_core::identity_admin::router())
        .merge(tradocraft_core::audit_log::router())
        .merge(tradocraft_crm::router())
        .merge(tradocraft_products::router())
        .merge(tradocraft_sales::router())
        .merge(tradocraft_engineering::router())
        .merge(tradocraft_helpdesk::router())
        .merge(tradocraft_kb::router())
        .merge(tradocraft_repairs::router())
        .merge(tradocraft_fieldservice::router())
        .merge(tradocraft_inventory::router())
        .merge(tradocraft_planning::router())
        .merge(tradocraft_purchasing::router())
        .merge(tradocraft_finance::router())
        .merge(tradocraft_delivery::router())
        .merge(tradocraft_production::router())
        .merge(tradocraft_configurator::router())
        .merge(tradocraft_reports::router())
        .merge(tradocraft_todo::router())
        .merge(tradocraft_imports::router())
        .merge(tradocraft_portal::router());
    OpenApiRouter::with_openapi(ApiDoc::openapi())
        .nest("/api/v1", v1)
        .split_for_parts()
}

pub fn openapi() -> OpenApiDoc {
    api().1
}

/// The application as a live environment (what tests use).
pub fn app(state: AppState) -> Router {
    app_with_environment(state, EnvironmentConfig::default())
}

/// The application, reporting itself as `environment` on `GET /api/v1/meta/environment`.
pub fn app_with_environment(state: AppState, environment: EnvironmentConfig) -> Router {
    app_with_options(state, environment, BootstrapConfig::default())
}

/// The application with an environment and the bootstrap secret (`BOOTSTRAP_TOKEN`, ADR 0047).
pub fn app_with_options(
    state: AppState,
    environment: EnvironmentConfig,
    bootstrap: BootstrapConfig,
) -> Router {
    app_with_cors(state, environment, bootstrap, &CorsConfig::Any)
}

/// The application answering only the browser origins of `cors` (`CORS_ALLOWED_ORIGINS`,
/// ADR 0050).
pub fn app_with_cors(
    state: AppState,
    environment: EnvironmentConfig,
    bootstrap: BootstrapConfig,
    cors: &CorsConfig,
) -> Router {
    app_with_identity(state, environment, bootstrap, cors, IdpSettings::default())
}

/// The application with the identity provider settings (ADR 0055) the admin API validates and
/// tests providers with; the same settings the registry in `state.auth` runs with.
pub fn app_with_identity(
    state: AppState,
    environment: EnvironmentConfig,
    bootstrap: BootstrapConfig,
    cors: &CorsConfig,
    identity: IdpSettings,
) -> Router {
    // Without a say in the matter the VIES lookup is off: a test must not call the Commission.
    app_with_vies(
        state,
        environment,
        bootstrap,
        cors,
        identity,
        ViesConfig::disabled(),
    )
}

/// The application with the VIES lookup (ADR 0058) pointed at `vies`: the server passes
/// `ViesConfig::from_env()` (`VIES_URL`), a test passes a local stand-in.
pub fn app_with_vies(
    state: AppState,
    environment: EnvironmentConfig,
    bootstrap: BootstrapConfig,
    cors: &CorsConfig,
    identity: IdpSettings,
    vies: ViesConfig,
) -> Router {
    let (router, doc) = api();
    // Bell motors for the product matching of the CRM come from the configurator tables.
    let motors: tradocraft_crm::product_matches::BellMotors =
        std::sync::Arc::new(tradocraft_configurator::motor::ConfiguratorMotors);
    router
        .route("/health", axum::routing::get(|| async { "ok" }))
        .merge(Scalar::with_url("/docs", doc.clone()))
        .route(
            "/api-docs/openapi.json",
            axum::routing::get(move || async move { axum::Json(doc) }),
        )
        .layer(axum::Extension(environment))
        .layer(axum::Extension(bootstrap))
        .layer(axum::Extension(identity))
        .layer(axum::Extension(vies))
        .layer(axum::Extension(motors))
        .layer(TraceLayer::new_for_http())
        .layer(cors.layer())
        .with_state(state)
}

/// Loads development seed data if the database has no company yet.
pub async fn seed_if_empty(db: &sqlx::PgPool) -> anyhow::Result<bool> {
    let companies: i64 = sqlx::query_scalar("SELECT count(*) FROM core.companies")
        .fetch_one(db)
        .await?;
    if companies > 0 {
        return Ok(false);
    }
    sqlx::raw_sql(DEV_SEED_SQL).execute(db).await?;
    // Companies created by provisioning get these themselves; the dev seed inserts its company
    // directly.
    sqlx::query("SELECT crm.seed_baseline_defaults(id) FROM core.companies")
        .execute(db)
        .await?;
    seed_configurators(db).await?;
    Ok(true)
}

/// The id of the development company.
pub const DEV_COMPANY_ID: &str = "00000000-0000-7000-8000-000000000001";

/// Loads the public demo configurator (`seed/configurators/conveyor_line.json`) into the
/// development company.
pub async fn seed_configurators(db: &sqlx::PgPool) -> anyhow::Result<()> {
    let company: uuid::Uuid = DEV_COMPANY_ID.parse()?;
    tradocraft_configurator::seed_demo(db, company)
        .await
        .map_err(|e| anyhow::anyhow!("loading the demo configurator: {e}"))?;
    Ok(())
}

/// Runs every `*.sql` file of `dir` in file-name order, each in its own transaction, after the
/// development seed (`EXTRA_SEED_DIR`). Meant for demo data that is kept outside this repository.
/// Returns the file names that ran; stops at the first failing file.
pub async fn load_extra_seed(
    db: &sqlx::PgPool,
    dir: &std::path::Path,
) -> anyhow::Result<Vec<String>> {
    use anyhow::Context;
    let mut files: Vec<std::path::PathBuf> = std::fs::read_dir(dir)
        .with_context(|| format!("reading EXTRA_SEED_DIR {}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_file() && p.extension().is_some_and(|x| x == "sql"))
        .collect();
    files.sort();
    let mut ran = Vec::new();
    for f in files {
        let sql =
            std::fs::read_to_string(&f).with_context(|| format!("reading {}", f.display()))?;
        let mut tx = db.begin().await?;
        sqlx::raw_sql(&sql)
            .execute(&mut *tx)
            .await
            .with_context(|| format!("running {}", f.display()))?;
        tx.commit().await?;
        ran.push(
            f.file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default(),
        );
    }
    Ok(ran)
}
