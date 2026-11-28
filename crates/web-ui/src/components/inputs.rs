//! Shared form input primitives: [`DecimalInput`] with expression evaluation and
//! [`SearchPicker`] for server-backed Many2One lookup.

use std::str::FromStr;

use leptos::prelude::*;
use rust_decimal::{Decimal, RoundingStrategy};

use crate::components::async_ops::{set_alive, spawn_api, RequestGuard};
use crate::state::AppContext;

const MAX_DECIMAL_INPUT_LEN: usize = 256;
const MAX_EXPR_DEPTH: usize = 64;

/// Parses a plain decimal number (optional leading `+`/`-`, optional `.` or `,` separator, no
/// operators or internal whitespace).
pub fn parse_decimal_input(text: &str) -> Option<Decimal> {
    let trimmed = text.trim();
    if trimmed.is_empty()
        || trimmed.len() > MAX_DECIMAL_INPUT_LEN
        || trimmed.chars().any(char::is_whitespace)
    {
        return None;
    }
    let normalized = trimmed.replace(',', ".");
    parse_number_literal(&normalized)
}

/// Evaluates plain decimals, arithmetic expressions (`+`, `-`, `*`, `/`, `()`, `%`), and
/// relative adjustments against `current_value` (`+=`, `-=`, `*=`, `/=`), rounding expression
/// results to `scale` decimal places.
pub fn evaluate_decimal_input(
    text: &str,
    current_value: Option<Decimal>,
    scale: u32,
    percentage_points: bool,
) -> Option<Decimal> {
    if let Some(plain) = parse_decimal_input(text) {
        return Some(if plain.is_zero() {
            Decimal::ZERO
        } else {
            plain
        });
    }

    let compact: String = text
        .chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| if c == ',' { '.' } else { c })
        .collect();
    if compact.is_empty() || compact.len() > MAX_DECIMAL_INPUT_LEN {
        return None;
    }

    let (adjustment_op, start) = parse_prefix_mode(&compact);
    let mut parser = DecimalParser::new(&compact, start, percentage_points);
    let mut result = parser.sum(0)?;
    if !parser.at_end() {
        return None;
    }

    if let Some(op) = adjustment_op {
        let base = current_value?;
        result = calculate(
            Operand {
                value: base,
                percent: false,
            },
            op,
            result,
            false,
        )?;
    }

    let scaled = if percentage_points && result.percent {
        result.value.checked_mul(Decimal::ONE_HUNDRED)?
    } else {
        result.value
    };
    let rounded = scaled
        .round_dp_with_strategy(scale, RoundingStrategy::MidpointAwayFromZero)
        .normalize();
    Some(if rounded.is_zero() {
        Decimal::ZERO
    } else {
        rounded
    })
}

/// Formats a decimal without spurious trailing fractional zeros or negative zero.
pub fn format_decimal_clean(value: Decimal) -> String {
    if value.is_zero() {
        return "0".to_string();
    }
    value.normalize().to_string()
}

fn parse_prefix_mode(compact: &str) -> (Option<char>, usize) {
    let bytes = compact.as_bytes();
    if bytes.len() >= 2 && bytes[1] == b'=' && matches!(bytes[0], b'+' | b'-' | b'*' | b'/') {
        return (Some(bytes[0] as char), 2);
    }
    if bytes.first() == Some(&b'=') {
        return (None, 1);
    }
    (None, 0)
}

fn parse_number_literal(raw: &str) -> Option<Decimal> {
    let (neg, unsigned) = match raw.as_bytes().first().copied() {
        Some(b'+') => (false, &raw[1..]),
        Some(b'-') => (true, &raw[1..]),
        _ => (false, raw),
    };
    if !is_unsigned_number_token(unsigned) {
        return None;
    }
    let normalized = if let Some(whole) = unsigned.strip_suffix('.') {
        whole.to_string()
    } else if unsigned.starts_with('.') {
        format!("0{unsigned}")
    } else {
        unsigned.to_string()
    };
    let value = Decimal::from_str(&normalized).ok()?;
    Some(if neg && !value.is_zero() {
        -value
    } else {
        value
    })
}

