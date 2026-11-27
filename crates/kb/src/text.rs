//! Pure helpers: slugs, plain text from Markdown, search words, tag clean-up, language choice.

/// A URL-friendly slug: lower-case ASCII letters and digits separated by single dashes.
/// Accented letters are reduced to their base letter. Never empty.
pub fn slugify(title: &str) -> String {
    let mut out = String::new();
    let mut dash = false;
    for c in title.replace('ß', "ss").chars() {
        let c = fold(c);
        if c.is_ascii_alphanumeric() {
            if dash && !out.is_empty() {
                out.push('-');
            }
            dash = false;
            out.push(c.to_ascii_lowercase());
        } else {
            dash = true;
        }
        if out.len() >= 80 {
            break;
        }
    }
    if out.is_empty() {
        "entry".into()
    } else {
        out
    }
}

fn fold(c: char) -> char {
    match c {
        'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' | 'À' | 'Á' | 'Â' | 'Ã' | 'Ä' | 'Å' => 'a',
        'ç' | 'Ç' => 'c',
        'è' | 'é' | 'ê' | 'ë' | 'È' | 'É' | 'Ê' | 'Ë' => 'e',
        'ì' | 'í' | 'î' | 'ï' | 'Ì' | 'Í' | 'Î' | 'Ï' => 'i',
        'ñ' | 'Ñ' => 'n',
        'ò' | 'ó' | 'ô' | 'õ' | 'ö' | 'Ò' | 'Ó' | 'Ô' | 'Õ' | 'Ö' => 'o',
        'ù' | 'ú' | 'û' | 'ü' | 'Ù' | 'Ú' | 'Û' | 'Ü' => 'u',
        'ý' | 'ÿ' | 'Ý' => 'y',
        c => c,
    }
}

/// Trimmed, lower-cased, de-duplicated tags of at most 40 characters.
pub fn clean_tags(tags: &[String]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for t in tags {
        let t: String = t.trim().to_lowercase().chars().take(40).collect();
        let t = t.trim().to_string();
        if !t.is_empty() && !out.contains(&t) {
            out.push(t);
        }
    }
    out
}

/// Markdown reduced to readable plain text: no markers, links as `label (address)`, images
/// dropped, list items kept as `- `. Used for snippets and for text inserted in e-mails.
pub fn plain_text(md: &str) -> String {
    let mut lines: Vec<String> = Vec::new();
    for raw in md.lines() {
        let line = raw.trim_end();
        let t = line.trim_start();
        let t = t.trim_start_matches('#').trim_start();
        let t = t.strip_prefix("> ").unwrap_or(t);
        let t = strip_inline(t);
        lines.push(t.trim_end().to_string());
    }
    let mut out = String::new();
    let mut blank = false;
    for l in lines {
        if l.is_empty() {
            blank = !out.is_empty();
        } else {
            if blank {
                out.push('\n');
            }
            if !out.is_empty() {
                out.push('\n');
            }
            blank = false;
            out.push_str(&l);
        }
    }
    out
}

/// Removes inline Markdown: `**bold**`, `*italic*`, `_italic_`, `` `code` ``, images, links.
fn strip_inline(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '!' && chars.get(i + 1) == Some(&'[') {
            if let Some((_, _, end)) = link_at(&chars, i + 1) {
                i = end;
                continue;
            }
        }
        if c == '[' {
            if let Some((label, url, end)) = link_at(&chars, i) {
                out.push_str(&strip_inline(&label));
                if !url.starts_with("image:") && !label.trim().is_empty() && label.trim() != url {
                    out.push_str(&format!(" ({url})"));
                } else if label.trim().is_empty() {
                    out.push_str(&url);
                }
                i = end;
                continue;
            }
        }
        if matches!(c, '*' | '`') || (c == '_' && is_marker(&chars, i)) {
            i += 1;
            continue;
        }
        out.push(c);
        i += 1;
    }
    out
}

/// An underscore is a marker when it is not inside a word (snake_case stays intact).
fn is_marker(chars: &[char], i: usize) -> bool {
    let before = i.checked_sub(1).and_then(|j| chars.get(j));
    let after = chars.get(i + 1);
    let word = |c: Option<&char>| c.is_some_and(|c| c.is_alphanumeric());
    !(word(before) && word(after))
}

/// `[label](url)` starting at `start` (which holds `[`): the label, the url and the index after.
fn link_at(chars: &[char], start: usize) -> Option<(String, String, usize)> {
    let close = (start + 1..chars.len()).find(|&j| chars[j] == ']')?;
    if chars.get(close + 1) != Some(&'(') {
        return None;
    }
    let end = (close + 2..chars.len()).find(|&j| chars[j] == ')')?;
    Some((
        chars[start + 1..close].iter().collect(),
        chars[close + 2..end]
            .iter()
            .collect::<String>()
            .trim()
            .to_string(),
        end + 1,
    ))
}

