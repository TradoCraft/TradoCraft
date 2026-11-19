use axum::http::request::Parts;
use rmcp::{
    handler::server::{tool::Extension, wrapper::Parameters},
    model::{CallToolResult, ServerCapabilities, ServerConfig},
    schemars, tool, tool_router, ErrorData, ServerHandler,
};
use serde::Deserialize;
use sqlx::PgPool;
use tradocraft_core::error::AppError;
use tradocraft_sales::orders::read_order;
use uuid::Uuid;

use crate::auth::DelegatedUser;

#[derive(Clone)]
pub(crate) struct OrderTools {
    db: PgPool,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct GetOrder {
    /// UUID of the sales order.
    order_id: Uuid,
}

#[tool_router]
impl OrderTools {
    pub(crate) fn new(db: PgPool) -> Self {
        Self { db }
    }

    #[tool(
        name = "get_order",
        description = "Look up a sales order's status, revision, and total by UUID in the authorized company.",
        annotations(
            read_only_hint = true,
            destructive_hint = false,
            open_world_hint = false
        )
    )]
    async fn get_order(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(input): Parameters<GetOrder>,
    ) -> Result<CallToolResult, ErrorData> {
        let delegated = parts
            .extensions
            .get::<DelegatedUser>()
            .ok_or_else(|| ErrorData::internal_error("missing authorization context", None))?;
        let result = read_order(&self.db, &delegated.user, input.order_id).await;
        tracing::info!(
            user_id = %delegated.user.user_id,
            company_id = %delegated.user.company_id,
            client_id = %delegated.client_id,
            order_id = %input.order_id,
            tool = "get_order",
            success = result.is_ok(),
            "MCP tool call"
        );
        match result {
            Ok(order) => Ok(CallToolResult::structured(serde_json::json!({
                "id": order.order.id,
                "number": order.order.number,
                "status": order.order.status,
                "revision": order.revision,
                "currency": order.order.currency,
                "total": order.order.total
            }))),
            Err(AppError::NotFound(_) | AppError::Forbidden(_)) => Ok(CallToolResult::error(vec![
                rmcp::model::ContentBlock::text("Order is unavailable to this user."),
            ])),
            Err(error) => {
                tracing::error!(%error, "MCP order read failed");
                Err(ErrorData::internal_error("Order lookup failed", None))
            }
        }
    }
}

#[rmcp::tool_handler]
impl ServerHandler for OrderTools {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
    }
}
