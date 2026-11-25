//! Finite loading of work centres and the conflicts of moving an operation (C3, work-centre half).
//! Pure like [`crate::schedule`]: no database, no clock. Dates are whole days.
//!
//! Where [`crate::schedule::schedule_forward`] ignores everybody else, this module knows the
//! minutes the other operations already take per work centre and day:
//! * a day offers `capacity_minutes_on` minus the minutes already booked;
//! * one operation runs on one unit, so it takes at most `minutes_on` (one unit) of a day, however
//!   many units are free.

use std::collections::HashMap;

use chrono::NaiveDate;

use crate::schedule::{spread_load, Calendar, NoWorkingTime, OpSpec, Placement, MAX_DAYS};

/// Minutes of other operations, per work-centre calendar (an index like [`OpSpec::calendar`]) and
/// day.
pub type BookedLoad = Vec<HashMap<NaiveDate, i64>>;

/// Places the operations one after the other from `start`, filling only what the other
/// operations in `booked` leave free. An operation with no minutes sits on the day the previous
/// one ended. Minutes of operations placed earlier in this call count as booked for the later
/// ones.
///
/// Only the first and the last day of an operation are stored, and everything that reads them
/// (the capacity page, the board, [`detect`]) spreads its minutes over the working days of that
/// range in proportion ([`spread_load`]). So a candidate range found by filling the free minutes
/// is checked against that split too: when any day would exceed the centre's capacity, the search
/// goes on from the day after the candidate's first day.
pub fn schedule_finite(
    ops: &[OpSpec],
    calendars: &[Calendar],
    booked: &BookedLoad,
    start: NaiveDate,
) -> Result<Vec<Placement>, NoWorkingTime> {
    let mut own: Vec<HashMap<NaiveDate, i64>> = vec![HashMap::new(); calendars.len()];
    let mut out = Vec::with_capacity(ops.len());
    let mut cursor = start;
    for (i, op) in ops.iter().enumerate() {
        if op.minutes <= 0 {
            out.push(Placement {
                start: cursor,
                end: cursor,
            });
            continue;
        }
        let cal = &calendars[op.calendar];
        let used = |own: &HashMap<NaiveDate, i64>, day: NaiveDate| -> i64 {
            booked
                .get(op.calendar)
                .and_then(|m| m.get(&day))
                .copied()
                .unwrap_or(0)
                + own.get(&day).copied().unwrap_or(0)
        };
        let fail = NoWorkingTime { op: i };
        let mut from_day = cursor;
        let mut attempts = 0_i64;
        let (first, last) = loop {
            attempts += 1;
            if attempts > MAX_DAYS {
                return Err(fail);
            }
            // Fill the free minutes of the days from `from_day` on.
            let mut remaining = op.minutes;
            let mut day = from_day;
            let mut first_day = None;
            let mut walked = 0_i64;
            let last_day = loop {
                let free = (cal.capacity_minutes_on(day) - used(&own[op.calendar], day)).max(0);
                let part = remaining.min(free).min(cal.minutes_on(day));
                if part > 0 {
                    first_day.get_or_insert(day);
                    remaining -= part;
                    if remaining == 0 {
                        break day;
                    }
                }
                walked += 1;
                if walked > MAX_DAYS {
                    return Err(fail);
                }
                day = day.succ_opt().ok_or(fail)?;
            };
            let first_day = first_day.expect("an operation with minutes works at least one day");
            // The split everybody else will see for this range.
            let parts = spread_load(op.minutes, first_day, last_day, cal);
            let fits = parts
                .iter()
                .all(|(d, m)| used(&own[op.calendar], *d) + m <= cal.capacity_minutes_on(*d));
            if fits {
                for (d, m) in parts {
                    *own[op.calendar].entry(d).or_insert(0) += m;
                }
                break (first_day, last_day);
            }
            from_day = first_day.succ_opt().ok_or(fail)?;
        };
        out.push(Placement {
            start: first,
            end: last,
        });
        // The next operation may start on the day this one ended.
        cursor = last;
    }
    Ok(out)
}

