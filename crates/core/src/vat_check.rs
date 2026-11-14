//! The answer of a VAT check, shared by the customer and supplier endpoints (ADR 0058, roadmap D4).
//!
//! A check is advice for a form, not a gate: it reports what is wrong with a number, which records
//! already carry it, and, when asked, what VIES knows. The modules that own customers and suppliers
//! look the duplicates up (they own those tables) and hand them to [`VatCheck::build`].

use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::vat::{self, Parsed, VatNumber, Verdict};
use crate::vies::{self, ViesConfig, ViesLookup};

/// What the local rules say about the number.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum VatStatus {
    /// Nothing was given.
    Empty,
    /// Not an EU number: stored as typed, no rule applies.
    NotChecked,
    /// Format and check digits are right.
    Valid,
    /// The format is right; this country's check digits are not verified here.
    FormatOk,
    BadFormat,
    BadChecksum,
}

/// A record that carries the same VAT number.
#[derive(Debug, Clone, Serialize, ToSchema, sqlx::FromRow)]
pub struct VatDuplicate {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub active: bool,
}

/// The query of a check, the same for customers and suppliers.
#[derive(Debug, Deserialize, IntoParams)]
pub struct VatCheckParams {
    /// The number as typed, with or without prefix, spaces and dots.
    pub vat_number: String,
    /// The country of the customer or supplier (ISO 3166-1 alpha-2): the prefix of a number typed
    /// without one.
    pub country_code: Option<String>,
    /// A record to leave out of the duplicates: the one being edited.
    pub exclude_id: Option<Uuid>,
    /// Also ask VIES, for the name and address (needs the write permission of the module).
    pub lookup: Option<bool>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct VatCheck {
    /// The number as given.
    pub vat_number: String,
    /// An EU number in its VIES form (`BE0428759497`), to store or look up; absent otherwise.
    pub normalized: Option<String>,
    pub status: VatStatus,
    /// What is wrong, in words, when `status` is `bad_format` or `bad_checksum`.
    pub message: Option<String>,
    /// Other records with the same number (at most 10). A warning only: two branches of one
    /// company share a number legitimately.
    pub duplicates: Vec<VatDuplicate>,
    /// VIES's answer; present only when a lookup was asked for.
    pub vies: Option<ViesLookup>,
}

/// What the local rules found, and what is needed to look for duplicates.
#[derive(Debug, Clone)]
pub struct Assessment {
    pub raw: String,
    pub status: VatStatus,
    pub eu: Option<VatNumber>,
    /// Keys (see `core.vat_key`, [`vat::key`]) under which the same number may be stored.
    pub keys: Vec<String>,
    /// The bare national part (in each spelling it is written in), to match numbers stored
    /// without a prefix, together with the country codes such a record must be in.
    pub bare: Option<(Vec<String>, Vec<String>)>,
}

/// Judges a typed number with the rules of this module.
pub fn assess(raw: &str, default_country: Option<&str>) -> Assessment {
    let mut a = Assessment {
        raw: raw.to_string(),
        status: VatStatus::Empty,
        eu: None,
        keys: Vec::new(),
        bare: None,
    };
    match vat::parse(raw, default_country) {
        Parsed::Empty => {}
        Parsed::Other(_) => {
            a.status = VatStatus::NotChecked;
            a.keys.push(vat::key(raw));
        }
        Parsed::Eu(v) => {
            a.status = match vat::validate(&v) {
                Verdict::Valid => VatStatus::Valid,
                Verdict::FormatOk => VatStatus::FormatOk,
                Verdict::BadFormat => VatStatus::BadFormat,
                Verdict::BadChecksum => VatStatus::BadChecksum,
            };
            // The number in every spelling it is written in (Belgian numbers with and without the
            // leading 0), each reduced the way the database reduces stored numbers.
            let numbers: Vec<String> = std::iter::once(v.number.clone())
                .chain(v.equivalent_numbers())
                .collect();
            a.keys = numbers
                .iter()
                .map(|n| vat::key(&format!("{}{n}", v.prefix)))
                .collect();
            // A number stored without its prefix is the same number when its record is in the
            // country of the prefix (Greece: EL for the number, GR for the country).
            let countries = if v.prefix == "EL" {
                vec!["EL".to_string(), "GR".to_string()]
            } else {
                vec![v.prefix.to_string()]
            };
            a.bare = Some((numbers.iter().map(|n| vat::key(n)).collect(), countries));
            a.eu = Some(v);
        }
    }
    a
}

impl Assessment {
    /// True when there is something to look for.
    pub fn has_number(&self) -> bool {
        self.status != VatStatus::Empty
    }

