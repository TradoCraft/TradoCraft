//! The VIES lookup (ADR 0058, roadmap D4): asks the European Commission's VAT Information
//! Exchange System whether a VAT number is active and, where the member state discloses them,
//! for the registered name and address, so a new customer or supplier can be pre-filled.
//!
//! The lookup is a convenience, never a gate. VIES goes down, rate-limits and, for several member
//! states, answers "valid" without a name. Every failure therefore ends as
//! [`ViesState::Unavailable`] with a short reason, and the caller carries on by hand. Only the VAT
//! number is sent: no credentials, no company data, no requester number.
//!
//! The request is `POST {base}/check-vat-number` with `{"countryCode", "vatNumber"}`. The answer is
//! read leniently (`isValid` or `valid`, an optional `userError`), because the public description
//! of the REST API is not consistent about them. The base URL is configuration (`VIES_URL`), so
//! tests, a proxy or a changed path need no code.

use std::time::Duration;

use serde::Serialize;
use utoipa::ToSchema;

use crate::environment::EnvironmentConfig;
use crate::vat::VatNumber;

/// The Commission's public VIES REST API.
pub const DEFAULT_URL: &str = "https://ec.europa.eu/taxation_customs/vies/rest-api";

/// How long to wait for VIES before giving up. The form waits on this, so it is short.
const TIMEOUT: Duration = Duration::from_secs(8);

/// Where the lookup goes. `None` switches it off (every lookup answers `unavailable`, reason
/// `disabled`).
#[derive(Debug, Clone)]
pub struct ViesConfig {
    base_url: Option<String>,
    timeout: Duration,
}

impl ViesConfig {
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            base_url: Some(base_url.into().trim_end_matches('/').to_string()),
            timeout: TIMEOUT,
        }
    }

    pub fn disabled() -> Self {
        Self {
            base_url: None,
            timeout: TIMEOUT,
        }
    }

    /// `VIES_URL`: unset means the Commission's service, `off` (or empty) switches the lookup off.
    pub fn from_env() -> Self {
        Self::from_value(std::env::var("VIES_URL").ok().as_deref())
    }

    pub fn from_value(value: Option<&str>) -> Self {
        match value.map(str::trim) {
            None => Self::new(DEFAULT_URL),
            Some("") => Self::disabled(),
            Some(v) if v.eq_ignore_ascii_case("off") => Self::disabled(),
            Some(v) => Self::new(v),
        }
    }

    /// The lookup for an environment: `VIES_URL` in a live one, off in any other. A VAT number
    /// leaving the installation is an outbound call, and ADR 0048 gates every outbound integration
    /// by [`EnvironmentConfig::outbound_allowed`]: a clone of live data must not start asking the
    /// outside world about its customers.
    pub fn for_environment(environment: &EnvironmentConfig) -> Self {
        Self::gated(environment, std::env::var("VIES_URL").ok().as_deref())
    }

    fn gated(environment: &EnvironmentConfig, value: Option<&str>) -> Self {
        if environment.outbound_allowed() {
            Self::from_value(value)
        } else {
            Self::disabled()
        }
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    pub fn is_enabled(&self) -> bool {
        self.base_url.is_some()
    }
}

impl Default for ViesConfig {
    /// Off. A test or tool that builds the application without saying otherwise must not call the
    /// Commission by accident; the API server asks for [`ViesConfig::from_env`].
    fn default() -> Self {
        Self::disabled()
    }
}

/// What VIES said.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ViesState {
    /// The number is registered and active.
    Valid,
    /// VIES does not know the number.
    Invalid,
    /// No answer: the lookup is off, VIES or the member state's service is down or busy, or the
    /// answer was not understood. See `reason`. Says nothing about the number.
    Unavailable,
    /// Not a number VIES can look up (not an EU number).
    NotApplicable,
}

/// The outcome of a lookup, ready to pre-fill a form.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct ViesLookup {
    pub state: ViesState,
    /// Why `state` is `unavailable`: `disabled`, `timeout`, `network`, `bad_response`, `http_NNN`,
    /// or the code VIES gave (`ms_unavailable`, `server_busy`, ...).
    pub reason: Option<String>,
    /// The registered name; absent when VIES does not disclose it.
    pub name: Option<String>,
    /// The registered address as VIES wrote it, lines joined by a line break.
    pub address: Option<String>,
    /// The address split as well as it can be: street lines, postal code and city. Absent parts
    /// were not recognised; `address` has the full text.
    pub street: Option<String>,
    pub postal_code: Option<String>,
    pub city: Option<String>,
}