/// The words of a text that are worth searching for, joined for `to_tsquery` as `a | b | c`.
/// Only letters and digits survive, so the result can never be a syntax error. `None` when no
/// word is left.
pub fn any_word_query(text: &str, max_words: usize) -> Option<String> {
    let mut words: Vec<String> = Vec::new();
    for w in text.split(|c: char| !c.is_alphanumeric()) {
        let w = w.to_lowercase();
        if w.chars().count() >= 3 && !words.contains(&w) {
            words.push(w);
            if words.len() >= max_words {
                break;
            }
        }
    }
    if words.is_empty() {
        None
    } else {
        Some(words.join(" | "))
    }
}

/// Index of the text to show: the wanted language, else English, else the first one (texts come
/// in the company's language order, ADR 0101). The flag tells that it is not the wanted language.
pub fn pick_language(available: &[&str], wanted: &str) -> Option<(usize, bool)> {
    tradocraft_core::languages::pick(
        available,
        &[
            wanted.to_string(),
            tradocraft_core::languages::SOURCE_LANGUAGE.to_string(),
        ],
    )
}

/// A short plain-text excerpt for a list without a search term.
pub fn excerpt(summary: &str, body: &str, max: usize) -> String {
    let source = if summary.trim().is_empty() {
        plain_text(body)
    } else {
        plain_text(summary)
    };
    let flat = source.split_whitespace().collect::<Vec<_>>().join(" ");
    if flat.chars().count() <= max {
        flat
    } else {
        let cut: String = flat.chars().take(max).collect();
        format!("{}…", cut.trim_end())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs_are_ascii_and_never_empty() {
        assert_eq!(
            slugify("Pompen onderhouden: stap voor stap!"),
            "pompen-onderhouden-stap-voor-stap"
        );
        assert_eq!(
            slugify("Réinitialiser le mot de passe"),
            "reinitialiser-le-mot-de-passe"
        );
        assert_eq!(slugify("Größe ändern"), "grosse-andern");
        assert_eq!(slugify("¿Cómo?"), "como");
        assert_eq!(slugify("  ---  "), "entry");
        assert!(slugify(&"a ".repeat(100)).len() <= 81);
    }

    #[test]
    fn tags_are_lower_case_unique_and_short() {
        let t = clean_tags(&[" Pump ".into(), "pump".into(), "".into(), "X".repeat(60)]);
        assert_eq!(t.len(), 2);
        assert_eq!(t[0], "pump");
        assert_eq!(t[1].len(), 40);
    }

    #[test]
    fn markdown_becomes_plain_text() {
        let md = "# Title\n\nSome **bold** and *italic* text with `code`.\n\n- one\n- two\n\nSee [the manual](https://x.example/m) and ![photo](image:abc).";
        assert_eq!(
            plain_text(md),
            "Title\n\nSome bold and italic text with code.\n\n- one\n- two\n\nSee the manual (https://x.example/m) and ."
        );
        assert_eq!(
            plain_text("snake_case_name and _em_"),
            "snake_case_name and em"
        );
        assert_eq!(plain_text(""), "");
    }

    #[test]
    fn search_words_cannot_break_the_query() {
        assert_eq!(
            any_word_query("Pump leaks: error 'E42' & (drip)!", 10).as_deref(),
            Some("pump | leaks | error | e42 | drip")
        );
        assert_eq!(any_word_query("a b ?! ", 10), None);
        assert_eq!(
            any_word_query("één twee drie vier", 2).as_deref(),
            Some("één | twee")
        );
        assert_eq!(any_word_query("pump pump PUMP", 5).as_deref(), Some("pump"));
    }

    #[test]
    fn language_falls_back_to_english_then_the_first() {
        assert_eq!(pick_language(&["nl", "en"], "nl"), Some((0, false)));
        assert_eq!(pick_language(&["nl", "en"], "de"), Some((1, true)));
        assert_eq!(pick_language(&["de", "fr"], "es"), Some((0, true)));
        assert_eq!(pick_language(&["pt", "sv"], "sv"), Some((1, false)));
        assert_eq!(pick_language(&[], "nl"), None);
    }

    #[test]
    fn excerpts_are_short_and_flat() {
        assert_eq!(excerpt("", "# A\n\nb **c**", 50), "A b c");
        assert_eq!(excerpt("Summary", "body", 50), "Summary");
        let long = excerpt("", &"word ".repeat(100), 20);
        assert!(long.ends_with('…') && long.chars().count() <= 21);
    }
}
