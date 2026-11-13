//! VAT numbers: parsing, format and check-digit validation (ADR 0058, roadmap D4).
//!
//! Pure functions, no I/O. The VIES lookup is in [`crate::vies`]; the duplicate warning needs the
//! database and lives with the modules that own customers and suppliers.
//!
//! Only numbers of EU member states (and `XI`, Northern Ireland) are validated. Anything else is
//! stored as typed: a Swiss, British or American tax number has no rule here, and refusing it would
//! block a customer for no reason. Countries without a check-digit rule in this module get the format
//! test only and say so ([`Verdict::FormatOk`]); a wrong number there is not caught.

use serde::Serialize;
use utoipa::ToSchema;

/// VIES prefixes of the member states, plus `XI` (Northern Ireland, goods only). Greece is `EL`
/// here, as in VIES, although its ISO country code is `GR`.
pub const EU_PREFIXES: [&str; 28] = [
    "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "EL", "ES", "FI", "FR", "HR", "HU", "IE", "IT",
    "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK", "XI",
];

/// The VIES prefix for an ISO 3166 country code: the same two letters, except Greece (`GR` ->
/// `EL`). `None` for a country outside the EU (the United Kingdom included).
pub fn vies_prefix(iso_country: &str) -> Option<&'static str> {
    let c = iso_country.trim().to_ascii_uppercase();
    let c = if c == "GR" { "EL" } else { c.as_str() };
    EU_PREFIXES.iter().copied().find(|p| *p == c)
}

/// An EU VAT number split into its VIES prefix and the national part, both compacted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VatNumber {
    pub prefix: &'static str,
    pub number: String,
}

impl VatNumber {
    /// Prefix and national part together, the form to compare and look up (`BE0428759497`).
    pub fn full(&self) -> String {
        format!("{}{}", self.prefix, self.number)
    }
}

/// What a typed VAT number turns out to be.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Parsed {
    /// Nothing typed.
    Empty,
    /// Not an EU VAT number (another country's prefix, or no prefix and no EU country to assume).
    /// Never validated. Holds the compacted text.
    Other(String),
    /// An EU VAT number, to validate.
    Eu(VatNumber),
}

/// How a VAT number fares.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum Verdict {
    /// The format and the check digits are right.
    Valid,
    /// The format is right, but this country has no check-digit rule here, so a typo can pass.
    FormatOk,
    /// The prefix is known but the rest does not have the shape of a number of that country.
    BadFormat,
    /// The shape is right and the check digits are wrong: almost always a typo.
    BadChecksum,
}

/// Removes what people put inside VAT numbers (spaces, dots, dashes, slashes, commas, underscores)
/// and upper-cases. Anything else stays, so a stray character fails the format test instead of
/// vanishing.
pub fn compact(raw: &str) -> String {
    raw.chars()
        .filter(|c| !c.is_whitespace() && !matches!(c, '.' | '-' | '/' | ',' | '_'))
        .flat_map(char::to_uppercase)
        .collect()
}

/// Reads a typed VAT number. A two-letter EU prefix names the country; without letters the number
/// is taken to be one of `default_country` (an ISO code, the customer's or supplier's country) when
/// that is in the EU.
pub fn parse(raw: &str, default_country: Option<&str>) -> Parsed {
    let c = compact(raw);
    if c.is_empty() {
        return Parsed::Empty;
    }
    let bytes = c.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1].is_ascii_alphabetic() {
        // Two letters up front: a prefix. `GR` is accepted for Greece, though VIES says `EL`.
        return match vies_prefix(&c[..2]) {
            Some(prefix) => Parsed::Eu(VatNumber {
                prefix,
                number: c[2..].to_string(),
            }),
            None => Parsed::Other(c),
        };
    }
    match default_country.and_then(vies_prefix) {
        Some(prefix) => Parsed::Eu(VatNumber { prefix, number: c }),
        None => Parsed::Other(c),
    }
}