impl ViesLookup {
    fn bare(state: ViesState, reason: Option<&str>) -> Self {
        Self {
            state,
            reason: reason.map(str::to_string),
            name: None,
            address: None,
            street: None,
            postal_code: None,
            city: None,
        }
    }

    pub fn unavailable(reason: &str) -> Self {
        Self::bare(ViesState::Unavailable, Some(reason))
    }

    pub fn not_applicable() -> Self {
        Self::bare(ViesState::NotApplicable, None)
    }
}

/// Looks `v` up. Never fails: see [`ViesState::Unavailable`].
pub async fn lookup(config: &ViesConfig, v: &VatNumber) -> ViesLookup {
    let Some(base) = &config.base_url else {
        return ViesLookup::unavailable("disabled");
    };
    // The VIES country code for Greece is EL, for Northern Ireland XI: the prefix as it stands.
    let client = match reqwest::Client::builder()
        .timeout(config.timeout)
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("tradocraft")
        .build()
    {
        Ok(c) => c,
        Err(_) => return ViesLookup::unavailable("network"),
    };
    let response = client
        .post(format!("{base}/check-vat-number"))
        .json(&serde_json::json!({ "countryCode": v.prefix, "vatNumber": v.number }))
        .send()
        .await;
    let response = match response {
        Ok(r) => r,
        Err(e) if e.is_timeout() => return ViesLookup::unavailable("timeout"),
        Err(_) => return ViesLookup::unavailable("network"),
    };
    let status = response.status().as_u16();
    match response.text().await {
        Ok(body) => parse_response(status, &body, v.prefix),
        Err(e) if e.is_timeout() => ViesLookup::unavailable("timeout"),
        Err(_) => ViesLookup::unavailable("network"),
    }
}

/// Reads a VIES answer. Pure, so the odd cases can be tested without a server.
pub fn parse_response(status: u16, body: &str, prefix: &str) -> ViesLookup {
    let json: Option<serde_json::Value> = serde_json::from_str(body).ok();
    // The error code VIES gives, in the body of an error status or as `userError`.
    let code = json.as_ref().and_then(error_code);
    if let Some(code) = code.as_deref() {
        match code {
            "VALID" => {}
            "INVALID" | "INVALID_INPUT" => return ViesLookup::bare(ViesState::Invalid, None),
            other => return ViesLookup::unavailable(&other.to_ascii_lowercase()),
        }
    }
    if !(200..300).contains(&status) {
        return ViesLookup::unavailable(&format!("http_{status}"));
    }
    let Some(json) = json else {
        return ViesLookup::unavailable("bad_response");
    };
    let valid = json
        .get("isValid")
        .or_else(|| json.get("valid"))
        .and_then(serde_json::Value::as_bool);
    match valid {
        Some(true) => {
            let name = disclosed(json.get("name"));
            let address = disclosed(json.get("address"));
            let parts = address
                .as_deref()
                .map(|a| split_address(a, prefix))
                .unwrap_or_default();
            ViesLookup {
                state: ViesState::Valid,
                reason: None,
                name,
                address,
                street: parts.street,
                postal_code: parts.postal_code,
                city: parts.city,
            }
        }
        Some(false) => ViesLookup::bare(ViesState::Invalid, None),
        None => ViesLookup::unavailable("bad_response"),
    }
}

/// `userError` of a normal answer, or the first error of an error body (`errorWrappers`), upper
/// case.
fn error_code(json: &serde_json::Value) -> Option<String> {
    let text = json
        .get("userError")
        .and_then(serde_json::Value::as_str)
        .or_else(|| {
            json.get("errorWrappers")?
                .as_array()?
                .first()?
                .get("error")?
                .as_str()
        })?;
    let t = text.trim();
    (!t.is_empty()).then(|| t.to_ascii_uppercase())
}

/// A name or address as VIES gives it: text, with `---` (not disclosed) and blanks as absent.
fn disclosed(v: Option<&serde_json::Value>) -> Option<String> {
    let s = v?.as_str()?.trim();
    (!s.is_empty() && s != "---").then(|| s.to_string())
}

/// An address cut into the fields of a form.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AddressParts {
    pub street: Option<String>,
    pub postal_code: Option<String>,
    pub city: Option<String>,
}