fn is_unsigned_number_token(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let mut dots = 0_u8;
    let mut digits = 0_usize;
    for b in s.bytes() {
        match b {
            b'0'..=b'9' => digits += 1,
            b'.' => {
                dots += 1;
                if dots > 1 {
                    return false;
                }
            }
            _ => return false,
        }
    }
    digits > 0
}

#[derive(Clone, Copy)]
struct Operand {
    value: Decimal,
    percent: bool,
}

fn calculate(left: Operand, op: char, right: Operand, keep_rates: bool) -> Option<Operand> {
    let a = left.value;
    let mut b = right.value;
    if matches!(op, '+' | '-') && right.percent && !left.percent {
        b = a.checked_mul(b)?;
    }
    let value = match op {
        '+' => a.checked_add(b)?,
        '-' => a.checked_sub(b)?,
        '*' => a.checked_mul(b)?,
        '/' => {
            if b.is_zero() {
                return None;
            }
            a.checked_div(b)?
        }
        _ => return None,
    };
    let percent = match op {
        '+' | '-' => left.percent && right.percent,
        '*' => keep_rates && (left.percent || right.percent),
        '/' => keep_rates && left.percent && !right.percent,
        _ => false,
    };
    Some(Operand { value, percent })
}

struct DecimalParser<'a> {
    bytes: &'a [u8],
    pos: usize,
    keep_rates: bool,
}

impl<'a> DecimalParser<'a> {
    fn new(input: &'a str, pos: usize, keep_rates: bool) -> Self {
        Self {
            bytes: input.as_bytes(),
            pos,
            keep_rates,
        }
    }

    fn at_end(&self) -> bool {
        self.pos == self.bytes.len()
    }

    fn take(&mut self, token: u8) -> bool {
        if self.bytes.get(self.pos) == Some(&token) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn sum(&mut self, depth: usize) -> Option<Operand> {
        if depth > MAX_EXPR_DEPTH {
            return None;
        }
        let mut result = self.product(depth + 1)?;
        while self.take(b'+') || self.take(b'-') {
            let op = self.bytes[self.pos - 1] as char;
            let rhs = self.product(depth + 1)?;
            result = calculate(result, op, rhs, false)?;
        }
        Some(result)
    }

    fn product(&mut self, depth: usize) -> Option<Operand> {
        if depth > MAX_EXPR_DEPTH {
            return None;
        }
        let mut result = self.signed(depth + 1)?;
        while self.take(b'*') || self.take(b'/') {
            let op = self.bytes[self.pos - 1] as char;
            let rhs = self.signed(depth + 1)?;
            result = calculate(result, op, rhs, self.keep_rates)?;
        }
        Some(result)
    }

    fn signed(&mut self, depth: usize) -> Option<Operand> {
        if depth > MAX_EXPR_DEPTH {
            return None;
        }
        if self.take(b'+') {
            return self.signed(depth + 1);
        }
        if self.take(b'-') {
            let inner = self.signed(depth + 1)?;
            return Some(Operand {
                value: -inner.value,
                percent: inner.percent,
            });
        }
        let operand = self.primary(depth + 1)?;
        if !self.take(b'%') {
            return Some(operand);
        }
        if operand.percent {
            return None;
        }
        Some(Operand {
            value: operand.value.checked_div(Decimal::ONE_HUNDRED)?,
            percent: true,
        })
    }

    fn primary(&mut self, depth: usize) -> Option<Operand> {
        if depth > MAX_EXPR_DEPTH {
            return None;
        }
        if self.take(b'(') {
            let inner = self.sum(depth + 1)?;
            if !self.take(b')') {
                return None;
            }
            return Some(inner);
        }
        let start = self.pos;
        while let Some(&b) = self.bytes.get(self.pos) {
            if b.is_ascii_digit() || b == b'.' {
                self.pos += 1;
            } else {
                break;
            }
        }
        if self.pos == start {
            return None;
        }
        let token = std::str::from_utf8(&self.bytes[start..self.pos]).ok()?;
        let value = parse_number_literal(token)?;
        Some(Operand {
            value,
            percent: false,
        })
    }
}

/// Decimal input field with arithmetic/percentage expression evaluation and relative adjustment
/// support on Enter or blur.
#[component]
pub fn DecimalInput(
    value: RwSignal<String>,
    #[prop(optional)] on_commit: Option<Callback<Option<Decimal>>>,
    #[prop(default = 4)] scale: u32,
    #[prop(default = false)] percentage_points: bool,
    #[prop(into, optional)] label: Option<String>,
    #[prop(into, optional)] placeholder: Option<String>,
    #[prop(into, default = "decimal-input".to_string())] target: String,
    #[prop(into, default = Signal::derive(|| false))] disabled: Signal<bool>,
    #[prop(default = false)] required: bool,
) -> impl IntoView {
    let initial_base =
        evaluate_decimal_input(&value.get_untracked(), None, scale, percentage_points);
    let last_valid = StoredValue::new(initial_base);
    let focused = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let input_id = format!("{target}-field");
    let error_target = format!("{target}-error");
    let has_label = label.is_some();

    Effect::new(move |_| {
        let raw = value.get();
        if !focused.get_untracked() {
            if raw.trim().is_empty() {
                last_valid.set_value(None);
                error.set(None);
            } else if let Some(plain) = parse_decimal_input(&raw) {
                last_valid.set_value(Some(plain));
                error.set(None);
            }
        }
    });

    let commit = move || {
        let raw = value.get_untracked();
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            last_valid.set_value(None);
            error.set(None);
            if let Some(cb) = on_commit {
                cb.run(None);
            }
            return;
        }
        let base = last_valid.get_value();
        match evaluate_decimal_input(trimmed, base, scale, percentage_points) {
            Some(result) => {
                let formatted = format_decimal_clean(result);
                last_valid.set_value(Some(result));
                error.set(None);
                value.set(formatted);
                if let Some(cb) = on_commit {
                    cb.run(Some(result));
                }
            }
            None => {
                error.set(Some("Enter a valid number or expression.".to_string()));
                if let Some(cb) = on_commit {
                    cb.run(None);
                }
            }
        }
    };

