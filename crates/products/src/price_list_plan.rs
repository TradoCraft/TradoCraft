//! The export plan of a price list (ADR 0074): every file an administrator's export profiles
//! produce, with a relative path computed here so no client builds file names from user text.
//! Everything in this module is pure.

use std::collections::HashSet;

use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

/// Longest path segment, in UTF-8 bytes (file systems limit bytes, usually 255), extension and
/// collision suffix included. Kept well below 255 for file systems with smaller limits.
const MAX_SEGMENT: usize = 200;

/// `s` cut to at most `max` bytes, only on a character boundary.
fn cut_bytes(s: &str, max: usize) -> &str {
    if s.len() <= max {
        return s;
    }
    let mut end = max;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

const RESERVED: [&str; 22] = [
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
    "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// Control characters and invisible ones that can disguise a name (zero width, bidi controls,
/// BOM) are dropped.
fn is_dropped(c: char) -> bool {
    c.is_control()
        || matches!(c, '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{FEFF}')
}

/// Path separators and the characters Windows refuses in file names become `_`.
fn is_replaced(c: char) -> bool {
    matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|')
}

/// Turns any text into one safe path segment: separators, control and invisible characters
/// become `_` (control and invisible ones are dropped), leading dots and spaces and trailing dots
/// and spaces are removed (so `..` can never survive), Windows reserved device names get a `_`
/// prefix, the length is capped, and an empty result becomes `_`.
pub fn sanitize_segment(input: &str) -> String {
    sanitize_to(input, MAX_SEGMENT)
}

fn sanitize_to(input: &str, max: usize) -> String {
    let replaced: String = input
        .chars()
        .filter(|c| !is_dropped(*c))
        .map(|c| if is_replaced(c) { '_' } else { c })
        .collect();
    // No ".." anywhere, not only as a whole segment.
    let mut replaced = replaced;
    while replaced.contains("..") {
        replaced = replaced.replace("..", ".");
    }
    let trimmed = replaced.trim_start_matches(['.', ' ']);
    // Room for the `_` a reserved device name may get below.
    let mut out: String = cut_bytes(trimmed, max.saturating_sub(1))
        .trim_end_matches(['.', ' '])
        .to_string();
    // CON, CON.txt and con are all the console device on Windows.
    let device = out
        .split('.')
        .next()
        .unwrap_or("")
        .trim_end()
        .to_uppercase();
    if RESERVED.contains(&device.as_str()) {
        out.insert(0, '_');
    }
    if out.is_empty() {
        out.push('_');
    }
    out
}

/// A file name `stem.ext` whose stem is sanitized; the extension is fixed by the caller.
/// `suffix` (such as ` (2)`) is appended to the stem and counted in the byte budget.
fn file_segment(stem: &str, ext: &str, suffix: &str) -> String {
    let budget = MAX_SEGMENT - ext.len() - 1 - suffix.len();
    format!("{}{suffix}.{ext}", sanitize_to(stem, budget))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, serde::Deserialize, ToSchema)]
#[serde(rename_all = "lowercase")]
pub enum RenderFormat {
    Pdf,
    Xlsx,
}

impl RenderFormat {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Pdf => "pdf",
            Self::Xlsx => "xlsx",
        }
    }
}

#[derive(Debug, Clone)]
pub struct PlanZone {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub languages: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PlanExport {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub file_name: Option<String>,
}

/// One file to produce.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct ExportPlanEntry {
    pub zone_id: Uuid,
    pub zone_code: String,
    pub lang: String,
    /// `null`: the whole list.
    pub export_id: Option<Uuid>,
    pub format: RenderFormat,
    /// Forward-slash path, `<list>/<zone>/<lang>/<file>.<ext>`, every segment sanitized and the
    /// whole path unique (ignoring case) within the plan.
    pub relative_path: String,
}

fn expand_template(template: &str, list: &str, zone: &str, lang: &str, e: &PlanExport) -> String {
    template
        .replace("{list}", list)
        .replace("{zone}", zone)
        .replace("{lang}", lang)
        .replace("{name}", &e.name)
        .replace("{code}", &e.code)
}

