//! Display names of the ISO 639-1 languages: the English name and the endonym (the language's
//! own name, capitalised for use in a list). A small static table instead of CLDR data keeps the
//! dependency footprint at zero; the Flutter app carries the same table in
//! `app/lib/l10n/language_names.dart` (a test keeps the two equal).

include!("names_table.rs");

/// The language's own name (`Nederlands`, `Français`), or `None` for an unknown code.
pub fn endonym(code: &str) -> Option<&'static str> {
    lookup(code).map(|(_, _, n)| *n)
}

/// The English name (`Dutch`, `French`), or `None` for an unknown code.
pub fn english_name(code: &str) -> Option<&'static str> {
    lookup(code).map(|(_, e, _)| *e)
}

fn lookup(code: &str) -> Option<&'static (&'static str, &'static str, &'static str)> {
    LANGUAGE_NAMES
        .binary_search_by(|(c, _, _)| (*c).cmp(code))
        .ok()
        .map(|i| &LANGUAGE_NAMES[i])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::language::ISO_639_1;

    #[test]
    fn one_name_per_iso_code_in_the_same_order() {
        let codes: Vec<&str> = LANGUAGE_NAMES.iter().map(|(c, _, _)| *c).collect();
        assert_eq!(codes, ISO_639_1);
        assert_eq!(endonym("nl"), Some("Nederlands"));
        assert_eq!(english_name("pt"), Some("Portuguese"));
        assert_eq!(endonym("xx"), None);
    }

    #[test]
    fn flutter_table_is_the_same() {
        let dart = include_str!("../../../../app/lib/l10n/language_names.dart");
        for (code, english, own) in LANGUAGE_NAMES {
            let own = own.replace('\'', "\\'");
            let line = format!("  '{code}': ('{english}', '{own}'),");
            assert!(dart.contains(&line), "missing in the Dart table: {line}");
        }
    }
}
