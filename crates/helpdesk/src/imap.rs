//! Polling a mailbox over IMAP (TLS) and turning unread messages into tickets.

use std::sync::Arc;

use anyhow::Context;
use futures::TryStreamExt;
use sqlx::PgPool;
use tokio::net::TcpStream;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::rustls::{ClientConfig, RootCertStore};
use tokio_rustls::TlsConnector;
use uuid::Uuid;

use crate::ingest;

#[derive(Debug, Clone)]
pub struct ImapConfig {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub password: String,
    pub mailbox: String,
    /// TLS (IMAPS). Only disable for a local test server.
    pub tls: bool,
    /// The company whose helpdesk receives the mails.
    pub company_id: Uuid,
    /// The helpdesk mailbox this is (ADR 0054); empty for the worker's `IMAP_*` variables.
    pub source: Option<ingest::Source>,
}

/// Fetches unread messages, ingests each one and marks it as read. Returns the number processed.
/// A message is only marked read after it has been stored, so nothing is lost if this fails.
pub async fn poll(db: &PgPool, cfg: &ImapConfig) -> anyhow::Result<usize> {
    let tcp = TcpStream::connect((cfg.host.as_str(), cfg.port))
        .await
        .context("connecting to IMAP server")?;
    if !cfg.tls {
        return fetch_unseen(db, cfg, async_imap::Client::new(tcp)).await;
    }
    let mut roots = RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let tls = TlsConnector::from(Arc::new(
        ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth(),
    ));
    let stream = tls
        .connect(ServerName::try_from(cfg.host.clone())?, tcp)
        .await
        .context("TLS handshake with IMAP server")?;
    fetch_unseen(db, cfg, async_imap::Client::new(stream)).await
}

async fn fetch_unseen<T>(
    db: &PgPool,
    cfg: &ImapConfig,
    mut client: async_imap::Client<T>,
) -> anyhow::Result<usize>
where
    T: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + std::fmt::Debug + Send,
{
    client
        .read_response()
        .await
        .context("no IMAP greeting")?
        .context("reading IMAP greeting")?;
    let mut session = client
        .login(&cfg.user, &cfg.password)
        .await
        .map_err(|(e, _)| e)
        .context("IMAP login")?;
    session.select(&cfg.mailbox).await?;

    let uids: Vec<u32> = session.uid_search("UNSEEN").await?.into_iter().collect();
    let mut processed = 0;
    for uid in uids {
        let fetched: Vec<_> = session
            .uid_fetch(uid.to_string(), "BODY.PEEK[]")
            .await?
            .try_collect()
            .await?;
        for f in &fetched {
            let Some(raw) = f.body() else { continue };
            match ingest::ingest_from(db, cfg.company_id, raw, cfg.source).await {
                Ok(r) => {
                    tracing::info!(ticket = %r.ticket_number, new = r.new_ticket, "e-mail ingested")
                }
                Err(e) => {
                    tracing::error!(uid, error = ?e, "could not ingest e-mail; it stays unread");
                    continue;
                }
            }
            let _: Vec<_> = session
                .uid_store(uid.to_string(), "+FLAGS (\\Seen)")
                .await?
                .try_collect()
                .await?;
            processed += 1;
        }
    }
    session.logout().await.ok();
    Ok(processed)
}