/// Every file to produce, per zone in order and per language of that zone: the whole list first,
/// then one file per profile. Two files that would get the same path (profiles with the same name,
/// or a profile named like the list) are told apart with ` (2)`, ` (3)`.
pub fn export_plan(
    list_name: &str,
    zones: &[PlanZone],
    exports: &[PlanExport],
    format: RenderFormat,
) -> Vec<ExportPlanEntry> {
    let ext = format.extension();
    let list_dir = sanitize_segment(list_name);
    let mut used: HashSet<String> = HashSet::new();
    let mut out = Vec::new();
    for z in zones {
        let zone_dir = sanitize_segment(&z.name);
        for lang in &z.languages {
            let dir = format!("{list_dir}/{zone_dir}/{}", sanitize_segment(lang));
            let files =
                std::iter::once((None, list_name.to_string())).chain(exports.iter().map(|e| {
                    let stem = match &e.file_name {
                        Some(t) => expand_template(t, list_name, &z.name, lang, e),
                        None => e.name.clone(),
                    };
                    (Some(e.id), stem)
                }));
            for (export_id, stem) in files {
                let mut file = file_segment(&stem, ext, "");
                let mut n = 1;
                while !used.insert(format!("{dir}/{file}").to_lowercase()) {
                    n += 1;
                    file = file_segment(&stem, ext, &format!(" ({n})"));
                }
                out.push(ExportPlanEntry {
                    zone_id: z.id,
                    zone_code: z.code.clone(),
                    lang: lang.clone(),
                    export_id,
                    format,
                    relative_path: format!("{dir}/{file}"),
                });
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_names_are_kept() {
        assert_eq!(sanitize_segment("Prijslijst 2027"), "Prijslijst 2027");
        assert_eq!(sanitize_segment("Zone 1 - België"), "Zone 1 - België");
    }

    #[test]
    fn separators_and_windows_characters_never_survive() {
        let s = sanitize_segment("a/b\\c:d*e?f\"g<h>i|j");
        assert_eq!(s, "a_b_c_d_e_f_g_h_i_j");
        for hostile in [
            "../../etc/passwd",
            "..\\..\\windows",
            "/abs/path",
            "C:\\x",
            "a/../b",
        ] {
            let s = sanitize_segment(hostile);
            assert!(
                !s.contains('/') && !s.contains('\\') && !s.contains(':'),
                "{s}"
            );
            assert!(!s.starts_with('.') && !s.contains(".."), "{hostile} -> {s}");
        }
    }

    #[test]
    fn dots_spaces_and_empty_input() {
        assert_eq!(sanitize_segment(".."), "_");
        assert_eq!(sanitize_segment("."), "_");
        assert_eq!(sanitize_segment(" . hidden"), "hidden");
        assert_eq!(sanitize_segment("name. . "), "name");
        assert_eq!(sanitize_segment(""), "_");
        assert_eq!(sanitize_segment("   "), "_");
        assert_eq!(sanitize_segment("..."), "_");
        assert_eq!(sanitize_segment("a..b....c"), "a.b.c");
        assert_eq!(sanitize_segment("../../etc"), "_._etc");
    }

    #[test]
    fn control_and_invisible_characters_are_dropped() {
        assert_eq!(sanitize_segment("a\0b\nc\td\u{7f}"), "abcd");
        assert_eq!(sanitize_segment("evil\u{202E}fdp.exe"), "evilfdp.exe");
        assert_eq!(sanitize_segment("\u{FEFF}\u{200B}x"), "x");
    }

    #[test]
    fn reserved_windows_names_are_prefixed() {
        for n in [
            "CON", "con", "Nul", "COM1", "lpt9", "aux.txt", "PRN.pdf", "CON .",
        ] {
            let s = sanitize_segment(n);
            assert!(s.starts_with('_'), "{n} -> {s}");
        }
        assert_eq!(sanitize_segment("CONSOLE"), "CONSOLE");
        assert_eq!(sanitize_segment("COM10"), "COM10");
    }

    #[test]
    fn length_is_capped_in_bytes_without_trailing_dots() {
        let long = "é".repeat(500);
        let s = sanitize_segment(&long);
        assert!(
            s.len() <= MAX_SEGMENT && MAX_SEGMENT - s.len() < 3,
            "{}",
            s.len()
        );
        let dotted = format!("{}.....", "a".repeat(MAX_SEGMENT - 2));
        let s = sanitize_segment(&dotted);
        assert!(!s.ends_with('.') && s.len() <= MAX_SEGMENT, "{s}");
        let f = file_segment(&long, "xlsx", "");
        assert!(f.len() <= MAX_SEGMENT);
        assert!(f.ends_with(".xlsx"));
    }

    #[test]
    fn multibyte_names_are_cut_on_character_boundaries() {
        for unit in ["é", "😀", "漢", "a😀"] {
            let long = unit.repeat(500);
            let s = sanitize_segment(&long);
            assert!(s.len() <= MAX_SEGMENT, "{unit}: {}", s.len());
            assert!(s.chars().all(|c| unit.contains(c)), "{unit}");
            let f = file_segment(&long, "pdf", " (12)");
            assert!(f.len() <= MAX_SEGMENT, "{unit}: {}", f.len());
            assert!(f.ends_with(" (12).pdf"), "{f}");
        }
        // A reserved name that only forms after the cut still fits.
        let s = sanitize_segment(&format!("CON{}", "x".repeat(300)));
        assert!(s.len() <= MAX_SEGMENT);
    }

    #[test]
    fn colliding_multibyte_files_stay_within_the_limit() {
        let zones = [zone(1, &"漢".repeat(300), &["en"])];
        let name = "😀".repeat(300);
        let exports = [export(1, &name, None), export(2, &name, None)];
        let plan = export_plan(&name, &zones, &exports, RenderFormat::Xlsx);
        let mut seen = HashSet::new();
        for e in &plan {
            assert!(seen.insert(e.relative_path.to_lowercase()));
            for segment in e.relative_path.split('/') {
                assert!(segment.len() <= MAX_SEGMENT, "{}", segment.len());
            }
        }
        // list file, then two profiles with the same name: " (2)" and " (3)" suffixes.
        assert!(plan.iter().any(|e| e.relative_path.ends_with(" (2).xlsx")));
        assert!(plan.iter().any(|e| e.relative_path.ends_with(" (3).xlsx")));
    }

    fn zone(n: u128, name: &str, langs: &[&str]) -> PlanZone {
        PlanZone {
            id: Uuid::from_u128(n),
            code: format!("Z{n}"),
            name: name.into(),
            languages: langs.iter().map(|l| l.to_string()).collect(),
        }
    }

    fn export(n: u128, name: &str, file_name: Option<&str>) -> PlanExport {
        PlanExport {
            id: Uuid::from_u128(n),
            code: format!("E{n}"),
            name: name.into(),
            file_name: file_name.map(String::from),
        }
    }

    #[test]
    fn plan_covers_zones_languages_whole_list_and_profiles() {
        let zones = [zone(1, "Zone 1", &["en", "fr"]), zone(2, "Zone 2", &["nl"])];
        let exports = [export(10, "Pompen", None), export(11, "Slangen", None)];
        let plan = export_plan("Prijslijst 2027", &zones, &exports, RenderFormat::Pdf);
        assert_eq!(plan.len(), (2 + 1) * 3);
        let paths: Vec<&str> = plan.iter().map(|e| e.relative_path.as_str()).collect();
        assert_eq!(
            &paths[..6],
            [
                "Prijslijst 2027/Zone 1/en/Prijslijst 2027.pdf",
                "Prijslijst 2027/Zone 1/en/Pompen.pdf",
                "Prijslijst 2027/Zone 1/en/Slangen.pdf",
                "Prijslijst 2027/Zone 1/fr/Prijslijst 2027.pdf",
                "Prijslijst 2027/Zone 1/fr/Pompen.pdf",
                "Prijslijst 2027/Zone 1/fr/Slangen.pdf",
            ]
        );
        assert_eq!(plan[0].export_id, None);
        assert_eq!(plan[1].export_id, Some(Uuid::from_u128(10)));
        assert_eq!(plan[6].zone_code, "Z2");
        assert_eq!(plan[6].lang, "nl");
        let x = export_plan("L", &zones[1..], &[], RenderFormat::Xlsx);
        assert_eq!(x.len(), 1);
        assert_eq!(x[0].relative_path, "L/Zone 2/nl/L.xlsx");
    }

    #[test]
    fn plan_paths_are_safe_and_unique_for_hostile_names() {
        let zones = [zone(1, "../Zone", &["en"])];
        let exports = [
            export(1, "../../x", None),
            export(2, "../../x", None),
            export(3, "CON", None),
            export(4, "same", None),
            export(5, "SAME", None),
            export(6, "Prijslijst", None),
        ];
        let plan = export_plan("../Prijslijst", &zones, &exports, RenderFormat::Pdf);
        let mut seen = HashSet::new();
        for e in &plan {
            assert!(
                seen.insert(e.relative_path.to_lowercase()),
                "{}",
                e.relative_path
            );
            assert!(!e.relative_path.contains(".."), "{}", e.relative_path);
            assert!(!e.relative_path.starts_with('/'));
            assert_eq!(e.relative_path.split('/').count(), 4);
            assert!(!e.relative_path.contains('\\'));
        }
        assert!(plan.iter().any(|e| e.relative_path.ends_with("/_CON.pdf")));
        assert!(plan
            .iter()
            .any(|e| e.relative_path.ends_with("/_._x (2).pdf")));
    }

    #[test]
    fn file_name_template_is_expanded_then_sanitized() {
        let zones = [zone(1, "Zone 1", &["en"])];
        let exports = [export(1, "Pompen", Some("{list} - {name} [{zone}/{lang}]"))];
        let plan = export_plan("PL", &zones, &exports, RenderFormat::Pdf);
        assert_eq!(
            plan[1].relative_path,
            "PL/Zone 1/en/PL - Pompen [Zone 1_en].pdf"
        );
    }
}
