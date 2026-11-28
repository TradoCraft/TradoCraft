//! Production API types and endpoints.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ApiError, Client};

/// The routing of one BOM revision.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BomRouting {
    pub bom_id: Uuid,
    pub bom_revision: i32,
    pub bom_status: String,
    pub operations: Vec<RoutingOperation>,
    pub product_id: Uuid,
}

/// One operation of a routing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingOperation {
    pub id: Uuid,
    pub name: String,
    pub notes: String,
    pub position: i32,
    pub run_minutes_per_unit: String,
    pub setup_minutes: i32,
    pub work_centre_code: String,
    pub work_centre_id: Uuid,
    pub work_centre_name: String,
}

/// Replaces the whole routing of a draft BOM revision. The order of the list is the order of the
/// operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BomRoutingInput {
    pub operations: Vec<RoutingOperationInput>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingOperationInput {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_minutes_per_unit: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub setup_minutes: Option<i32>,
    pub work_centre_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionPage {
    pub items: Vec<ProductionSummary>,
    pub total: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionSummary {
    pub behind_schedule: bool,
    pub bom_revision: i32,
    pub created_at: chrono::DateTime<chrono::Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_name: Option<String>,
    pub id: Uuid,
    pub number: String,
    pub operation_count: i64,
    pub operations_done: i64,
    pub order_cancelled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order_number: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_ready_date: Option<chrono::NaiveDate>,
    pub priority: String,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub product_tracking: String,
    pub quantity: String,
    pub short_components: i64,
    pub status: String,
    pub unit: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListProductionOrdersParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mine: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOrder {
    #[serde(flatten)]
    pub summary: ProductionSummary,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actual_cost: Option<ProductionOrderCost>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cancel_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<chrono::DateTime<chrono::Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_quantity: Option<String>,
    pub components: Vec<ProductionComponent>,
    pub notes: String,
    pub operations: Vec<ProductionOperation>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order_line_id: Option<Uuid>,
    pub outputs: Vec<ProductionOutput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_order_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_order_number: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_cost: Option<ProductionOrderCost>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub production_remark: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_end: Option<chrono::NaiveDate>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<chrono::DateTime<chrono::Utc>>,
    pub sub_orders: Vec<ProductionSubOrder>,
}

/// Cost of a production order, in the company currency.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOrderCost {
    pub incomplete: bool,
    pub labour_cost: String,
    pub material_cost: String,
    pub total_cost: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionComponent {
    pub component_code: String,
    pub component_name: String,
    pub component_product_id: Uuid,
    pub consumed_quantity: String,
    pub id: Uuid,
    pub manufactured: bool,
    pub position: i32,
    pub required_quantity: String,
    pub reserved_quantity: String,
    pub scrap_quantity: String,
    pub short: bool,
    pub tracking: String,
    pub unit: String,
}

/// One operation of a production order.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOperation {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actual_minutes: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<chrono::DateTime<chrono::Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_by: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_by_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cost_rate: Option<String>,
    pub id: Uuid,
    pub name: String,
    pub notes: String,
    pub planned_end: chrono::NaiveDate,
    pub planned_minutes: i32,
    pub planned_start: chrono::NaiveDate,
    pub position: i32,
    pub run_minutes_per_unit: String,
    pub setup_minutes: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<chrono::DateTime<chrono::Utc>>,
    pub status: String,
    pub work_centre_code: String,
    pub work_centre_id: Uuid,
    pub work_centre_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOutput {
    pub id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lot_number: Option<String>,
    pub quantity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub serial_number: Option<String>,
    pub stock_move_id: Uuid,
}

/// A production order released for a subassembly of another one.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionSubOrder {
    pub id: Uuid,
    pub number: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_ready_date: Option<chrono::NaiveDate>,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub quantity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_end: Option<chrono::NaiveDate>,
    pub status: String,
    pub unit: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseProductionInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto_release_subassemblies: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order_line_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_order_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_ready_date: Option<chrono::NaiveDate>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start_date: Option<chrono::NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProductionInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_ready_date: Option<chrono::NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CancelProductionInput {
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompleteProductionInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub components: Option<Vec<ProductionComponentActual>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub operations: Option<Vec<ProductionOperationActual>>,
    pub output: ProductionOutputInput,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionComponentActual {
    pub component_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub consumed_quantity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extra_location_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extra_lot_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scrap_quantity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub serial_unit_ids: Option<Vec<Uuid>>,
}

/// The minutes worked on one operation, given when the order is completed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOperationActual {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actual_minutes: Option<i32>,
    pub operation_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOutputInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expiry_date: Option<chrono::NaiveDate>,
    pub location_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lot_number: Option<String>,
    pub quantity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub serial_numbers: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionBuildComponentInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto_release_subassemblies: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionSerialCandidate {
    pub id: Uuid,
    pub location: String,
    pub location_id: Uuid,
    pub serial_number: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ProductionSerialCandidatesParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
}

/// What a planner may change on an operation that is not finished. What is left out stays.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOperationUpdate {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_end: Option<chrono::NaiveDate>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_start: Option<chrono::NaiveDate>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_centre_id: Option<Uuid>,
}

/// Records that an operation is finished and how many minutes it took.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOperationFinish {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actual_minutes: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionOperationMove {
    pub applied: bool,
    pub conflicts: Vec<ProductionMoveConflict>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<ProductionOrder>,
}

/// One problem with a move.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionMoveConflict {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub day: Option<chrono::NaiveDate>,
    pub kind: String,
    pub message_key: String,
    pub severity: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct MoveProductionOperationParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dry_run: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub force: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ProductionOrderPdfParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lang: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionScheduleInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub finite: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start_date: Option<chrono::NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionCapacity {
    pub centres: Vec<ProductionCapacityCentre>,
    pub from: chrono::NaiveDate,
    pub to: chrono::NaiveDate,
}

/// A work centre over the period.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionCapacityCentre {
    pub active: bool,
    pub capacity: i32,
    pub code: String,
    pub days: Vec<ProductionCapacityDay>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    pub id: Uuid,
    pub name: String,
    pub total_available_minutes: i64,
    pub total_load_minutes: i64,
}

/// One day of one work centre.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionCapacityDay {
    pub available_minutes: i64,
    pub date: chrono::NaiveDate,
    pub load_minutes: i64,
    pub overloaded: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProductionCapacityParams {
    pub from: chrono::NaiveDate,
    pub to: chrono::NaiveDate,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
}

/// A period in which a work centre (or the whole plant) does not work.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkCentreClosure {
    pub from_date: chrono::NaiveDate,
    pub id: Uuid,
    pub kind: String,
    pub note: String,
    pub to_date: chrono::NaiveDate,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_centre_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_centre_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListWorkCentreClosuresParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_centre_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<chrono::NaiveDate>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to: Option<chrono::NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkCentreClosureInput {
    pub from_date: chrono::NaiveDate,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    pub to_date: chrono::NaiveDate,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_centre_id: Option<Uuid>,
}

/// A production division with its members.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Division {
    pub active: bool,
    pub code: String,
    pub id: Uuid,
    pub is_member: bool,
    pub members: Vec<DivisionMember>,
    pub name: String,
    pub open_orders: i64,
    pub sort_order: i32,
}

