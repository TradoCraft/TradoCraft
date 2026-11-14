//! A mock identity provider for tests: an axum server on 127.0.0.1 serving discovery and a JWKS,
//! and token minting with three fixed RSA test keys (never used outside tests).
#![allow(dead_code)]

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde_json::{json, Value};

const PEMS: [&str; 3] = [
    include_str!("keys/test_rsa_1.pem"),
    include_str!("keys/test_rsa_2.pem"),
    include_str!("keys/test_rsa_3.pem"),
];
const MODULI: [&str; 3] = [
    "r8S2dVvVr_J9oVbW3_HIdRSsMjkgyt1wlQ430rKFMbNOstDgq3G-g-AleA682b8nEz5vpC24tt4NrCQiRgm33WucO-GJrkIM8sRFxH_9TK4_9EEkwi2At4ysBjcnAV6Y6eMB4Rvr6urcqHEFIgtt1cPm21Q_kNHFBQ7FvqkskcQqB4CfIXGKqnVUJqUgMg7hiXrEvYUt_dhda2ejoVVpnljlI0-GU8yMcBxV08XFMmk4jMEoY_ZnvZo935FHlmmcRkoGSrsaamBTZFxhI2k_xNJfQIGrvsaJ59NHg811kBNQu0_JlK1nWw6mP8ZYmRimUnoC4i03t6U98CfokM6OsQ",
    "4a1rppqOXYloIy2akO62JsMky9AbuTlKNTRC8-qpH-z0a5rU493zbBTunb5bq38oOsZUI7xMYkzETP9Cbo12IZ-G-nDdWbkwr4ocwiIAug-Tv_RRCxM8YYkGFr8mQqQRUSDvQw1ii7MIWlK4Z1Y38REEq2dCPbXH_i6NhQVSf8FxArwuZ5HvvIbhQlqszR0bbg1k2GCPeEgkvo4fkGepSoqtvlEbjMV3TNR3Fqa4RcVaYXnZgXHUOH_yQFh4HudUze5-u3s1CHsKzWrAAj3AOAUeEn2fMTgH9lmH6qsnk--8-VkZDNansfngq3bAAR0CgJnRjy2zJBBpwE1vfmQGww",
    "3wqIHZXEw6pC5dAH_a4VWjJyDbFg3NlkSX5oemxybjaYYpB8P0RJaAwiyv8Wz2W9h43K5YUM-jxMf6b97PZgbhU2G1Qbg9WLef0bQUhoxN5YUIP2GCTZrWgMD6OfgSWPYx6Ftg9ibBHGd33Y_7SsYTCNBU_eDj4J1JuCHxjAkmQsQDcPeFkOZgIqmmO2CfueU99ph3JLSleyOAQ2YpSAYKglY8FW9YvcRD7sd361CcTJmczMumPtNKmVvxHhMXjsrxD7vharII4SMidki3k1bi6aLhG5MvYYMxp3fgjcgriPE756LGzlyRvzWvbWUyKbQ661CHZiVVwy4oIpWWVwvw",
];

struct Inner {
    base: String,
    keys: Mutex<Vec<(String, usize)>>,
    jwks_hits: AtomicUsize,
    discovery_issuer: Mutex<Option<String>>,
}

/// A running mock identity provider.
pub struct MockIdp {
    inner: Arc<Inner>,
    /// The issuer URL, `http://127.0.0.1:<port>/<prefix>`.
    pub issuer: String,
}

async fn discovery(State(s): State<Arc<Inner>>) -> Json<Value> {
    let issuer = s
        .discovery_issuer
        .lock()
        .unwrap()
        .clone()
        .unwrap_or_else(|| s.base.clone());
    Json(json!({
        "issuer": issuer,
        "jwks_uri": format!("{}/jwks", s.base),
        "claims_supported": ["sub", "email", "email_verified"],
    }))
}

async fn jwks(State(s): State<Arc<Inner>>) -> Json<Value> {
    s.jwks_hits.fetch_add(1, Ordering::SeqCst);
    let keys: Vec<Value> = s
        .keys
        .lock()
        .unwrap()
        .iter()
        .map(|(kid, i)| {
            json!({"kty": "RSA", "kid": kid, "use": "sig", "alg": "RS256", "n": MODULI[*i], "e": "AQAB"})
        })
        .collect();
    Json(json!({ "keys": keys }))
}

impl MockIdp {
    /// Starts a provider whose only key has id `kid` and is test key `key` (0..3).
    pub async fn start(prefix: &str, kid: &str, key: usize) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let base = format!("http://127.0.0.1:{port}/{prefix}");
        let inner = Arc::new(Inner {
            base: base.clone(),
            keys: Mutex::new(vec![(kid.to_string(), key)]),
            jwks_hits: AtomicUsize::new(0),
            discovery_issuer: Mutex::new(None),
        });
        let app = Router::new()
            .route(
                &format!("/{prefix}/.well-known/openid-configuration"),
                get(discovery),
            )
            .route(&format!("/{prefix}/jwks"), get(jwks))
            .with_state(inner.clone());
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        Self {
            inner,
            issuer: base,
        }
    }

    /// Replaces the published keys: `(kid, test key index)`.
    pub fn set_keys(&self, keys: Vec<(&str, usize)>) {
        *self.inner.keys.lock().unwrap() =
            keys.into_iter().map(|(k, i)| (k.to_string(), i)).collect();
    }

    /// Makes discovery claim another issuer.
    pub fn set_discovery_issuer(&self, issuer: &str) {
        *self.inner.discovery_issuer.lock().unwrap() = Some(issuer.to_string());
    }

    /// How many times the JWKS was fetched.
    pub fn jwks_hits(&self) -> usize {
        self.inner.jwks_hits.load(Ordering::SeqCst)
    }

    /// Standard claims for this provider: issuer, `aud`, `sub`, valid for an hour.
    pub fn claims(&self, aud: &str, sub: &str) -> Value {
        json!({"iss": self.issuer, "aud": aud, "sub": sub, "exp": now() + 3600})
    }

    /// An RS256 token signed with test key `key`, header `kid`.
    pub fn token(&self, kid: &str, key: usize, claims: &Value) -> String {
        sign(
            Algorithm::RS256,
            Some(kid),
            &EncodingKey::from_rsa_pem(PEMS[key].as_bytes()).unwrap(),
            claims,
        )
    }
}

/// Seconds since the epoch.
pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
}

/// Signs `claims` with any algorithm and key.
pub fn sign(alg: Algorithm, kid: Option<&str>, key: &EncodingKey, claims: &Value) -> String {
    let mut h = Header::new(alg);
    h.kid = kid.map(str::to_string);
    jsonwebtoken::encode(&h, claims, key).unwrap()
}