    view! {
        <div class="tc-field" data-target=target.clone()>
            {label.map(|text| view! {
                <label class="tc-label" for=input_id.clone()>{text}</label>
            })}
            <input
                id=if has_label { Some(input_id) } else { None }
                type="text"
                inputmode="decimal"
                class=move || {
                    if error.with(Option::is_some) {
                        "tc-input tc-input-error tc-num"
                    } else {
                        "tc-input tc-num"
                    }
                }
                placeholder=placeholder.unwrap_or_default()
                required=required
                disabled=move || disabled.get()
                aria-invalid=move || error.with(Option::is_some).then_some("true")
                data-target=format!("{target}-field")
                prop:value=move || value.get()
                on:focus=move |_| focused.set(true)
                on:input=move |ev| {
                    value.set(event_target_value(&ev));
                    error.set(None);
                }
                on:blur=move |_| {
                    focused.set(false);
                    commit();
                }
                on:keydown=move |ev: leptos::ev::KeyboardEvent| {
                    if ev.key() == "Enter" {
                        ev.prevent_default();
                        commit();
                    }
                }
            />
            {move || error.get().map(|msg| view! {
                <span class="tc-field-error" role="alert" data-target=error_target.clone()>
                    {msg}
                </span>
            })}
        </div>
    }
}

/// Reply channel handed to a [`SearchPicker`] search callback.
pub type PickerReply<T> = Callback<Result<Vec<T>, String>>;

/// Async search callback invoked by [`SearchPicker`] with `(query, reply)`.
pub type PickerSearch<T> = Callback<(String, PickerReply<T>)>;

/// Wraps an API search call for [`SearchPicker`] using [`spawn_api`].
pub fn api_picker_search<T, F, Fut>(ctx: AppContext, f: F) -> PickerSearch<T>
where
    T: Send + Sync + 'static,
    F: Fn(tradocraft_api_client::Client, String) -> Fut + Copy + Send + Sync + 'static,
    Fut: std::future::Future<Output = Result<Vec<T>, tradocraft_api_client::ApiError>> + 'static,
{
    Callback::new(move |(query, reply): (String, PickerReply<T>)| {
        spawn_api(
            ctx,
            move |client| f(client, query),
            move |res| reply.run(res.map_err(|err| err.user_message())),
        );
    })
}