/// Validates an EU VAT number: its format and, where this module knows the rule, its check digits.
pub fn validate(v: &VatNumber) -> Verdict {
    let n = v.number.as_str();
    let Some(shape) = shapes(v.prefix).iter().find(|p| matches_shape(p, n)) else {
        return Verdict::BadFormat;
    };
    let _ = shape;
    match checksum(v.prefix, n) {
        Some(true) => Verdict::Valid,
        Some(false) => Verdict::BadChecksum,
        None => Verdict::FormatOk,
    }
}

/// Parses and validates in one go. `None` when there is nothing to validate (empty, or not an EU
/// number); the broken rule's message otherwise.
pub fn problem(raw: &str, default_country: Option<&str>) -> Option<String> {
    match parse(raw, default_country) {
        Parsed::Empty | Parsed::Other(_) => None,
        Parsed::Eu(v) => match validate(&v) {
            Verdict::Valid | Verdict::FormatOk => None,
            Verdict::BadFormat => Some(format!(
                "VAT number {} is not shaped like a {} VAT number",
                v.full(),
                v.prefix
            )),
            Verdict::BadChecksum => Some(format!(
                "VAT number {} has wrong check digits: please check for a typo",
                v.full()
            )),
        },
    }
}

/// True when `a` and `b` are the same VAT number once compacted and given their prefix. Used to
/// leave an unchanged legacy value alone when other fields of a record are edited.
pub fn same_number(a: &str, b: &str, default_country: Option<&str>) -> bool {
    let key = |s: &str| match parse(s, default_country) {
        Parsed::Empty => String::new(),
        Parsed::Other(c) => c,
        Parsed::Eu(v) => v.full(),
    };
    key(a) == key(b)
}

// ---- shapes ----------------------------------------------------------------------------------

/// The accepted shapes per prefix. Tokens: `d` digit, `l` letter, `x` letter or digit; anything
/// else (upper case) stands for itself.
fn shapes(prefix: &str) -> &'static [&'static str] {
    match prefix {
        "AT" => &["Udddddddd"],
        // Ten digits starting 0 or 1; the nine-digit form without the leading 0 is still written.
        "BE" => &["0ddddddddd", "1ddddddddd", "ddddddddd"],
        "BG" => &["ddddddddd", "dddddddddd"],
        "CY" => &["ddddddddl"],
        "CZ" => &["dddddddd", "ddddddddd", "dddddddddd"],
        "DE" => &["ddddddddd"],
        "DK" => &["dddddddd"],
        "EE" => &["ddddddddd"],
        "EL" => &["dddddddd", "ddddddddd"],
        "ES" => &["xdddddddx"],
        "FI" => &["dddddddd"],
        "FR" => &["xxddddddddd"],
        "HR" => &["ddddddddddd"],
        "HU" => &["dddddddd"],
        "IE" => &["dddddddl", "dddddddll", "dlddddd l"],
        "IT" => &["ddddddddddd"],
        "LT" => &["ddddddddd", "dddddddddddd"],
        "LU" => &["dddddddd"],
        "LV" => &["ddddddddddd"],
        "MT" => &["dddddddd"],
        "NL" => &["dddddddddBdd"],
        "PL" => &["dddddddddd"],
        "PT" => &["ddddddddd"],
        "RO" => &[
            "dd",
            "ddd",
            "dddd",
            "ddddd",
            "dddddd",
            "ddddddd",
            "dddddddd",
            "ddddddddd",
            "dddddddddd",
            "ddddddddddddd",
        ],
        "SE" => &["dddddddddddd"],
        "SI" => &["dddddddd"],
        "SK" => &["dddddddddd"],
        "XI" => &["ddddddddd", "dddddddddddd", "GDddd", "HAddd"],
        _ => &[],
    }
}

fn matches_shape(shape: &str, s: &str) -> bool {
    // The one shape with a space is Ireland's old form `9L99999L`; the space only separates the
    // letter from the five digits in the table above and is not part of the number.
    let shape: Vec<char> = shape.chars().filter(|c| *c != ' ').collect();
    let s: Vec<char> = s.chars().collect();
    shape.len() == s.len()
        && shape.iter().zip(&s).all(|(t, c)| match t {
            'd' => c.is_ascii_digit(),
            'l' => c.is_ascii_uppercase(),
            'x' => c.is_ascii_uppercase() || c.is_ascii_digit(),
            lit => lit == c,
        })
}