/// A user who works in a division.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DivisionMember {
    pub display_name: String,
    pub user_id: Uuid,
}

/// Input to create or change a division.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DivisionInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub member_user_ids: Option<Vec<Uuid>>,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionPlanningBoard {
    pub centres: Vec<ProductionCapacityCentre>,
    pub from: chrono::NaiveDate,
    pub operations: Vec<ProductionBoardOperation>,
    pub to: chrono::NaiveDate,
}

/// An open operation on the board.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionBoardOperation {
    pub id: Uuid,
    pub late: bool,
    pub locked: bool,
    pub name: String,
    pub order_number: String,
    pub planned_end: chrono::NaiveDate,
    pub planned_minutes: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_ready_date: Option<chrono::NaiveDate>,
    pub planned_start: chrono::NaiveDate,
    pub position: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub predecessor_end: Option<chrono::NaiveDate>,
    pub product_name: String,
    pub production_order_id: Uuid,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub successor_start: Option<chrono::NaiveDate>,
    pub work_centre_id: Uuid,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProductionPlanningBoardParams {
    pub from: chrono::NaiveDate,
    pub to: chrono::NaiveDate,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionCostRollup {
    pub currency: String,
    pub gaps: Vec<ProductionCostGap>,
    pub labour_cost: String,
    pub levels: Vec<ProductionCostLevel>,
    pub material_cost: String,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub quantity: String,
    pub total_cost: String,
    pub unit: String,
    pub unit_cost: String,
}

/// Something that could not be costed and was left out.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionCostGap {
    pub code: String,
    pub kind: String,
}