/// How bad a conflict is. Errors need an explicit override (`force`), warnings do not.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictKind {
    /// The work centre is not active.
    InactiveWorkCentre,
    /// The operation is running or finished and cannot be moved.
    OperationStarted,
    /// The operation's first or last day has no working minutes (closure or a day off).
    OnClosure,
    /// The day's load, with this operation, exceeds what the work centre offers.
    Overload,
    /// It starts before the previous operation of the same order has ended.
    BeforePredecessor,
    /// It ends after the next operation of the same order has started.
    AfterSuccessor,
    /// It ends after the order's planned-ready date.
    LaterThanReady,
}

impl ConflictKind {
    pub fn severity(self) -> Severity {
        match self {
            ConflictKind::InactiveWorkCentre
            | ConflictKind::OperationStarted
            | ConflictKind::OnClosure
            | ConflictKind::Overload
            | ConflictKind::BeforePredecessor => Severity::Error,
            ConflictKind::AfterSuccessor | ConflictKind::LaterThanReady => Severity::Warning,
        }
    }

    /// The key the app translates.
    pub fn message_key(self) -> &'static str {
        match self {
            ConflictKind::InactiveWorkCentre => "production.conflict.inactive_work_centre",
            ConflictKind::OperationStarted => "production.conflict.operation_started",
            ConflictKind::OnClosure => "production.conflict.on_closure",
            ConflictKind::Overload => "production.conflict.overload",
            ConflictKind::BeforePredecessor => "production.conflict.before_predecessor",
            ConflictKind::AfterSuccessor => "production.conflict.after_successor",
            ConflictKind::LaterThanReady => "production.conflict.later_than_ready",
        }
    }
}

/// One problem with a move. `day` is the day concerned (the overloaded day, the closed day, ...).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Conflict {
    pub kind: ConflictKind,
    pub day: Option<NaiveDate>,
}

/// An operation moved to a work centre and a range of days.
#[derive(Debug, Clone, Copy)]
pub struct MoveCandidate {
    pub minutes: i64,
    pub start: NaiveDate,
    pub end: NaiveDate,
    pub work_centre_active: bool,
    /// The operation is pending (not running, not done, not skipped).
    pub operation_open: bool,
    /// When the previous operation of the order ends, if there is one.
    pub predecessor_end: Option<NaiveDate>,
    /// When the next operation of the order starts, if there is one.
    pub successor_start: Option<NaiveDate>,
    /// The order's planned-ready date, if set.
    pub ready_date: Option<NaiveDate>,
}

/// Whether the move is allowed without `force`: no error among the conflicts.
pub fn has_errors(conflicts: &[Conflict]) -> bool {
    conflicts
        .iter()
        .any(|c| c.kind.severity() == Severity::Error)
}