    /// True when the local rules do not rule the number out: worth asking VIES about.
    pub fn lookup_worthwhile(&self) -> bool {
        matches!(self.status, VatStatus::Valid | VatStatus::FormatOk)
    }

    /// Puts the answer together. `duplicates` come from the module's own tables.
    pub async fn build(
        self,
        duplicates: Vec<VatDuplicate>,
        lookup: Option<&ViesConfig>,
    ) -> VatCheck {
        let message = match (self.status, &self.eu) {
            (VatStatus::BadFormat | VatStatus::BadChecksum, Some(_)) => {
                vat::problem(&self.raw, self.eu.as_ref().map(|v| v.prefix))
            }
            _ => None,
        };
        let vies = match lookup {
            None => None,
            Some(cfg) => Some(match (&self.eu, self.lookup_worthwhile()) {
                (Some(v), true) => vies::lookup(cfg, v).await,
                _ => ViesLookup::not_applicable(),
            }),
        };
        VatCheck {
            vat_number: self.raw,
            normalized: self.eu.as_ref().map(VatNumber::full),
            status: self.status,
            message,
            duplicates,
            vies,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assess_reads_prefix_country_and_foreign_numbers() {
        let a = assess("be 0428.759.497", None);
        assert_eq!(a.status, VatStatus::Valid);
        // Both spellings of a Belgian number: with and without the leading 0.
        assert_eq!(
            a.keys,
            vec!["BE0428759497".to_string(), "BE428759497".to_string()]
        );
        assert_eq!(
            a.bare,
            Some((
                vec!["0428759497".to_string(), "428759497".to_string()],
                vec!["BE".to_string()]
            ))
        );
        let a = assess("BE428759497", None);
        assert_eq!(
            a.keys,
            vec!["BE428759497".to_string(), "BE0428759497".to_string()]
        );

        let a = assess("0428.759.497", Some("BE"));
        assert_eq!(a.eu.unwrap().full(), "BE0428759497");

        let a = assess("123456789", Some("GR"));
        assert_eq!(a.eu.as_ref().unwrap().prefix, "EL");
        assert_eq!(a.bare.unwrap().1, vec!["EL".to_string(), "GR".to_string()]);

        let a = assess("CHE-123.456.789", Some("CH"));
        assert_eq!(a.status, VatStatus::NotChecked);
        assert_eq!(a.keys, vec!["CHE123456789".to_string()]);
        // Punctuation the typed-number rules keep is still dropped from the key, like in the database.
        let a = assess("CHE-123.456.789 (MWST)", Some("CH"));
        assert_eq!(a.keys, vec!["CHE123456789MWST".to_string()]);
        assert!(a.eu.is_none() && a.bare.is_none() && !a.lookup_worthwhile());

        let a = assess("  ", Some("BE"));
        assert_eq!(a.status, VatStatus::Empty);
        assert!(!a.has_number());
    }

    #[tokio::test]
    async fn build_names_the_problem_and_skips_vies_for_a_bad_number() {
        let c = assess("BE0428759498", None)
            .build(Vec::new(), Some(&ViesConfig::disabled()))
            .await;
        assert_eq!(c.status, VatStatus::BadChecksum);
        assert!(c.message.unwrap().contains("check digits"));
        assert_eq!(c.vies.unwrap().state, vies::ViesState::NotApplicable);
        assert_eq!(c.normalized.as_deref(), Some("BE0428759498"));
    }

    #[tokio::test]
    async fn build_asks_vies_only_when_told_to_and_for_a_plausible_number() {
        let asked = assess("BE0428759497", None).build(Vec::new(), None).await;
        assert!(asked.vies.is_none());
        // A disabled lookup is reported, not hidden.
        let c = assess("BE0428759497", None)
            .build(Vec::new(), Some(&ViesConfig::disabled()))
            .await;
        let v = c.vies.unwrap();
        assert_eq!(v.state, vies::ViesState::Unavailable);
        assert_eq!(v.reason.as_deref(), Some("disabled"));
    }
}