/// One built product in the roll-up: the product itself and each subassembly below it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionCostLevel {
    pub labour_cost: String,
    pub level: i32,
    pub material_cost: String,
    pub minutes: i64,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub quantity: String,
    pub unit: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ProductionCostRollupParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantity: Option<String>,
}

/// The division that normally builds a product.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductDivision {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductionToRelease {
    pub customer_name: String,
    pub order_id: Uuid,
    pub order_line_id: Uuid,
    pub order_number: String,
    pub ordered: String,
    pub planned: String,
    pub priority: String,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub to_build: String,
}

/// A work centre with its own opening hours.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkCentre {
    pub active: bool,
    pub capacity: i32,
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cost_per_hour: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_name: Option<String>,
    pub hours: Vec<WorkCentreHoursSlot>,
    pub id: Uuid,
    pub name: String,
    pub notes: String,
    pub open_operations: i64,
    pub sort_order: i32,
}

/// A block of working time of a work centre.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkCentreHoursSlot {
    pub end_time: String,
    pub start_time: String,
    pub weekday: i32,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListWorkCentresParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
}

/// Input to create or change a work centre.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkCentreInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capacity: Option<i32>,
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cost_per_hour: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
}

/// Replaces the opening hours of a work centre.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkCentreHoursInput {
    pub slots: Vec<WorkCentreHoursSlot>,
}

impl Client {
    /// `GET /api/v1/boms/{id}/routing`.
    pub async fn get_routing(&self, id: Uuid) -> Result<BomRouting, ApiError> {
        self.get_json(&format!("/api/v1/boms/{id}/routing"), &())
            .await
    }

    /// `PUT /api/v1/boms/{id}/routing`.
    pub async fn set_routing(
        &self,
        id: Uuid,
        body: &BomRoutingInput,
    ) -> Result<BomRouting, ApiError> {
        self.put_json(&format!("/api/v1/boms/{id}/routing"), body)
            .await
    }

    /// `GET /api/v1/production-orders`.
    pub async fn list_production_orders(
        &self,
        params: &ListProductionOrdersParams,
    ) -> Result<ProductionPage, ApiError> {
        self.get_json("/api/v1/production-orders", params).await
    }

    /// `POST /api/v1/production-orders`.
    pub async fn release_production(
        &self,
        body: &ReleaseProductionInput,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_json("/api/v1/production-orders", body).await
    }

    /// `GET /api/v1/production-orders/{id}`.
    pub async fn get_production_order(&self, id: Uuid) -> Result<ProductionOrder, ApiError> {
        self.get_json(&format!("/api/v1/production-orders/{id}"), &())
            .await
    }

    /// `PUT /api/v1/production-orders/{id}`.
    pub async fn update_production_order(
        &self,
        id: Uuid,
        body: &UpdateProductionInput,
    ) -> Result<ProductionOrder, ApiError> {
        self.put_json(&format!("/api/v1/production-orders/{id}"), body)
            .await
    }

    /// `POST /api/v1/production-orders/{id}/cancel`.
    pub async fn cancel_production_order(
        &self,
        id: Uuid,
        body: &CancelProductionInput,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_json(&format!("/api/v1/production-orders/{id}/cancel"), body)
            .await
    }

    /// `POST /api/v1/production-orders/{id}/complete`.
    pub async fn complete_production_order(
        &self,
        id: Uuid,
        body: &CompleteProductionInput,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_json(&format!("/api/v1/production-orders/{id}/complete"), body)
            .await
    }

    /// `POST /api/v1/production-orders/{id}/components/{component_id}/build`.
    pub async fn build_production_component(
        &self,
        id: Uuid,
        component_id: Uuid,
        body: &ProductionBuildComponentInput,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_json(
            &format!("/api/v1/production-orders/{id}/components/{component_id}/build"),
            body,
        )
        .await
    }