// ---- check digits -----------------------------------------------------------------------------

/// `Some(true/false)` when this country's check digits are known and right/wrong, `None` when no
/// rule is implemented. Only called with a string that already matched a shape of the prefix.
fn checksum(prefix: &str, n: &str) -> Option<bool> {
    let d = |s: &str| -> Vec<u32> { s.chars().filter_map(|c| c.to_digit(10)).collect() };
    match prefix {
        "AT" => {
            let x = d(&n[1..]);
            let sum: u32 = x[..7]
                .iter()
                .enumerate()
                .map(|(i, v)| {
                    let p = v * if i % 2 == 0 { 1 } else { 2 };
                    p / 10 + p % 10
                })
                .sum();
            Some((10 - (sum + 4) % 10) % 10 == x[7])
        }
        "BE" => {
            let padded = if n.len() == 9 {
                format!("0{n}")
            } else {
                n.to_string()
            };
            let head: u64 = padded[..8].parse().ok()?;
            let check: u64 = padded[8..].parse().ok()?;
            // The check digits complete the first eight to a multiple of 97. Written as a sum so
            // that the check digits 00, 98 and 99 pass too, as they do in the other validators.
            Some((head + check).is_multiple_of(97))
        }
        "DE" => {
            let x = d(n);
            Some(x[0] != 0 && mod_11_10_valid(&x[..8], x[8]))
        }
        "DK" => {
            let x = d(n);
            let w = [2, 7, 6, 5, 4, 3, 2, 1];
            Some(x[0] != 0 && x.iter().zip(w).map(|(a, b)| a * b).sum::<u32>() % 11 == 0)
        }
        "EE" => {
            let x = d(n);
            let w = [3, 7, 1, 3, 7, 1, 3, 7];
            let sum: u32 = x[..8].iter().zip(w).map(|(a, b)| a * b).sum();
            Some((10 - sum % 10) % 10 == x[8])
        }
        "EL" => {
            let padded = format!("{n:0>9}");
            let x = d(&padded);
            let sum: u32 = x[..8]
                .iter()
                .enumerate()
                .map(|(i, v)| v * (1u32 << (8 - i)))
                .sum();
            Some(sum % 11 % 10 == x[8])
        }
        "FI" => {
            let x = d(n);
            let w = [7, 9, 10, 5, 8, 4, 2];
            let sum: u32 = x[..7].iter().zip(w).map(|(a, b)| a * b).sum();
            let check = 11 - sum % 11;
            Some(match check {
                11 => x[7] == 0,
                10 => false,
                c => x[7] == c,
            })
        }
        "FR" => {
            let (key, siren) = n.split_at(2);
            if !key.chars().all(|c| c.is_ascii_digit()) {
                // Keys with letters (introduced for the numbers that ran out) have their own rule.
                return None;
            }
            let siren_n: u64 = siren.parse().ok()?;
            let expected = (siren_n * 100 + 12) % 97;
            let key_n: u64 = key.parse().ok()?;
            Some(key_n == expected && luhn_valid(siren))
        }
        "HR" => {
            let x = d(n);
            Some(mod_11_10_valid(&x[..10], x[10]))
        }
        "HU" => {
            let x = d(n);
            let w = [9, 7, 3, 1, 9, 7, 3, 1];
            Some(x.iter().zip(w).map(|(a, b)| a * b).sum::<u32>() % 10 == 0)
        }
        "IT" => {
            let x = d(n);
            Some(x[..7].iter().any(|v| *v != 0) && luhn_valid(n))
        }
        "LU" => {
            let head: u32 = n[..6].parse().ok()?;
            let check: u32 = n[6..].parse().ok()?;
            Some(head % 89 == check)
        }
        "NL" => {
            let (digits, rest) = n.split_at(9);
            let x = d(digits);
            let _ = rest;
            if x.iter().all(|v| *v == 0) {
                return Some(false);
            }
            // The old form: the first nine digits are a citizen service number (11-proof). Since
            // 2020 sole proprietors get an id that follows ISO 7064 mod 97-10 instead.
            let eleven: i64 = x[..8]
                .iter()
                .enumerate()
                .map(|(i, v)| i64::from(*v) * (9 - i as i64))
                .sum::<i64>()
                - i64::from(x[8]);
            Some(eleven % 11 == 0 || mod_97_10_valid(&format!("NL{n}")))
        }
        "PL" => {
            let x = d(n);
            let w = [6, 5, 7, 2, 3, 4, 5, 6, 7];
            let r = x[..9].iter().zip(w).map(|(a, b)| a * b).sum::<u32>() % 11;
            Some(r != 10 && r == x[9])
        }
        "PT" => {
            let x = d(n);
            let sum: u32 = x[..8]
                .iter()
                .enumerate()
                .map(|(i, v)| v * (9 - i as u32))
                .sum();
            let check = match 11 - sum % 11 {
                c if c >= 10 => 0,
                c => c,
            };
            Some(x[0] != 0 && check == x[8])
        }
        "RO" => {
            if n.len() == 13 {
                // A personal numeric code can serve as the number; its rule is not implemented.
                return None;
            }
            let padded = format!("{n:0>10}");
            let x = d(&padded);
            let w = [7, 5, 3, 2, 1, 7, 5, 3, 2];
            let sum: u32 = x[..9].iter().zip(w).map(|(a, b)| a * b).sum();
            Some(sum * 10 % 11 % 10 == x[9])
        }
        "SE" => Some(luhn_valid(&n[..10]) && n.ends_with("01")),
        "SI" => {
            let x = d(n);
            let sum: u32 = x[..7]
                .iter()
                .enumerate()
                .map(|(i, v)| v * (8 - i as u32))
                .sum();
            let check = match 11 - sum % 11 {
                10 => 0,
                c => c,
            };
            Some(x[0] != 0 && check != 11 && check == x[7])
        }
        "SK" => {
            // Companies and, for sole proprietors, the birth number: both are multiples of 11.
            // A birth number whose first nine digits leave 10 has 0 as its last digit.
            let value: u64 = n.parse().ok()?;
            let head: u64 = n[..9].parse().ok()?;
            Some(value.is_multiple_of(11) || (head % 11 == 10 && n.ends_with('0')))
        }
        _ => None,
    }
}