/// Splits a VIES address: street lines first, a last line of postal code and city. VIES writes
/// the lines of one address separated by line breaks, in the member state's own order, which for
/// the countries that disclose addresses is street, then "postal code city" (`1000 BRUXELLES`,
/// `B-1000 BRUXELLES`, `1234 AB AMSTERDAM`). Anything else comes back as one street line: the form
/// is a starting point, and the full text stays in [`ViesLookup::address`].
pub fn split_address(address: &str, _prefix: &str) -> AddressParts {
    let lines: Vec<&str> = address
        .split(['\n', '\r'])
        .map(str::trim)
        .filter(|l| !l.is_empty() && *l != "---")
        .collect();
    let Some((last, head)) = lines.split_last() else {
        return AddressParts::default();
    };
    if !head.is_empty() {
        if let Some((postal, city)) = postal_and_city(last) {
            return AddressParts {
                street: Some(head.join(", ")),
                postal_code: Some(postal),
                city: Some(city),
            };
        }
    }
    AddressParts {
        street: Some(lines.join(", ")),
        postal_code: None,
        city: None,
    }
}

/// `1000 BRUXELLES`, `B-1000 BRUXELLES`, `L-1234 LUXEMBOURG`, `1234 AB AMSTERDAM`, `75008 PARIS`.
fn postal_and_city(line: &str) -> Option<(String, String)> {
    // A country letter prefix such as `B-` or `NL-`.
    let line = match line.split_once('-') {
        Some((p, rest))
            if (1..=2).contains(&p.len()) && p.chars().all(|c| c.is_ascii_uppercase()) =>
        {
            rest.trim()
        }
        _ => line,
    };
    let mut tokens = line.split_whitespace();
    let first = tokens.next()?;
    if !(4..=5).contains(&first.len()) || !first.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let mut postal = first.to_string();
    let mut rest: Vec<&str> = tokens.collect();
    // Dutch postal codes carry two letters after the four digits.
    if first.len() == 4 && rest.len() > 1 {
        if let Some(l) = rest.first() {
            if l.len() == 2 && l.chars().all(|c| c.is_ascii_uppercase()) {
                postal = format!("{first} {l}");
                rest.remove(0);
            }
        }
    }
    let city = rest.join(" ");
    (!city.is_empty()).then_some((postal, city))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_reads_the_environment_value() {
        assert!(ViesConfig::from_value(None).is_enabled());
        assert!(ViesConfig::from_value(Some("https://vies.example/api/")).is_enabled());
        for off in ["", "  ", "off", "OFF"] {
            assert!(!ViesConfig::from_value(Some(off)).is_enabled(), "{off:?}");
        }
        // The default of the type is off: nothing calls the Commission by accident.
        assert!(!ViesConfig::default().is_enabled());
    }

    #[test]
    fn only_a_live_environment_may_call_vies() {
        use crate::environment::EnvKind;
        let env = |kind| EnvironmentConfig { name: None, kind };
        assert!(ViesConfig::gated(&env(EnvKind::Live), None).is_enabled());
        // `VIES_URL=off` still switches it off in live.
        assert!(!ViesConfig::gated(&env(EnvKind::Live), Some("off")).is_enabled());
        // Whatever `VIES_URL` says, a clone of live data does not ask the outside world.
        for kind in [EnvKind::Test, EnvKind::Tutorial] {
            assert!(
                !ViesConfig::gated(&env(kind), None).is_enabled(),
                "{kind:?}"
            );
            assert!(
                !ViesConfig::gated(&env(kind), Some("https://vies.example/api")).is_enabled(),
                "{kind:?}"
            );
        }
    }

    #[test]
    fn a_valid_answer_gives_name_and_address() {
        let body = r#"{"isValid": true, "userError": "VALID", "name": "ACME NV",
                       "address": "RUE DE LA LOI 16\n1000 BRUXELLES", "requestDate": "2026-11-13"}"#;
        let r = parse_response(200, body, "BE");
        assert_eq!(r.state, ViesState::Valid);
        assert_eq!(r.name.as_deref(), Some("ACME NV"));
        assert_eq!(r.street.as_deref(), Some("RUE DE LA LOI 16"));
        assert_eq!(r.postal_code.as_deref(), Some("1000"));
        assert_eq!(r.city.as_deref(), Some("BRUXELLES"));
        assert_eq!(r.reason, None);
    }

    #[test]
    fn the_other_spelling_of_the_flag_is_read_too() {
        let r = parse_response(
            200,
            r#"{"valid": true, "name": "ACME", "address": "---"}"#,
            "DE",
        );
        assert_eq!(r.state, ViesState::Valid);
        assert_eq!(r.name.as_deref(), Some("ACME"));
        // `---` is how a member state says it does not disclose it.
        assert_eq!(r.address, None);
        assert_eq!(r.street, None);
    }

    #[test]
    fn an_unknown_number_is_invalid() {
        for body in [
            r#"{"isValid": false, "userError": "INVALID"}"#,
            r#"{"valid": false}"#,
            r#"{"userError": "INVALID_INPUT"}"#,
            r#"{"errorWrappers": [{"error": "INVALID_INPUT", "message": "x"}]}"#,
        ] {
            assert_eq!(
                parse_response(200, body, "BE").state,
                ViesState::Invalid,
                "{body}"
            );
        }
        // An error status that says the input is invalid says it too.
        let r = parse_response(
            400,
            r#"{"errorWrappers": [{"error": "INVALID_INPUT"}]}"#,
            "BE",
        );
        assert_eq!(r.state, ViesState::Invalid);
    }

    #[test]
    fn a_service_that_cannot_answer_is_unavailable_with_its_reason() {
        for (code, reason) in [
            ("MS_UNAVAILABLE", "ms_unavailable"),
            ("SERVICE_UNAVAILABLE", "service_unavailable"),
            ("TIMEOUT", "timeout"),
            ("SERVER_BUSY", "server_busy"),
            ("MS_MAX_CONCURRENT_REQ", "ms_max_concurrent_req"),
            ("SOMETHING_NEW", "something_new"),
        ] {
            let body = format!(r#"{{"isValid": false, "userError": "{code}"}}"#);
            let r = parse_response(200, &body, "BE");
            assert_eq!(r.state, ViesState::Unavailable, "{code}");
            assert_eq!(r.reason.as_deref(), Some(reason), "{code}");
        }
        // The same code in an error body.
        let r = parse_response(
            500,
            r#"{"errorWrappers": [{"error": "MS_UNAVAILABLE"}]}"#,
            "BE",
        );
        assert_eq!(r.reason.as_deref(), Some("ms_unavailable"));
    }

    #[test]
    fn odd_answers_are_unavailable_not_invalid() {
        let r = parse_response(503, "<html>maintenance</html>", "BE");
        assert_eq!(
            (r.state, r.reason.as_deref()),
            (ViesState::Unavailable, Some("http_503"))
        );
        let r = parse_response(200, "not json", "BE");
        assert_eq!(
            (r.state, r.reason.as_deref()),
            (ViesState::Unavailable, Some("bad_response"))
        );
        // JSON without a verdict says nothing about the number.
        let r = parse_response(200, r#"{"name": "X"}"#, "BE");
        assert_eq!(
            (r.state, r.reason.as_deref()),
            (ViesState::Unavailable, Some("bad_response"))
        );
        let r = parse_response(429, "{}", "BE");
        assert_eq!(r.reason.as_deref(), Some("http_429"));
    }

    #[test]
    fn addresses_are_split_for_the_form() {
        let a = |s| split_address(s, "BE");
        assert_eq!(
            a("RUE DE LA LOI 16\n1000 BRUXELLES"),
            AddressParts {
                street: Some("RUE DE LA LOI 16".into()),
                postal_code: Some("1000".into()),
                city: Some("BRUXELLES".into()),
            }
        );
        // A country letter in front of the postal code.
        let p = a("AVENUE X 1\nBOX 2\nB-1050 IXELLES");
        assert_eq!(p.street.as_deref(), Some("AVENUE X 1, BOX 2"));
        assert_eq!(
            (p.postal_code.as_deref(), p.city.as_deref()),
            (Some("1050"), Some("IXELLES"))
        );
        // Dutch postal codes have letters.
        let p = a("KEIZERSGRACHT 1\n1015 CJ AMSTERDAM");
        assert_eq!(p.postal_code.as_deref(), Some("1015 CJ"));
        assert_eq!(p.city.as_deref(), Some("AMSTERDAM"));
        // A city of several words.
        let p = a("RUE X 2\n4000 LIEGE CENTRE");
        assert_eq!(p.city.as_deref(), Some("LIEGE CENTRE"));
        // Not recognised: everything stays in the street.
        let p = a("1 MAIN STREET DUBLIN");
        assert_eq!(p.street.as_deref(), Some("1 MAIN STREET DUBLIN"));
        assert_eq!((p.postal_code, p.city), (None, None));
        // One line cannot be told apart from a street.
        let p = a("1000 BRUXELLES");
        assert_eq!(p.street.as_deref(), Some("1000 BRUXELLES"));
        assert_eq!(a("---\n\n"), AddressParts::default());
        assert_eq!(a(""), AddressParts::default());
    }
}