    /// `GET /api/v1/production-orders/{id}/components/{component_id}/serial-units`.
    pub async fn production_serial_candidates(
        &self,
        id: Uuid,
        component_id: Uuid,
        params: &ProductionSerialCandidatesParams,
    ) -> Result<Vec<ProductionSerialCandidate>, ApiError> {
        self.get_json(
            &format!("/api/v1/production-orders/{id}/components/{component_id}/serial-units"),
            params,
        )
        .await
    }

    /// `PUT /api/v1/production-orders/{id}/operations/{operation_id}`.
    pub async fn update_production_operation(
        &self,
        id: Uuid,
        operation_id: Uuid,
        body: &ProductionOperationUpdate,
    ) -> Result<ProductionOrder, ApiError> {
        self.put_json(
            &format!("/api/v1/production-orders/{id}/operations/{operation_id}"),
            body,
        )
        .await
    }

    /// `POST /api/v1/production-orders/{id}/operations/{operation_id}/finish`.
    pub async fn finish_production_operation(
        &self,
        id: Uuid,
        operation_id: Uuid,
        body: &ProductionOperationFinish,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_json(
            &format!("/api/v1/production-orders/{id}/operations/{operation_id}/finish"),
            body,
        )
        .await
    }

    /// `PUT /api/v1/production-orders/{id}/operations/{operation_id}/move`.
    pub async fn move_production_operation(
        &self,
        id: Uuid,
        operation_id: Uuid,
        params: &MoveProductionOperationParams,
        body: &ProductionOperationUpdate,
    ) -> Result<ProductionOperationMove, ApiError> {
        self.put_json_with_query(
            &format!("/api/v1/production-orders/{id}/operations/{operation_id}/move"),
            params,
            body,
        )
        .await
    }

    /// `POST /api/v1/production-orders/{id}/operations/{operation_id}/reopen`.
    pub async fn reopen_production_operation(
        &self,
        id: Uuid,
        operation_id: Uuid,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_without_body(&format!(
            "/api/v1/production-orders/{id}/operations/{operation_id}/reopen"
        ))
        .await
    }

    /// `POST /api/v1/production-orders/{id}/operations/{operation_id}/start`.
    pub async fn start_production_operation(
        &self,
        id: Uuid,
        operation_id: Uuid,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_without_body(&format!(
            "/api/v1/production-orders/{id}/operations/{operation_id}/start"
        ))
        .await
    }

    /// `GET /api/v1/production-orders/{id}/pdf`.
    pub async fn production_order_pdf(
        &self,
        id: Uuid,
        params: &ProductionOrderPdfParams,
    ) -> Result<Vec<u8>, ApiError> {
        self.get_bytes_with_query(&format!("/api/v1/production-orders/{id}/pdf"), params)
            .await
    }

    /// `POST /api/v1/production-orders/{id}/reserve`.
    pub async fn reserve_production_components(
        &self,
        id: Uuid,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_without_body(&format!("/api/v1/production-orders/{id}/reserve"))
            .await
    }

    /// `POST /api/v1/production-orders/{id}/schedule`.
    pub async fn schedule_production_order(
        &self,
        id: Uuid,
        body: &ProductionScheduleInput,
    ) -> Result<ProductionOrder, ApiError> {
        self.post_json(&format!("/api/v1/production-orders/{id}/schedule"), body)
            .await
    }

    /// `POST /api/v1/production-orders/{id}/start`.
    pub async fn start_production_order(&self, id: Uuid) -> Result<ProductionOrder, ApiError> {
        self.post_without_body(&format!("/api/v1/production-orders/{id}/start"))
            .await
    }

    /// `GET /api/v1/production/capacity`.
    pub async fn production_capacity(
        &self,
        params: &ProductionCapacityParams,
    ) -> Result<ProductionCapacity, ApiError> {
        self.get_json("/api/v1/production/capacity", params).await
    }

    /// `GET /api/v1/production/closures`.
    pub async fn list_work_centre_closures(
        &self,
        params: &ListWorkCentreClosuresParams,
    ) -> Result<Vec<WorkCentreClosure>, ApiError> {
        self.get_json("/api/v1/production/closures", params).await
    }

    /// `POST /api/v1/production/closures`.
    pub async fn create_work_centre_closure(
        &self,
        body: &WorkCentreClosureInput,
    ) -> Result<WorkCentreClosure, ApiError> {
        self.post_json("/api/v1/production/closures", body).await
    }

