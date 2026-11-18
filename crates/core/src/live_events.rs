//! Shared Server-Sent Events (SSE) push channel for live record updates (ADR 0073, D3 / A8).
//!
//! When a record is updated, the handler publishes a `RecordEvent` after the transaction commits.
//! Open edit/detail screens subscribe to `GET /api/v1/events/records?entity_type=...&record_id=...`
//! and receive `record_changed` events immediately so they can warn the user or reload.

use std::convert::Infallible;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;

use axum::extract::{Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use chrono::{DateTime, Utc};
use futures_core::Stream;
use serde::{Deserialize, Serialize};
use tokio::sync::{broadcast, mpsc};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{AppError, AppResult, AppState, CurrentUser, Permission};

const CHANNEL_CAPACITY: usize = 1024;

/// A live change notification emitted after a record is committed.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RecordEvent {
    #[serde(skip_serializing, default)]
    pub company_id: Uuid,
    /// `customer` | `quotation` | `order` | `ticket`
    pub entity_type: String,
    pub record_id: Uuid,
    pub version: i64,
    pub changed_by_id: Uuid,
    pub changed_by_name: String,
    /// `updated` (a save), or for tickets (A8) `note`, `escalated`, `delegated`, `tag`, `time`,
    /// `merge`, `split`, `attachment`, `checklist` and `presence` (someone arrived or started
    /// or stopped replying; the version did not move). `resync` is only produced by the client.
    pub kind: String,
    pub summary: Option<String>,
    pub at: DateTime<Utc>,
}

/// In-process broadcast hub for live record change events.
#[derive(Clone)]
pub struct LiveEvents {
    tx: broadcast::Sender<RecordEvent>,
}

impl Default for LiveEvents {
    fn default() -> Self {
        Self::new()
    }
}

impl LiveEvents {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(CHANNEL_CAPACITY);
        Self { tx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<RecordEvent> {
        self.tx.subscribe()
    }

    pub fn publish(&self, event: RecordEvent) {
        // No active subscribers is normal; ignore SendError.
        let _ = self.tx.send(event);
    }

    pub fn publish_record_change(
        &self,
        user: &CurrentUser,
        entity_type: &str,
        record_id: Uuid,
        version: i64,
        kind: &str,
        summary: Option<String>,
    ) {
        self.publish(RecordEvent {
            company_id: user.company_id,
            entity_type: entity_type.to_string(),
            record_id,
            version,
            changed_by_id: user.user_id,
            changed_by_name: user.display_name.clone(),
            kind: kind.to_string(),
            summary,
            at: Utc::now(),
        });
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct RecordEventsQuery {
    /// `customer` | `quotation` | `order` | `ticket`
    pub entity_type: String,
    pub record_id: Uuid,
}

fn permission_for(entity_type: &str) -> AppResult<Permission> {
    match entity_type {
        "customer" => Ok(Permission::CustomersRead),
        "quotation" => Ok(Permission::QuotationsRead),
        "order" => Ok(Permission::OrdersRead),
        "ticket" => Ok(Permission::HelpdeskRead),
        _ => Err(AppError::Validation(format!(
            "unsupported entity_type: {entity_type}"
        ))),
    }
}

struct SseStream(mpsc::Receiver<Result<Event, Infallible>>);

impl Stream for SseStream {
    type Item = Result<Event, Infallible>;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.0.poll_recv(cx)
    }
}

#[utoipa::path(
    get,
    path = "/events/records",
    tag = "core",
    params(RecordEventsQuery),
    responses(
        (status = 200, description = "Server-sent events stream of record changes", content_type = "text/event-stream"),
        (status = 422, body = crate::error::ErrorBody),
    )
)]
async fn stream_record_events(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(query): Query<RecordEventsQuery>,
) -> AppResult<Sse<impl Stream<Item = Result<Event, Infallible>>>> {
    user.require(permission_for(&query.entity_type)?)?;

    let company_id = user.company_id;
    let entity_type = query.entity_type;
    let record_id = query.record_id;
    let mut rx = state.live_events.subscribe();
    let (tx, mpsc_rx) = mpsc::channel::<Result<Event, Infallible>>(64);

    tokio::spawn(async move {
        loop {
            let received = tokio::select! {
                _ = tx.closed() => break,
                received = rx.recv() => received,
            };
            let event = match received {
                Ok(ev)
                    if ev.company_id == company_id
                        && ev.entity_type == entity_type
                        && ev.record_id == record_id =>
                {
                    Event::default().event("record_changed").json_data(&ev).ok()
                }
                Ok(_) => continue,
                Err(broadcast::error::RecvError::Lagged(_)) => {
                    Some(Event::default().event("resync").data("{}"))
                }
                Err(broadcast::error::RecvError::Closed) => break,
            };
            // Revalidate membership and permissions immediately before delivery.
            let member = tokio::select! {
                _ = tx.closed() => break,
                member = CurrentUser::for_member(&state.db, user.user_id, company_id) => member,
            };
            let Ok(member) = member else { break };
            if member
                .require(permission_for(&entity_type).expect("validated selector"))
                .is_err()
            {
                break;
            }
            if let Some(event) = event {
                if tx.send(Ok(event)).await.is_err() {
                    break;
                }
            }
        }
    });

    Ok(Sse::new(SseStream(mpsc_rx)).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(20))
            .text("ping"),
    ))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(stream_record_events))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permission_mapping_covers_supported_entities() {
        assert_eq!(
            permission_for("customer").unwrap(),
            Permission::CustomersRead
        );
        assert_eq!(
            permission_for("quotation").unwrap(),
            Permission::QuotationsRead
        );
        assert_eq!(permission_for("order").unwrap(), Permission::OrdersRead);
        assert_eq!(permission_for("ticket").unwrap(), Permission::HelpdeskRead);
        assert!(permission_for("unknown").is_err());
    }

    #[test]
    fn publish_and_receive_event() {
        let bus = LiveEvents::new();
        let mut rx = bus.subscribe();
        let company_id = Uuid::now_v7();
        let record_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        bus.publish(RecordEvent {
            company_id,
            entity_type: "ticket".into(),
            record_id,
            version: 2,
            changed_by_id: user_id,
            changed_by_name: "Alice".into(),
            kind: "updated".into(),
            summary: None,
            at: Utc::now(),
        });
        let got = rx.try_recv().unwrap();
        assert_eq!(got.company_id, company_id);
        assert_eq!(got.entity_type, "ticket");
        assert_eq!(got.record_id, record_id);
        assert_eq!(got.version, 2);
    }
}