/// ISO 7064 mod 11,10 (Germany's VAT numbers, Croatia's OIB): `digits` are all but the last,
/// `check` is the last.
fn mod_11_10_valid(digits: &[u32], check: u32) -> bool {
    let mut product = 10;
    for d in digits {
        let mut sum = (d + product) % 10;
        if sum == 0 {
            sum = 10;
        }
        product = (2 * sum) % 11;
    }
    (11 - product) % 10 == check
}

/// ISO 7064 mod 97-10: letters count as 10 (A) to 35 (Z); the whole number mod 97 must be 1.
fn mod_97_10_valid(s: &str) -> bool {
    let mut rem: u32 = 0;
    for c in s.chars() {
        let Some(v) = c.to_digit(36) else {
            return false;
        };
        rem = if v >= 10 {
            (rem * 100 + v) % 97
        } else {
            (rem * 10 + v) % 97
        };
    }
    rem == 1
}

/// The Luhn check over a string of digits.
fn luhn_valid(s: &str) -> bool {
    let mut sum = 0;
    for (i, c) in s.chars().rev().enumerate() {
        let Some(mut v) = c.to_digit(10) else {
            return false;
        };
        if i % 2 == 1 {
            v *= 2;
            if v > 9 {
                v -= 9;
            }
        }
        sum += v;
    }
    !s.is_empty() && sum % 10 == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn verdict(raw: &str) -> Verdict {
        match parse(raw, None) {
            Parsed::Eu(v) => validate(&v),
            other => panic!("{raw}: not an EU number: {other:?}"),
        }
    }

    #[test]
    fn compact_strips_separators_and_upper_cases() {
        assert_eq!(compact("be 0428.759.497"), "BE0428759497");
        assert_eq!(compact(" NL-004495445-b01 "), "NL004495445B01");
        assert_eq!(compact("DE 136,695 976"), "DE136695976");
        // A stray character stays and later fails the shape test.
        assert_eq!(compact("BE0428*759497"), "BE0428*759497");
    }

    #[test]
    fn parse_reads_prefixes_and_falls_back_to_the_country() {
        assert_eq!(parse("  ", None), Parsed::Empty);
        assert_eq!(
            parse("BE 0428.759.497", None),
            Parsed::Eu(VatNumber {
                prefix: "BE",
                number: "0428759497".into()
            })
        );
        // No prefix: the country of the record decides.
        assert_eq!(
            parse("0428.759.497", Some("be")),
            Parsed::Eu(VatNumber {
                prefix: "BE",
                number: "0428759497".into()
            })
        );
        // Greece is EL in VIES but GR as a country, and either may be typed.
        for raw in ["EL123456789", "GR123456789"] {
            assert!(
                matches!(parse(raw, None), Parsed::Eu(v) if v.prefix == "EL"),
                "{raw}"
            );
        }
        assert!(matches!(parse("123456789", Some("GR")), Parsed::Eu(v) if v.prefix == "EL"));
        // Not the EU: never validated (the United Kingdom left, Switzerland never joined).
        assert!(matches!(parse("GB123456789", None), Parsed::Other(_)));
        assert!(matches!(
            parse("CHE-123.456.789 MWST", None),
            Parsed::Other(_)
        ));
        assert!(matches!(parse("123456789", Some("US")), Parsed::Other(_)));
        assert!(matches!(parse("123456789", None), Parsed::Other(_)));
        // Northern Ireland has its own prefix.
        assert!(matches!(parse("XI123456789", None), Parsed::Eu(v) if v.prefix == "XI"));
    }

    #[test]
    fn vies_prefix_maps_countries() {
        assert_eq!(vies_prefix("be"), Some("BE"));
        assert_eq!(vies_prefix("GR"), Some("EL"));
        assert_eq!(vies_prefix("GB"), None);
        assert_eq!(vies_prefix("CH"), None);
        assert_eq!(vies_prefix(""), None);
    }

    #[test]
    fn real_numbers_are_valid() {
        for raw in [
            "BE0428759497",
            "BE 0428.759.497",
            // The nine-digit Belgian form without the leading zero.
            "BE428759497",
            "NL004495445B01",
            "FR40303265045",
            "DE136695976",
            "LU15027442",
            "ATU13585627",
            "IT00743110157",
        ] {
            assert_eq!(verdict(raw), Verdict::Valid, "{raw}");
        }
    }

    #[test]
    fn a_typo_in_the_check_digits_is_caught() {
        for raw in [
            "BE0428759498",
            "NL004495446B01",
            "FR41303265045",
            "DE136695977",
            "LU15027443",
            "ATU13585628",
            "IT00743110158",
        ] {
            assert_eq!(verdict(raw), Verdict::BadChecksum, "{raw}");
        }
    }

    #[test]
    fn a_wrong_shape_is_a_format_error() {
        for raw in [
            // Nine digits would be the old Belgian form without the leading 0, so go shorter.
            "BE04287594",
            "BE04287594970",  // one digit too many
            "BE2428759497",   // a Belgian number starts with 0 or 1
            "NL004495445A01", // the B is fixed
            "NL004495445B1",
            "DE13669597",
            "DE13669597A",
            "ATU1358562",
            "AT013585627", // the U is fixed
            "FR4030326504",
            "LU1502744",
        ] {
            assert_eq!(verdict(raw), Verdict::BadFormat, "{raw}");
        }
    }

    #[test]
    fn countries_without_a_rule_get_the_format_test_only() {
        // Spain: right shape, no check digit rule here.
        assert_eq!(verdict("ESB12345678"), Verdict::FormatOk);
        assert_eq!(verdict("ES1234567"), Verdict::BadFormat);
        assert_eq!(verdict("BG123456789"), Verdict::FormatOk);
        // A French key with a letter is not checked either.
        assert_eq!(verdict("FRAB303265045"), Verdict::FormatOk);
    }

    #[test]
    fn problem_reports_only_what_is_wrong() {
        assert_eq!(problem("", Some("BE")), None);
        assert_eq!(problem("BE0428759497", None), None);
        assert_eq!(problem("ESB12345678", None), None);
        // Another country's number is the caller's business.
        assert_eq!(problem("CHE-123.456.789", None), None);
        assert_eq!(problem("123456789", Some("CH")), None);
        let m = problem("BE0428759498", None).unwrap();
        assert!(m.contains("check digits"), "{m}");
        let m = problem("0428759", Some("BE")).unwrap();
        assert!(m.contains("not shaped like a BE"), "{m}");
    }

    #[test]
    fn same_number_ignores_spelling() {
        assert!(same_number("BE 0428.759.497", "be0428759497", None));
        assert!(same_number("0428.759.497", "BE0428759497", Some("BE")));
        assert!(!same_number("BE0428759497", "BE0428759498", None));
        assert!(same_number("", "  ", None));
        // Not an EU number: compared as compacted text.
        assert!(same_number("CHE-123.456.789", "che123456789", None));
    }

    /// Numbers generated with python-stdnum as an independent implementation: `VALID` are numbers it
    /// accepts, `BAD_CHECK` are numbers of the right shape it rejects. During development this module
    /// was also compared with it over some 43,000 generated numbers in 27 countries: nothing it
    /// accepts is rejected here (a few countries are looser, never stricter).
    #[test]
    fn check_digits_agree_with_an_independent_implementation() {
        const VALID: [&str; 57] = [
            "ATU76467459",
            "ATU17080110",
            "ATU97034538",
            "BE1781974825",
            "BE557394365",
            "BE0404528107",
            "DE402126844",
            "DE827639262",
            "DE516178960",
            "DK39296497",
            "DK40991263",
            "DK68112117",
            "EE273194947",
            "EE260538435",
            "EE660888031",
            "EL696801193",
            "EL147295707",
            "EL14115883",
            "FI93611811",
            "FI55407692",
            "FI49949209",
            "FRTW517553509",
            "FRM6689146801",
            "FRWS813888021",
            "HR02011924918",
            "HR80801204579",
            "HR07463707031",
            "HU47299559",
            "HU01419566",
            "HU64387479",
            "IT61731371003",
            "IT10180860198",
            "IT23565390368",
            "LU57630530",
            "LU05561579",
            "LU57685546",
            "NL753135304B38",
            "NL318575383B39",
            "NL182663644B15",
            "PL4075374534",
            "PL8843389306",
            "PL4474162733",
            "PT989630005",
            "PT336547617",
            "PT931608406",
            "RO766914955",
            "RO346376728",
            "RO849788038",
            "SE479875043801",
            "SE499006552801",
            "SE515512016401",
            "SI27494098",
            "SI19702221",
            "SI21979332",
            "SK1486178320",
            "SK1724976979",
            "SK2791510722",
        ];
        const BAD_CHECK: [&str; 38] = [
            "ATU21259583",
            "ATU42809461",
            "BE0112004417",
            "BE1458132055",
            "DE459705132",
            "DE470596606",
            "DK00572039",
            "DK08529536",
            "EE175357058",
            "EE572535843",
            "EL351110839",
            "EL425823928",
            "FI12572734",
            "FI12268795",
            "FR43592117120",
            "FR84812625434",
            "HR38915998176",
            "HR57515661688",
            "HU94423561",
            "HU97893455",
            "IT43405341276",
            "IT88874817808",
            "LU69230406",
            "LU75232139",
            "NL492745491B23",
            "NL752814152B87",
            "PL1696315592",
            "PL5591387267",
            "PT761022285",
            "PT257027358",
            "RO427702907",
            "RO541441063",
            "SE197745060901",
            "SE245873218401",
            "SI00945215",
            "SI94623281",
            "SK2212781499",
            "SK9495234311",
        ];
        for raw in VALID {
            // French keys with a letter have a rule of their own that is not implemented here.
            let letter_key =
                raw.starts_with("FR") && !raw[2..4].chars().all(|c| c.is_ascii_digit());
            let expected = if letter_key {
                Verdict::FormatOk
            } else {
                Verdict::Valid
            };
            assert_eq!(verdict(raw), expected, "{raw}");
        }
        for raw in BAD_CHECK {
            assert_eq!(verdict(raw), Verdict::BadChecksum, "{raw}");
        }
    }
}