/// Async server-backed Many2One autocomplete selector with stale-response filtering and keyboard
/// navigation (`ArrowUp`, `ArrowDown`, `Enter`, `Escape`).
#[component]
pub fn SearchPicker<T>(
    search: PickerSearch<T>,
    selected: RwSignal<Option<T>>,
    display: Callback<T, String>,
    #[prop(optional)] subtitle: Option<Callback<T, Option<String>>>,
    #[prop(optional)] on_select: Option<Callback<Option<T>>>,
    #[prop(into, optional)] label: Option<String>,
    #[prop(into, default = "Search…".to_string())] placeholder: String,
    #[prop(into, default = "search-picker".to_string())] target: String,
    #[prop(into, default = Signal::derive(|| false))] disabled: Signal<bool>,
    #[prop(default = false)] clear_on_select: bool,
    #[prop(default = true)] allow_clear: bool,
) -> impl IntoView
where
    T: Clone + Send + Sync + 'static,
{
    let initial_text = selected
        .get_untracked()
        .map(|item| display.run(item))
        .unwrap_or_default();
    let query = RwSignal::new(initial_text);
    let results = RwSignal::new(Vec::<T>::new());
    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let open = RwSignal::new(false);
    let highlighted = RwSignal::new(0_usize);
    let editing = RwSignal::new(false);
    let guard = RequestGuard::new();

    let input_id = format!("{target}-input");
    let listbox_id = format!("{target}-listbox");
    let has_label = label.is_some();

    Effect::new(move |_| {
        let current = selected.get();
        if !editing.get_untracked() {
            match current {
                Some(item) if !clear_on_select => query.set(display.run(item)),
                Some(_) => query.set(String::new()),
                None => query.set(String::new()),
            }
        }
    });

    let trigger_search = move |q: String| {
        if disabled.get_untracked() {
            return;
        }
        let gen = guard.bump();
        loading.set(true);
        error.set(None);
        open.set(true);
        // The old results belong to the old query: drop them, so Enter or a click cannot pick one
        // while the reply for the new query is still pending.
        results.set(Vec::new());
        highlighted.set(0);
        let reply = Callback::new(move |res: Result<Vec<T>, String>| {
            if !guard.is_current(gen) {
                return;
            }
            let _ = set_alive(loading, false);
            match res {
                Ok(list) => {
                    let _ = set_alive(results, list);
                    let _ = set_alive(highlighted, 0);
                }
                Err(msg) => {
                    let _ = set_alive(results, Vec::new());
                    let _ = set_alive(error, Some(msg));
                }
            }
        });
        search.run((q, reply));
    };

    let choose_item = move |item: T| {
        guard.bump();
        editing.set(false);
        loading.set(false);
        error.set(None);
        open.set(false);
        let text = if clear_on_select {
            String::new()
        } else {
            display.run(item.clone())
        };
        selected.set(Some(item.clone()));
        query.set(text);
        if let Some(cb) = on_select {
            cb.run(Some(item));
        }
    };

    // Leaves the picker without choosing: the box shows the committed selection again (or nothing),
    // never the half-typed search text of an abandoned search.
    let dismiss = move || {
        guard.bump();
        editing.set(false);
        loading.set(false);
        open.set(false);
        let text = match selected.get_untracked() {
            Some(item) if !clear_on_select => display.run(item),
            _ => String::new(),
        };
        query.set(text);
    };

    let clear_selection = move || {
        guard.bump();
        editing.set(false);
        loading.set(false);
        error.set(None);
        open.set(false);
        results.set(Vec::new());
        selected.set(None);
        query.set(String::new());
        if let Some(cb) = on_select {
            cb.run(None);
        }
    };

    let target_menu = StoredValue::new(format!("{target}-menu"));
    let target_clear = format!("{target}-clear");
    let target_input = format!("{target}-input");
    let target_opt_prefix = StoredValue::new(format!("{target}-option"));
    let listbox_id_sv = StoredValue::new(listbox_id.clone());

    view! {
        <div class="tc-field tc-picker" data-target=target>
            {label.map(|text| view! {
                <label class="tc-label" for=input_id.clone()>{text}</label>
            })}
            <div class="tc-picker-control">
                <input
                    id=if has_label { Some(input_id) } else { None }
                    type="text"
                    role="combobox"
                    aria-autocomplete="list"
                    aria-expanded=move || if open.get() { "true" } else { "false" }
                    aria-controls=listbox_id.clone()
                    class="tc-input tc-picker-input"
                    placeholder=placeholder
                    disabled=move || disabled.get()
                    data-target=target_input
                    prop:value=move || query.get()
                    on:focus=move |_| {
                        if !open.get_untracked() && !disabled.get_untracked() {
                            trigger_search(query.get_untracked());
                        }
                    }
                    on:input=move |ev| {
                        let next = event_target_value(&ev);
                        editing.set(true);
                        query.set(next.clone());
                        trigger_search(next);
                    }
                    on:blur=move |_| dismiss()
                    on:keydown=move |ev: leptos::ev::KeyboardEvent| {
                        match ev.key().as_str() {
                            "ArrowDown" => {
                                ev.prevent_default();
                                if !open.get_untracked() {
                                    trigger_search(query.get_untracked());
                                } else {
                                    let len = results.with_untracked(Vec::len);
                                    if len > 0 {
                                        highlighted.update(|idx| {
                                            if *idx + 1 < len {
                                                *idx += 1;
                                            }
                                        });
                                    }
                                }
                            }
                            "ArrowUp" => {
                                ev.prevent_default();
                                highlighted.update(|idx| *idx = idx.saturating_sub(1));
                            }
                            "Enter" => {
                                if open.get_untracked() {
                                    let idx = highlighted.get_untracked();
                                    let picked = results.with_untracked(|list| list.get(idx).cloned());
                                    if let Some(item) = picked {
                                        ev.prevent_default();
                                        choose_item(item);
                                    }
                                }
                            }
                            "Escape" if open.get_untracked() => {
                                ev.stop_propagation();
                                dismiss();
                            }
                            _ => {}
                        }
                    }
                />
                {move || {
                    let show_clear = allow_clear
                        && !disabled.get()
                        && (selected.with(Option::is_some) || !query.with(String::is_empty));
                    show_clear.then(|| view! {
                        <button
                            type="button"
                            class="tc-btn tc-btn-ghost tc-btn-sm tc-picker-clear"
                            aria-label="Clear selection"
                            data-target=target_clear.clone()
                            on:mousedown=|ev: leptos::ev::MouseEvent| ev.prevent_default()
                            on:click=move |_| clear_selection()
                        >
                            "×"
                        </button>
                    })
                }}
            </div>
            <Show when=move || open.get()>
                <div
                    id=move || listbox_id_sv.get_value()
                    class="tc-picker-menu"
                    role="listbox"
                    data-target=move || target_menu.get_value()
                >
                    {move || {
                        if let Some(err) = error.get() {
                            return view! {
                                <div class="tc-picker-state tc-picker-error" role="alert">
                                    {err}
                                </div>
                            }
                            .into_any();
                        }
                        if loading.get() && results.with(Vec::is_empty) {
                            return view! {
                                <div class="tc-picker-state">"Searching…"</div>
                            }
                            .into_any();
                        }
                        let list = results.get();
                        if list.is_empty() {
                            return view! {
                                <div class="tc-picker-state">"No matches found."</div>
                            }
                            .into_any();
                        }
                        let prefix = target_opt_prefix.get_value();
                        list.into_iter()
                            .enumerate()
                            .map(|(idx, item)| {
                                let title = display.run(item.clone());
                                let sub = subtitle.and_then(|cb| cb.run(item.clone()));
                                let opt_target = format!("{prefix}-{idx}");
                                let opt_item = item.clone();
                                view! {
                                    <button
                                        type="button"
                                        role="option"
                                        aria-selected=move || {
                                            if highlighted.get() == idx { "true" } else { "false" }
                                        }
                                        class=move || {
                                            if highlighted.get() == idx {
                                                "tc-picker-option tc-picker-option-active"
                                            } else {
                                                "tc-picker-option"
                                            }
                                        }
                                        data-target=opt_target
                                        on:mousedown=|ev: leptos::ev::MouseEvent| ev.prevent_default()
                                        on:mouseenter=move |_| highlighted.set(idx)
                                        on:click=move |_| choose_item(opt_item.clone())
                                    >
                                        <span class="tc-picker-option-title">{title}</span>
                                        {sub.map(|s| view! {
                                            <span class="tc-picker-option-sub">{s}</span>
                                        })}
                                    </button>
                                }
                            })
                            .collect_view()
                            .into_any()
                    }}
                </div>
            </Show>
        </div>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> Decimal {
        Decimal::from_str(s).expect("valid decimal literal")
    }

    #[test]
    fn parses_plain_decimal_inputs() {
        assert_eq!(parse_decimal_input(" 12.50 "), Some(dec("12.50")));
        assert_eq!(parse_decimal_input("-3,25"), Some(dec("-3.25")));
        assert_eq!(parse_decimal_input("+7"), Some(dec("7")));
        assert_eq!(parse_decimal_input(".5"), Some(dec("0.5")));
        assert_eq!(parse_decimal_input("12."), Some(dec("12")));
        assert_eq!(parse_decimal_input(""), None);
        assert_eq!(parse_decimal_input("12 + 3"), None);
        assert_eq!(parse_decimal_input("1e4"), None);
        assert_eq!(parse_decimal_input("."), None);
    }

    #[test]
    fn evaluates_arithmetic_and_percentages() {
        assert_eq!(
            evaluate_decimal_input("200 + 10%", None, 4, false),
            Some(dec("220"))
        );
        assert_eq!(
            evaluate_decimal_input("200 - 15%", None, 4, false),
            Some(dec("170"))
        );
        assert_eq!(
            evaluate_decimal_input("(10 + 5) * 2,5", None, 4, false),
            Some(dec("37.5"))
        );
        assert_eq!(
            evaluate_decimal_input("= 100 / 3", None, 2, false),
            Some(dec("33.33"))
        );
        assert_eq!(
            evaluate_decimal_input("10% + 5%", None, 4, true),
            Some(dec("15"))
        );
        assert_eq!(
            evaluate_decimal_input("10% * 2", None, 4, true),
            Some(dec("20"))
        );
    }

    #[test]
    fn evaluates_relative_adjustments() {
        let base = Some(dec("200"));
        assert_eq!(
            evaluate_decimal_input("+= 10%", base, 4, false),
            Some(dec("220"))
        );
        assert_eq!(
            evaluate_decimal_input("-= 25", base, 4, false),
            Some(dec("175"))
        );
        assert_eq!(
            evaluate_decimal_input("*= 1,1", base, 4, false),
            Some(dec("220"))
        );
        assert_eq!(
            evaluate_decimal_input("/= 4", base, 4, false),
            Some(dec("50"))
        );
        assert_eq!(evaluate_decimal_input("+= 10", None, 4, false), None);
    }

    #[test]
    fn rejects_invalid_or_division_by_zero_expressions() {
        assert_eq!(evaluate_decimal_input("10 / 0", None, 4, false), None);
        assert_eq!(evaluate_decimal_input("10 +", None, 4, false), None);
        assert_eq!(evaluate_decimal_input("(1 + 2", None, 4, false), None);
        assert_eq!(evaluate_decimal_input("10%%", None, 4, false), None);
        assert_eq!(evaluate_decimal_input("abc", None, 4, false), None);
    }

    #[test]
    fn formats_decimals_cleanly() {
        assert_eq!(format_decimal_clean(dec("0.0000")), "0");
        assert_eq!(format_decimal_clean(dec("-0.00")), "0");
        assert_eq!(format_decimal_clean(dec("12.500")), "12.5");
        assert_eq!(format_decimal_clean(dec("100.00")), "100");
    }
}