/// The conflicts of moving the operation. `other_load` is the minutes the **other** operations of
/// the target work centre take per day (the operation itself is not in it, so a move within a
/// centre does not collide with its old place).
pub fn detect(
    c: &MoveCandidate,
    cal: &Calendar,
    other_load: &HashMap<NaiveDate, i64>,
) -> Vec<Conflict> {
    let mut out = Vec::new();
    let mut push = |kind, day| out.push(Conflict { kind, day });
    if !c.work_centre_active {
        push(ConflictKind::InactiveWorkCentre, None);
    }
    if !c.operation_open {
        push(ConflictKind::OperationStarted, None);
    }
    for day in [c.start, c.end] {
        if cal.minutes_on(day) == 0 {
            push(ConflictKind::OnClosure, Some(day));
            if c.start == c.end {
                break;
            }
        }
    }
    for (day, minutes) in spread_load(c.minutes, c.start, c.end, cal) {
        let booked = other_load.get(&day).copied().unwrap_or(0);
        if booked + minutes > cal.capacity_minutes_on(day) {
            push(ConflictKind::Overload, Some(day));
        }
    }
    if let Some(prev) = c.predecessor_end.filter(|prev| c.start < *prev) {
        push(ConflictKind::BeforePredecessor, Some(prev));
    }
    if let Some(next) = c.successor_start.filter(|next| c.end > *next) {
        push(ConflictKind::AfterSuccessor, Some(next));
    }
    if let Some(ready) = c.ready_date.filter(|ready| c.end > *ready) {
        push(ConflictKind::LaterThanReady, Some(ready));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(day: u32) -> NaiveDate {
        // February 2027: the 1st is a Monday.
        NaiveDate::from_ymd_opt(2027, 2, day).unwrap()
    }

    fn cal(capacity: i32) -> Calendar {
        Calendar::new(vec![], vec![], capacity)
    }

    fn op(minutes: i64) -> OpSpec {
        OpSpec {
            minutes,
            calendar: 0,
        }
    }

    fn booked(entries: &[(u32, i64)]) -> BookedLoad {
        vec![entries.iter().map(|(day, m)| (d(*day), *m)).collect()]
    }

    fn candidate() -> MoveCandidate {
        MoveCandidate {
            minutes: 240,
            start: d(2),
            end: d(2),
            work_centre_active: true,
            operation_open: true,
            predecessor_end: None,
            successor_start: None,
            ready_date: None,
        }
    }

    fn kinds(cs: &[Conflict]) -> Vec<ConflictKind> {
        cs.iter().map(|c| c.kind).collect()
    }

    #[test]
    fn an_empty_centre_behaves_like_infinite_capacity() {
        let cals = [cal(1)];
        let p = schedule_finite(&[op(600)], &cals, &booked(&[]), d(1)).unwrap();
        assert_eq!((p[0].start, p[0].end), (d(1), d(2)));
    }

    #[test]
    fn booked_minutes_push_the_operation_to_free_days() {
        let cals = [cal(1)];
        // Monday is full, Tuesday has 120 free minutes.
        let p = schedule_finite(&[op(300)], &cals, &booked(&[(1, 480), (2, 360)]), d(1)).unwrap();
        // Filling Tuesday's 120 and 180 on Wednesday would be stored as Tuesday to Wednesday and
        // read back as 150 a day, which overloads Tuesday: the search goes on to Wednesday.
        assert_eq!((p[0].start, p[0].end), (d(3), d(3)));
    }

    #[test]
    fn a_range_that_the_stored_dates_would_spread_onto_a_full_day_is_not_taken() {
        let cals = [cal(1)];
        // Monday has 60 free minutes, Tuesday is free: 540 minutes filled greedily are 60 + 480.
        let load = booked(&[(1, 420)]);
        let p = schedule_finite(&[op(540)], &cals, &load, d(1)).unwrap();
        assert_eq!(
            (p[0].start, p[0].end),
            (d(2), d(3)),
            "spread as 270 and 270"
        );
        // Whatever is placed passes the same check as a move onto those dates.
        let c = MoveCandidate {
            minutes: 540,
            start: p[0].start,
            end: p[0].end,
            work_centre_active: true,
            operation_open: true,
            predecessor_end: None,
            successor_start: None,
            ready_date: None,
        };
        assert!(detect(&c, &cals[0], &load[0]).is_empty());
    }

    #[test]
    fn what_is_placed_never_overloads_a_day_in_any_arrangement() {
        let cals = [cal(1), cal(2)];
        for centre in 0..2 {
            for minutes in [30_i64, 200, 480, 500, 900, 1300] {
                for entries in [
                    vec![],
                    vec![(1, 100)],
                    vec![(1, 480), (3, 250)],
                    vec![(1, 300), (2, 100), (3, 450), (4, 20)],
                ] {
                    let mut load = booked(&entries);
                    load = vec![load[0].clone(), load[0].clone()];
                    let spec = OpSpec {
                        minutes,
                        calendar: centre,
                    };
                    let Ok(p) = schedule_finite(&[spec], &cals, &load, d(1)) else {
                        continue;
                    };
                    let c = MoveCandidate {
                        minutes,
                        start: p[0].start,
                        end: p[0].end,
                        work_centre_active: true,
                        operation_open: true,
                        predecessor_end: None,
                        successor_start: None,
                        ready_date: None,
                    };
                    let found = detect(&c, &cals[centre], &load[centre]);
                    assert!(
                        !found.iter().any(|x| x.kind == ConflictKind::Overload),
                        "{minutes} min on centre {centre} with {entries:?}: {found:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn a_free_unit_lets_another_operation_run_the_same_day() {
        let cals = [cal(2)];
        // One of two units is taken all Monday; the other is free but one operation uses one unit.
        let p = schedule_finite(&[op(480)], &cals, &booked(&[(1, 480)]), d(1)).unwrap();
        assert_eq!((p[0].start, p[0].end), (d(1), d(1)));
        // Both units taken: nothing is left on Monday.
        let p = schedule_finite(&[op(60)], &cals, &booked(&[(1, 960)]), d(1)).unwrap();
        assert_eq!(p[0].start, d(2));
    }

    #[test]
    fn one_operation_never_uses_more_than_one_unit_a_day() {
        let cals = [cal(3)];
        let p = schedule_finite(&[op(960)], &cals, &booked(&[]), d(1)).unwrap();
        assert_eq!((p[0].start, p[0].end), (d(1), d(2)), "two days of 480");
    }

    #[test]
    fn operations_of_one_call_count_against_each_other() {
        let cals = [cal(1)];
        let p = schedule_finite(&[op(480), op(60)], &cals, &booked(&[]), d(1)).unwrap();
        assert_eq!((p[0].start, p[0].end), (d(1), d(1)));
        assert_eq!(p[1].start, d(2), "monday is full after the first");
    }

    #[test]
    fn a_centre_that_is_never_free_gives_up() {
        let closed = Calendar::new(vec![], vec![(d(1), d(1) + chrono::Days::new(2000))], 1);
        assert_eq!(
            schedule_finite(&[op(60)], &[closed], &booked(&[]), d(1)),
            Err(NoWorkingTime { op: 0 })
        );
    }

    #[test]
    fn a_clean_move_has_no_conflicts() {
        assert!(detect(&candidate(), &cal(1), &HashMap::new()).is_empty());
    }

    #[test]
    fn overload_names_the_day() {
        let other: HashMap<_, _> = [(d(2), 400)].into();
        let cs = detect(&candidate(), &cal(1), &other);
        assert_eq!(
            cs,
            vec![Conflict {
                kind: ConflictKind::Overload,
                day: Some(d(2))
            }]
        );
        assert!(has_errors(&cs));
    }

    #[test]
    fn a_second_unit_absorbs_the_same_load() {
        let other: HashMap<_, _> = [(d(2), 400)].into();
        assert!(detect(&candidate(), &cal(2), &other).is_empty());
    }

    #[test]
    fn a_weekend_start_is_on_closure() {
        let mut c = candidate();
        c.start = d(6);
        c.end = d(6);
        let cs = detect(&c, &cal(1), &HashMap::new());
        assert_eq!(kinds(&cs).first(), Some(&ConflictKind::OnClosure));
        assert_eq!(
            cs.iter()
                .filter(|c| c.kind == ConflictKind::OnClosure)
                .count(),
            1,
            "a one-day move reports its day once"
        );
    }

    #[test]
    fn a_closure_range_is_on_closure() {
        let closed = Calendar::new(vec![], vec![(d(2), d(2))], 1);
        let cs = detect(&candidate(), &closed, &HashMap::new());
        assert!(kinds(&cs).contains(&ConflictKind::OnClosure));
    }

    #[test]
    fn order_of_operations_is_checked() {
        let mut c = candidate();
        c.predecessor_end = Some(d(3));
        c.successor_start = Some(d(1));
        let cs = detect(&c, &cal(1), &HashMap::new());
        assert_eq!(
            kinds(&cs),
            vec![
                ConflictKind::BeforePredecessor,
                ConflictKind::AfterSuccessor
            ]
        );
        assert!(has_errors(&cs));
    }

    #[test]
    fn later_than_ready_is_only_a_warning() {
        let mut c = candidate();
        c.ready_date = Some(d(1));
        let cs = detect(&c, &cal(1), &HashMap::new());
        assert_eq!(kinds(&cs), vec![ConflictKind::LaterThanReady]);
        assert!(!has_errors(&cs));
    }

    #[test]
    fn inactive_centres_and_started_operations_are_refused() {
        let mut c = candidate();
        c.work_centre_active = false;
        c.operation_open = false;
        let cs = detect(&c, &cal(1), &HashMap::new());
        assert_eq!(
            kinds(&cs),
            vec![
                ConflictKind::InactiveWorkCentre,
                ConflictKind::OperationStarted
            ]
        );
        assert!(has_errors(&cs));
    }

    #[test]
    fn message_keys_are_unique() {
        let all = [
            ConflictKind::InactiveWorkCentre,
            ConflictKind::OperationStarted,
            ConflictKind::OnClosure,
            ConflictKind::Overload,
            ConflictKind::BeforePredecessor,
            ConflictKind::AfterSuccessor,
            ConflictKind::LaterThanReady,
        ];
        let keys: std::collections::HashSet<_> = all.iter().map(|k| k.message_key()).collect();
        assert_eq!(keys.len(), all.len());
    }
}