    /// `PUT /api/v1/production/closures/{id}`.
    pub async fn update_work_centre_closure(
        &self,
        id: Uuid,
        body: &WorkCentreClosureInput,
    ) -> Result<WorkCentreClosure, ApiError> {
        self.put_json(&format!("/api/v1/production/closures/{id}"), body)
            .await
    }

    /// `DELETE /api/v1/production/closures/{id}`.
    pub async fn delete_work_centre_closure(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/production/closures/{id}"))
            .await
    }

    /// `GET /api/v1/production/divisions`.
    pub async fn list_divisions(&self) -> Result<Vec<Division>, ApiError> {
        self.get_json("/api/v1/production/divisions", &()).await
    }

    /// `POST /api/v1/production/divisions`.
    pub async fn create_division(&self, body: &DivisionInput) -> Result<Division, ApiError> {
        self.post_json("/api/v1/production/divisions", body).await
    }

    /// `PUT /api/v1/production/divisions/{id}`.
    pub async fn update_division(
        &self,
        id: Uuid,
        body: &DivisionInput,
    ) -> Result<Division, ApiError> {
        self.put_json(&format!("/api/v1/production/divisions/{id}"), body)
            .await
    }

    /// `DELETE /api/v1/production/divisions/{id}`.
    pub async fn delete_division(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/production/divisions/{id}"))
            .await
    }

    /// `GET /api/v1/production/planning-board`.
    pub async fn production_planning_board(
        &self,
        params: &ProductionPlanningBoardParams,
    ) -> Result<ProductionPlanningBoard, ApiError> {
        self.get_json("/api/v1/production/planning-board", params)
            .await
    }

    /// `GET /api/v1/production/products/{id}/cost-rollup`.
    pub async fn production_cost_rollup(
        &self,
        id: Uuid,
        params: &ProductionCostRollupParams,
    ) -> Result<ProductionCostRollup, ApiError> {
        self.get_json(
            &format!("/api/v1/production/products/{id}/cost-rollup"),
            params,
        )
        .await
    }

    /// `GET /api/v1/production/products/{id}/division`.
    pub async fn get_product_division(&self, id: Uuid) -> Result<ProductDivision, ApiError> {
        self.get_json(&format!("/api/v1/production/products/{id}/division"), &())
            .await
    }

    /// `PUT /api/v1/production/products/{id}/division`.
    pub async fn set_product_division(
        &self,
        id: Uuid,
        body: &ProductDivision,
    ) -> Result<ProductDivision, ApiError> {
        self.put_json(&format!("/api/v1/production/products/{id}/division"), body)
            .await
    }

    /// `GET /api/v1/production/to-release`.
    pub async fn production_to_release(&self) -> Result<Vec<ProductionToRelease>, ApiError> {
        self.get_json("/api/v1/production/to-release", &()).await
    }

    /// `GET /api/v1/production/work-centres`.
    pub async fn list_work_centres(
        &self,
        params: &ListWorkCentresParams,
    ) -> Result<Vec<WorkCentre>, ApiError> {
        self.get_json("/api/v1/production/work-centres", params)
            .await
    }

    /// `POST /api/v1/production/work-centres`.
    pub async fn create_work_centre(&self, body: &WorkCentreInput) -> Result<WorkCentre, ApiError> {
        self.post_json("/api/v1/production/work-centres", body)
            .await
    }

    /// `PUT /api/v1/production/work-centres/{id}`.
    pub async fn update_work_centre(
        &self,
        id: Uuid,
        body: &WorkCentreInput,
    ) -> Result<WorkCentre, ApiError> {
        self.put_json(&format!("/api/v1/production/work-centres/{id}"), body)
            .await
    }

    /// `DELETE /api/v1/production/work-centres/{id}`.
    pub async fn delete_work_centre(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/production/work-centres/{id}"))
            .await
    }

    /// `PUT /api/v1/production/work-centres/{id}/hours`.
    pub async fn set_work_centre_hours(
        &self,
        id: Uuid,
        body: &WorkCentreHoursInput,
    ) -> Result<WorkCentre, ApiError> {
        self.put_json(&format!("/api/v1/production/work-centres/{id}/hours"), body)
            .await
    }
}
