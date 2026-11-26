//! Tenant-isolation query scan (docs/ROADMAP.md, "Per-item checklist": tenant isolation).
//!
//! How it works, in four steps that are meant to stay simple enough to explain:
//!
//! 1. **Tenant tables** are derived from `migrations/*.sql`: every `CREATE TABLE` whose
//!    column list has a `company_id` column, plus every table that later gets one through
//!    `ALTER TABLE ... ADD COLUMN company_id`, minus tables that are dropped again. New
//!    tables are therefore covered without editing this test.
//! 2. **SQL literals** are collected from every Rust source under `crates/*/src` and
//!    `apps/*/src` (ordinary, raw and `format!` strings; comments, `#[cfg(test)]` items
//!    and `tests.rs` modules are skipped). A `{NAME}` placeholder is replaced with the value of a
//!    `const NAME: &str = "..."` in the same file, so the common
//!    `format!("{SELECT} WHERE ...")` pattern is read as one statement (and the const
//!    itself is not scanned on its own when it is used that way). A local
//!    `let NAME = "..."` is spliced the same way (nearest definition first).
//! 3. A literal is **flagged** when it names a tenant table as `schema.table`, contains an
//!    SQL keyword (`FROM`, `JOIN`, `INTO`, `UPDATE`, `DELETE`), and does not mention
//!    `company_id` anywhere. The rule is deliberately coarse: it does not check *which*
//!    table the predicate belongs to, it only makes sure nobody touches tenant data
//!    without thinking about the tenant.
//! 4. Flagged statements must be listed in `tests/tenant_scan_allowlist.txt` with a
//!    reason (usually: the row was reached through a company-scoped lookup earlier in
//!    the same handler). The test fails for a flagged statement that is not listed, and
//!    for an allowlist entry that no longer matches any flagged statement.
//!
//! Allowlist format, one entry per line: `path | reason | normalised SQL`, where the
//! SQL is the literal with whitespace collapsed to single spaces (exactly what the
//! failure message prints). Lines starting with `#` and blank lines are ignored.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("workspace root")
}

// ---------------------------------------------------------------------------
// Step 1: tenant tables from the migrations.
// ---------------------------------------------------------------------------

fn strip_sql_comments(sql: &str) -> String {
    sql.lines()
        .map(|line| match line.find("--") {
            Some(i) => &line[..i],
            None => line,
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn is_ident(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// Reads the next identifier (`a-z0-9_.` plus quotes) after skipping whitespace.
fn next_word(s: &str) -> (&str, &str) {
    let s = s.trim_start();
    let end = s
        .find(|c: char| !(is_ident(c) || c == '.' || c == '"'))
        .unwrap_or(s.len());
    (&s[..end], &s[end..])
}

fn skip_keywords<'a>(mut s: &'a str, keywords: &[&str]) -> &'a str {
    loop {
        let (w, rest) = next_word(s);
        if keywords.iter().any(|k| w.eq_ignore_ascii_case(k)) {
            s = rest;
        } else {
            return s;
        }
    }
}

/// Top-level comma-separated items of a parenthesised body starting at `(`.
fn paren_items(body: &str) -> Vec<String> {
    let mut items = Vec::new();
    let mut depth = 0usize;
    let mut cur = String::new();
    for c in body.chars() {
        match c {
            '(' => {
                depth += 1;
                if depth == 1 {
                    continue;
                }
            }
            ')' => {
                depth -= 1;
                if depth == 0 {
                    items.push(std::mem::take(&mut cur));
                    break;
                }
            }
            ',' if depth == 1 => {
                items.push(std::mem::take(&mut cur));
                continue;
            }
            _ => {}
        }
        if depth >= 1 {
            cur.push(c);
        }
    }
    items
}

fn tenant_tables(root: &Path) -> BTreeSet<String> {
    let mut files: Vec<PathBuf> = fs::read_dir(root.join("migrations"))
        .expect("migrations dir")
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "sql"))
        .collect();
    files.sort();
    let mut tables = BTreeSet::new();
    for file in files {
        let sql = strip_sql_comments(&fs::read_to_string(&file).unwrap());
        for stmt in sql.split(';') {
            let (w1, rest) = next_word(stmt);
            let (w2, rest) = next_word(rest);
            if w1.eq_ignore_ascii_case("CREATE") && w2.eq_ignore_ascii_case("TABLE") {
                let rest = skip_keywords(rest, &["IF", "NOT", "EXISTS"]);
                let (name, body) = next_word(rest);
                let has_company = paren_items(body).iter().any(|item| {
                    let (col, _) = next_word(item);
                    col.trim_matches('"') == "company_id"
                });
                if has_company {
                    tables.insert(name.replace('"', "").to_lowercase());
                }
            } else if w1.eq_ignore_ascii_case("ALTER") && w2.eq_ignore_ascii_case("TABLE") {
                let rest = skip_keywords(rest, &["IF", "EXISTS", "ONLY"]);
                let (name, actions) = next_word(rest);
                let adds_company = actions.split(',').any(|action| {
                    let (a, r) = next_word(action);
                    if !a.eq_ignore_ascii_case("ADD") {
                        return false;
                    }
                    let r = skip_keywords(r, &["COLUMN", "IF", "NOT", "EXISTS"]);
                    next_word(r).0 == "company_id"
                });
                if adds_company {
                    tables.insert(name.replace('"', "").to_lowercase());
                }
            } else if w1.eq_ignore_ascii_case("DROP") && w2.eq_ignore_ascii_case("TABLE") {
                let rest = skip_keywords(rest, &["IF", "EXISTS"]);
                for name in rest.split(',') {
                    tables.remove(&next_word(name).0.replace('"', "").to_lowercase());
                }
            }
        }
    }
    tables
}

// ---------------------------------------------------------------------------
// Step 2: string literals from the Rust sources.
// ---------------------------------------------------------------------------

struct Literal {
    line: usize,
    /// Byte offset in the file, used to pick the nearest `let` binding.
    offset: usize,
    value: String,
    /// `Some(NAME)` when the literal is the initialiser of `const NAME: &str = "..."`
    /// or `let NAME = "..."`.
    const_name: Option<String>,
}

fn const_name_before(src: &str, start: usize) -> Option<String> {
    let before = &src[..start];
    let from = before.rfind([';', '{', '}']).map_or(0, |i| i + 1);
    let decl = before[from..].trim();
    let decl = decl.strip_suffix('=')?.trim_end();
    let decl = decl
        .strip_suffix("&str")
        .or_else(|| decl.strip_suffix("&'static str"))
        .map_or(decl, |d| d.trim_end().strip_suffix(':').unwrap_or(d))
        .trim_end();
    let mut words = decl.split_whitespace().rev();
    let name = words.next()?;
    let kw = words.next()?;
    let is_name = name.chars().all(is_ident);
    (is_name && matches!(kw, "const" | "static" | "let")).then(|| name.to_string())
}

/// A small Rust lexer: enough to find string literals and skip comments, char
/// literals and `#[cfg(test)]` items.
fn rust_literals(src: &str) -> Vec<Literal> {
    let b = src.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut line = 1;
    // Brace depth, plus the depth at which a #[cfg(test)] item started.
    let mut depth = 0usize;
    let mut cfg_test_pending = false;
    let mut skip_until_depth: Option<usize> = None;
    while i < b.len() {
        let c = b[i];
        if c == b'\n' {
            line += 1;
            i += 1;
            continue;
        }
        if src[i..].starts_with("//") {
            while i < b.len() && b[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if src[i..].starts_with("/*") {
            let mut nest = 0;
            while i < b.len() {
                if src[i..].starts_with("/*") {
                    nest += 1;
                    i += 2;
                } else if src[i..].starts_with("*/") {
                    nest -= 1;
                    i += 2;
                    if nest == 0 {
                        break;
                    }
                } else {
                    if b[i] == b'\n' {
                        line += 1;
                    }
                    i += 1;
                }
            }
            continue;
        }
        if src[i..].starts_with("#[cfg(test)]") {
            cfg_test_pending = true;
            i += "#[cfg(test)]".len();
            continue;
        }
        let prev_ident = i > 0 && is_ident(b[i - 1] as char);
        // Raw strings: r"..", r#".."#, br#".."#.
        let raw_start = if !prev_ident && c == b'r' {
            Some(i + 1)
        } else if !prev_ident && c == b'b' && b.get(i + 1) == Some(&b'r') {
            Some(i + 2)
        } else {
            None
        };
        if let Some(mut j) = raw_start {
            let mut hashes = 0;
            while b.get(j) == Some(&b'#') {
                hashes += 1;
                j += 1;
            }
            if b.get(j) == Some(&b'"') {
                let close = format!("\"{}", "#".repeat(hashes));
                let body_start = j + 1;
                let end = body_start + src[body_start..].find(&close).expect("raw string end");
                let value = src[body_start..end].to_string();
                if skip_until_depth.is_none() {
                    out.push(Literal {
                        line,
                        offset: i,
                        const_name: const_name_before(src, i),
                        value: value.clone(),
                    });
                }
                line += value.matches('\n').count();
                i = end + close.len();
                continue;
            }
        }
        if c == b'"' {
            let start = i;
            let mut value = String::new();
            let start_line = line;
            i += 1;
            while b[i] != b'"' {
                if b[i] == b'\\' {
                    let e = b[i + 1];
                    i += 2;
                    match e {
                        b'n' => value.push('\n'),
                        b't' => value.push('\t'),
                        b'\n' => {
                            line += 1;
                            while i < b.len() && (b[i] as char).is_whitespace() {
                                if b[i] == b'\n' {
                                    line += 1;
                                }
                                i += 1;
                            }
                        }
                        other => value.push(other as char),
                    }
                    continue;
                }
                if b[i] == b'\n' {
                    line += 1;
                }
                let ch = src[i..].chars().next().unwrap();
                value.push(ch);
                i += ch.len_utf8();
            }
            i += 1;
            if skip_until_depth.is_none() {
                out.push(Literal {
                    line: start_line,
                    offset: start,
                    const_name: const_name_before(src, start),
                    value,
                });
            }
            continue;
        }
        if c == b'\'' {
            // Char literal ('x', '\n', '\u{..}') or lifetime ('a).
            if b.get(i + 1) == Some(&b'\\') {
                i += 2;
                while b[i] != b'\'' {
                    i += 1;
                }
                i += 1;
                continue;
            }
            let ch_len = src[i + 1..].chars().next().map_or(1, char::len_utf8);
            if b.get(i + 1 + ch_len) == Some(&b'\'') {
                i += 2 + ch_len;
                continue;
            }
            i += 1;
            continue;
        }
        match c {
            b'{' => {
                if cfg_test_pending && skip_until_depth.is_none() {
                    skip_until_depth = Some(depth);
                }
                cfg_test_pending = false;
                depth += 1;
            }
            b'}' => {
                depth -= 1;
                if skip_until_depth == Some(depth) {
                    skip_until_depth = None;
                }
            }
            b';' => cfg_test_pending = false,
            _ => {}
        }
        i += 1;
    }
    out
}

fn rust_sources(root: &Path) -> Vec<PathBuf> {
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = fs::read_dir(dir) else {
            return;
        };
        for e in entries {
            let p = e.unwrap().path();
            if p.is_dir() {
                walk(&p, out);
            } else if p.extension().is_some_and(|e| e == "rs")
                && p.file_name().is_some_and(|n| n != "tests.rs")
            {
                out.push(p);
            }
        }
    }
    let mut out = Vec::new();
    for group in ["crates", "apps"] {
        let mut members: Vec<PathBuf> = fs::read_dir(root.join(group))
            .unwrap()
            .map(|e| e.unwrap().path())
            .collect();
        members.sort();
        for m in members {
            walk(&m.join("src"), &mut out);
        }
    }
    out.sort();
    out
}

// ---------------------------------------------------------------------------
// Step 3: flagging.
// ---------------------------------------------------------------------------

fn contains_word(hay: &str, word: &str, allow_dot_before: bool) -> bool {
    let mut from = 0;
    while let Some(pos) = hay[from..].find(word) {
        let s = from + pos;
        let e = s + word.len();
        let before = hay[..s].chars().next_back();
        let after = hay[e..].chars().next();
        let ok_before = match before {
            None => true,
            Some('.') => allow_dot_before,
            Some(c) => !is_ident(c) && c != '"',
        };
        let ok_after = after.is_none_or(|c| !is_ident(c));
        if ok_before && ok_after {
            return true;
        }
        from = s + 1;
    }
    false
}

fn normalise(sql: &str) -> String {
    sql.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Replace `{NAME}` with the value of a same-file `const NAME: &str` or `let NAME = "..."`
/// (the nearest definition before the literal, else the first one in the file). Returns
/// the expanded text and the indices (into `lits`) of the definitions it used.
fn expand(lits: &[Literal], idx: usize) -> (String, BTreeSet<usize>) {
    let mut used = BTreeSet::new();
    let mut out = lits[idx].value.clone();
    let names: BTreeSet<&str> = lits.iter().filter_map(|l| l.const_name.as_deref()).collect();
    for _ in 0..3 {
        let mut changed = false;
        for name in &names {
            let ph = format!("{{{name}}}");
            if !out.contains(&ph) {
                continue;
            }
            let defs = || {
                lits.iter()
                    .enumerate()
                    .filter(|(_, l)| l.const_name.as_deref() == Some(*name))
            };
            let def = defs()
                .filter(|(_, l)| l.offset < lits[idx].offset)
                .last()
                .or_else(|| defs().next())
                .map(|(i, _)| i)
                .expect("definition");
            out = out.replace(&ph, &lits[def].value);
            used.insert(def);
            changed = true;
        }
        if !changed {
            break;
        }
    }
    (out, used)
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct Flagged {
    path: String,
    line: usize,
    sql: String,
}

fn scan(root: &Path, tables: &BTreeSet<String>) -> Vec<Flagged> {
    const KEYWORDS: [&str; 5] = ["FROM", "JOIN", "INTO", "UPDATE", "DELETE"];
    let mut flagged = Vec::new();
    for file in rust_sources(root) {
        let src = fs::read_to_string(&file).unwrap();
        let lits = rust_literals(&src);
        let mut expanded = Vec::new();
        let mut used_defs = BTreeSet::new();
        for i in 0..lits.len() {
            let (value, used) = expand(&lits, i);
            used_defs.extend(used);
            expanded.push(value);
        }
        let rel = file
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        for (i, (lit, value)) in lits.iter().zip(expanded).enumerate() {
            // A const/let that is spliced into another literal is scanned there.
            if used_defs.contains(&i) {
                continue;
            }
            let lower = value.to_lowercase();
            let names_tenant_table = tables.iter().any(|t| contains_word(&lower, t, false));
            if !names_tenant_table
                || !KEYWORDS.iter().any(|k| contains_word(&value, k, false))
                || contains_word(&lower, "company_id", true)
            {
                continue;
            }
            flagged.push(Flagged {
                path: rel.clone(),
                line: lit.line,
                sql: normalise(&value),
            });
        }
    }
    flagged
}

// ---------------------------------------------------------------------------
// Step 4: allowlist.
// ---------------------------------------------------------------------------

struct Entry {
    line: usize,
    path: String,
    sql: String,
}

fn allowlist(path: &Path) -> Vec<Entry> {
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut out = Vec::new();
    for (n, raw) in text.lines().enumerate() {
        let l = raw.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        let parts: Vec<&str> = l.splitn(3, " | ").collect();
        assert!(
            parts.len() == 3 && !parts[1].trim().is_empty(),
            "allowlist line {}: expected `path | reason | sql`: {l}",
            n + 1
        );
        out.push(Entry {
            line: n + 1,
            path: parts[0].trim().to_string(),
            sql: normalise(parts[2]),
        });
    }
    out
}

#[test]
fn tenant_tables_are_derived_from_migrations() {
    let tables = tenant_tables(&workspace_root());
    for t in [
        "crm.opportunities",
        "sales.orders",
        "helpdesk.articles",
        "core.user_companies",
    ] {
        assert!(tables.contains(t), "{t} missing from {tables:?}");
    }
    assert!(!tables.contains("core.companies"));
    assert!(!tables.contains("core.users"));
    assert!(tables.len() > 100, "only {} tenant tables", tables.len());
}

#[test]
fn every_tenant_query_mentions_company_id_or_is_allowlisted() {
    let root = workspace_root();
    let tables = tenant_tables(&root);
    let flagged = scan(&root, &tables);
    let list_path = root.join("crates/core/tests/tenant_scan_allowlist.txt");
    let entries = allowlist(&list_path);

    let mut by_key: BTreeMap<(&str, &str), usize> = BTreeMap::new();
    for e in &entries {
        by_key.insert((e.path.as_str(), e.sql.as_str()), 0);
    }
    let mut missing = Vec::new();
    for f in &flagged {
        match by_key.get_mut(&(f.path.as_str(), f.sql.as_str())) {
            Some(hits) => *hits += 1,
            None => missing.push(f),
        }
    }
    let stale: Vec<&Entry> = entries
        .iter()
        .filter(|e| by_key[&(e.path.as_str(), e.sql.as_str())] == 0)
        .collect();

    let mut msg = String::new();
    if !missing.is_empty() {
        msg.push_str(&format!(
            "{} statement(s) touch a tenant table without mentioning company_id.\n\
             Add `AND company_id = $n` (or the column on INSERT), or, if the row is already \
             scoped (e.g. loaded through a company-scoped lookup), add a line to \
             {}:\n\n",
            missing.len(),
            list_path.display()
        ));
        for f in &missing {
            msg.push_str(&format!("# {}:{}\n{} | REASON | {}\n", f.path, f.line, f.path, f.sql));
        }
    }
    if !stale.is_empty() {
        msg.push_str(&format!(
            "\n{} stale allowlist entr(y/ies) match no flagged statement; remove them:\n",
            stale.len()
        ));
        for e in &stale {
            msg.push_str(&format!("  line {}: {} | {}\n", e.line, e.path, e.sql));
        }
    }
    assert!(msg.is_empty(), "{msg}");
}
