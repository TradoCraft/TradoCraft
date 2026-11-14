//! Scheduling routing operations onto work-centre calendars (ADR 0063). Everything here is pure:
//! no database, no clock. Dates are whole days; an operation takes the working minutes of its
//! work centre day by day.
//!
//! Simplifications, on purpose (the finite-capacity board is C3):
//! * **Infinite capacity.** Other orders' load is not looked at.
//! * **One unit per operation.** An operation runs on one unit of the work centre, so `capacity`
//!   (parallel units) only widens the capacity a day offers; it never shortens an operation.
//! * **Sequential.** Operations run in order. The next one may start on the day the previous one
//!   ends when working time is left that day; the minutes already used that day are counted
//!   against the next work centre's day length.

use chrono::{Datelike, NaiveDate, NaiveTime};

/// How far ahead an operation is looked for working time before giving up.
pub const MAX_DAYS: i64 = 730;

/// Longest range [`spread_load`] walks; a longer one is cut off.
const MAX_SPREAD_DAYS: i64 = 3660;

/// A block of working time on a weekday (1 = Monday ... 7 = Sunday).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HoursBlock {
    pub weekday: i16,
    pub start: NaiveTime,
    pub end: NaiveTime,
}

/// The blocks a work centre without hours of its own works: Monday to Friday 08:00-12:00 and
/// 13:00-17:00 (eight hours).
pub fn default_blocks() -> Vec<HoursBlock> {
    let t = |h, m| NaiveTime::from_hms_opt(h, m, 0).expect("valid time");
    (1..=5)
        .flat_map(|weekday| {
            [
                HoursBlock {
                    weekday,
                    start: t(8, 0),
                    end: t(12, 0),
                },
                HoursBlock {
                    weekday,
                    start: t(13, 0),
                    end: t(17, 0),
                },
            ]
        })
        .collect()
}

/// When a work centre can work, and with how many units at once.
#[derive(Debug, Clone)]
pub struct Calendar {
    hours: Vec<HoursBlock>,
    /// Inclusive date ranges on which nothing is worked (holidays, maintenance).
    closures: Vec<(NaiveDate, NaiveDate)>,
    /// Parallel units (machines, crews), at least 1.
    capacity: i64,
}

impl Calendar {
    /// No `hours` means [`default_blocks`]. A capacity below 1 counts as 1.
    pub fn new(
        hours: Vec<HoursBlock>,
        closures: Vec<(NaiveDate, NaiveDate)>,
        capacity: i32,
    ) -> Self {
        Calendar {
            hours: if hours.is_empty() {
                default_blocks()
            } else {
                hours
            },
            closures,
            capacity: i64::from(capacity.max(1)),
        }
    }

    /// Whether a closure covers the day.
    pub fn is_closed(&self, day: NaiveDate) -> bool {
        self.closures
            .iter()
            .any(|(from, to)| *from <= day && day <= *to)
    }

    /// Working minutes of **one unit** on the day: the blocks of its weekday, 0 when closed.
    pub fn minutes_on(&self, day: NaiveDate) -> i64 {
        if self.is_closed(day) {
            return 0;
        }
        let weekday = day.weekday().number_from_monday() as i16;
        self.hours
            .iter()
            .filter(|b| b.weekday == weekday)
            .map(|b| (b.end - b.start).num_minutes().max(0))
            .sum()
    }

    /// Minutes the work centre offers on the day: one unit's minutes times the capacity.
    pub fn capacity_minutes_on(&self, day: NaiveDate) -> i64 {
        self.minutes_on(day) * self.capacity
    }
}

/// An operation to place: how long it takes and on which calendar (an index into the slice
/// handed to [`schedule_forward`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpSpec {
    pub minutes: i64,
    pub calendar: usize,
}

/// The first and the last day an operation works.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Placement {
    pub start: NaiveDate,
    pub end: NaiveDate,
}

/// An operation found no working time within [`MAX_DAYS`] (a work centre that is closed for
/// good, or an absurd duration). `op` is its index in the list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoWorkingTime {
    pub op: usize,
}

/// Places the operations one after the other from `start`. An operation with no minutes sits on
/// the day the previous one ended.
pub fn schedule_forward(
    ops: &[OpSpec],
    calendars: &[Calendar],
    start: NaiveDate,
) -> Result<Vec<Placement>, NoWorkingTime> {
    let mut out = Vec::with_capacity(ops.len());
    // The day work continues on, and the minutes of it that are already taken.
    let mut cursor = start;
    let mut used = 0_i64;
    for (i, op) in ops.iter().enumerate() {
        if op.minutes <= 0 {
            out.push(Placement {
                start: cursor,
                end: cursor,
            });
            continue;
        }
        let cal = &calendars[op.calendar];
        let mut remaining = op.minutes;
        let mut day = cursor;
        let mut taken = used;
        let mut first_day = None;
        let mut walked = 0_i64;
        loop {
            let available = cal.minutes_on(day) - taken;
            if available > 0 {
                first_day.get_or_insert(day);
                let part = remaining.min(available);
                remaining -= part;
                taken += part;
                if remaining == 0 {
                    break;
                }
            }
            walked += 1;
            if walked > MAX_DAYS {
                return Err(NoWorkingTime { op: i });
            }
            day = day.succ_opt().ok_or(NoWorkingTime { op: i })?;
            taken = 0;
        }
        out.push(Placement {
            start: first_day.expect("an operation with minutes works at least one day"),
            end: day,
        });
        cursor = day;
        used = taken;
    }
    Ok(out)
}

/// Spreads `minutes` over the working days of `[start, end]` in proportion to each day's
/// available minutes, so the parts add up to exactly `minutes` (largest remainder, earlier day
/// first on ties). A range with no working day puts everything on `start`.
pub fn spread_load(
    minutes: i64,
    start: NaiveDate,
    end: NaiveDate,
    cal: &Calendar,
) -> Vec<(NaiveDate, i64)> {
    if minutes <= 0 {
        return Vec::new();
    }
    let end = end.max(start);
    let mut days: Vec<(NaiveDate, i64)> = Vec::new();
    let mut day = start;
    for _ in 0..=MAX_SPREAD_DAYS {
        if day > end {
            break;
        }
        let w = cal.minutes_on(day);
        if w > 0 {
            days.push((day, w));
        }
        match day.succ_opt() {
            Some(next) => day = next,
            None => break,
        }
    }
    let total: i64 = days.iter().map(|(_, w)| w).sum();
    if total == 0 {
        return vec![(start, minutes)];
    }
    let mut parts: Vec<(NaiveDate, i64, i64)> = days
        .iter()
        .map(|(d, w)| (*d, minutes * w / total, minutes * w % total))
        .collect();
    let mut left = minutes - parts.iter().map(|(_, p, _)| p).sum::<i64>();
    let mut order: Vec<usize> = (0..parts.len()).collect();
    // Biggest fractional remainder first; the earlier day wins a tie.
    order.sort_by(|a, b| parts[*b].2.cmp(&parts[*a].2).then(a.cmp(b)));
    for i in order {
        if left == 0 {
            break;
        }
        parts[i].1 += 1;
        left -= 1;
    }
    parts
        .into_iter()
        .filter(|(_, p, _)| *p > 0)
        .map(|(d, p, _)| (d, p))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    fn t(h: u32, m: u32) -> NaiveTime {
        NaiveTime::from_hms_opt(h, m, 0).unwrap()
    }

    /// Monday 2027-02-01.
    const MON: (i32, u32, u32) = (2027, 2, 1);

    fn mon() -> NaiveDate {
        d(MON.0, MON.1, MON.2)
    }

    fn std_cal() -> Calendar {
        Calendar::new(vec![], vec![], 1)
    }

    fn op(minutes: i64) -> OpSpec {
        OpSpec {
            minutes,
            calendar: 0,
        }
    }

    #[test]
    fn the_default_week_is_eight_hours_monday_to_friday() {
        let cal = std_cal();
        assert_eq!(cal.minutes_on(mon()), 480);
        assert_eq!(cal.minutes_on(d(2027, 2, 5)), 480, "friday");
        assert_eq!(cal.minutes_on(d(2027, 2, 6)), 0, "saturday");
        assert_eq!(cal.minutes_on(d(2027, 2, 7)), 0, "sunday");
    }

    #[test]
    fn capacity_widens_the_day_but_not_the_unit() {
        let cal = Calendar::new(vec![], vec![], 3);
        assert_eq!(cal.minutes_on(mon()), 480);
        assert_eq!(cal.capacity_minutes_on(mon()), 1440);
        assert_eq!(
            Calendar::new(vec![], vec![], 0).capacity_minutes_on(mon()),
            480
        );
    }

    #[test]
    fn own_hours_replace_the_default_and_blocks_add_up() {
        let cal = Calendar::new(
            vec![
                HoursBlock {
                    weekday: 1,
                    start: t(6, 0),
                    end: t(10, 30),
                },
                HoursBlock {
                    weekday: 1,
                    start: t(11, 0),
                    end: t(12, 0),
                },
            ],
            vec![],
            1,
        );
        assert_eq!(cal.minutes_on(mon()), 330);
        assert_eq!(cal.minutes_on(d(2027, 2, 2)), 0, "tuesday has no block");
    }

    #[test]
    fn a_closure_is_inclusive_at_both_ends() {
        let cal = Calendar::new(vec![], vec![(d(2027, 2, 2), d(2027, 2, 3))], 1);
        assert_eq!(cal.minutes_on(d(2027, 2, 1)), 480);
        assert_eq!(cal.minutes_on(d(2027, 2, 2)), 0);
        assert_eq!(cal.minutes_on(d(2027, 2, 3)), 0);
        assert_eq!(cal.minutes_on(d(2027, 2, 4)), 480);
    }

    #[test]
    fn a_short_operation_stays_on_one_day() {
        let p = schedule_forward(&[op(120)], &[std_cal()], mon()).unwrap();
        assert_eq!(
            p,
            vec![Placement {
                start: mon(),
                end: mon()
            }]
        );
    }

    #[test]
    fn a_long_operation_takes_the_working_days_it_needs() {
        // 1000 minutes = 480 + 480 + 40: Monday, Tuesday, Wednesday.
        let p = schedule_forward(&[op(1000)], &[std_cal()], mon()).unwrap();
        assert_eq!(p[0].start, mon());
        assert_eq!(p[0].end, d(2027, 2, 3));
    }

    #[test]
    fn weekends_are_skipped() {
        // Starting on a Saturday, work begins on Monday; 600 minutes ends on Tuesday.
        let sat = d(2027, 2, 6);
        let p = schedule_forward(&[op(600)], &[std_cal()], sat).unwrap();
        assert_eq!(p[0].start, d(2027, 2, 8));
        assert_eq!(p[0].end, d(2027, 2, 9));
        // Friday 480 + Monday: crosses the weekend.
        let fri = d(2027, 2, 5);
        let p = schedule_forward(&[op(500)], &[std_cal()], fri).unwrap();
        assert_eq!((p[0].start, p[0].end), (fri, d(2027, 2, 8)));
    }

    #[test]
    fn closures_push_the_work_out() {
        let cal = Calendar::new(vec![], vec![(d(2027, 2, 1), d(2027, 2, 3))], 1);
        let p = schedule_forward(&[op(60)], &[cal], mon()).unwrap();
        assert_eq!((p[0].start, p[0].end), (d(2027, 2, 4), d(2027, 2, 4)));
    }

    #[test]
    fn operations_chain_on_the_same_day_while_time_is_left() {
        // 100 + 100 minutes share Monday; 300 more uses the 280 left on Monday and ends Tuesday.
        let ops = [op(100), op(100), op(300)];
        let p = schedule_forward(&ops, &[std_cal()], mon()).unwrap();
        assert_eq!((p[0].start, p[0].end), (mon(), mon()));
        assert_eq!((p[1].start, p[1].end), (mon(), mon()));
        assert_eq!((p[2].start, p[2].end), (mon(), d(2027, 2, 2)));
    }

    #[test]
    fn a_full_day_hands_over_to_the_next_working_day() {
        let ops = [op(480), op(60)];
        let p = schedule_forward(&ops, &[std_cal()], mon()).unwrap();
        assert_eq!((p[0].start, p[0].end), (mon(), mon()));
        assert_eq!((p[1].start, p[1].end), (d(2027, 2, 2), d(2027, 2, 2)));
    }

    #[test]
    fn each_operation_uses_the_calendar_of_its_own_work_centre() {
        // A Monday-only centre followed by the default one.
        let monday_only = Calendar::new(
            vec![HoursBlock {
                weekday: 1,
                start: t(8, 0),
                end: t(12, 0),
            }],
            vec![],
            1,
        );
        let ops = [
            OpSpec {
                minutes: 480,
                calendar: 0,
            },
            OpSpec {
                minutes: 60,
                calendar: 1,
            },
        ];
        let p = schedule_forward(&ops, &[monday_only, std_cal()], mon()).unwrap();
        // 240 on Monday, 240 on the next Monday.
        assert_eq!((p[0].start, p[0].end), (mon(), d(2027, 2, 8)));
        // The next operation begins on that Monday: 240 are used of the 480 the default day offers.
        assert_eq!((p[1].start, p[1].end), (d(2027, 2, 8), d(2027, 2, 8)));
    }

    #[test]
    fn a_zero_minute_operation_sits_on_the_cursor_day() {
        let ops = [op(0), op(480), op(0), op(60)];
        let p = schedule_forward(&ops, &[std_cal()], mon()).unwrap();
        assert_eq!((p[0].start, p[0].end), (mon(), mon()));
        assert_eq!((p[1].start, p[1].end), (mon(), mon()));
        assert_eq!((p[2].start, p[2].end), (mon(), mon()));
        assert_eq!((p[3].start, p[3].end), (d(2027, 2, 2), d(2027, 2, 2)));
    }

    #[test]
    fn nothing_to_schedule_is_fine() {
        assert_eq!(schedule_forward(&[], &[], mon()).unwrap(), vec![]);
    }

    #[test]
    fn a_work_centre_that_never_works_is_an_error() {
        let closed = Calendar::new(vec![], vec![(d(2027, 1, 1), d(2035, 12, 31))], 1);
        let err = schedule_forward(&[op(10), op(10)], &[closed], mon()).unwrap_err();
        assert_eq!(err, NoWorkingTime { op: 0 });
    }

    #[test]
    fn an_absurd_duration_is_an_error_not_a_hang() {
        let err = schedule_forward(&[op(i64::from(i32::MAX))], &[std_cal()], mon()).unwrap_err();
        assert_eq!(err, NoWorkingTime { op: 0 });
    }

    #[test]
    fn spreading_follows_the_working_days_and_adds_up() {
        let cal = std_cal();
        // Monday to Sunday: five working days, 1000 minutes: 200 each.
        let parts = spread_load(1000, mon(), d(2027, 2, 7), &cal);
        assert_eq!(parts.len(), 5);
        assert!(parts.iter().all(|(_, m)| *m == 200));
        // An odd amount still adds up exactly; the earlier days take the extra minutes.
        let parts = spread_load(1001, mon(), d(2027, 2, 7), &cal);
        assert_eq!(parts.iter().map(|(_, m)| m).sum::<i64>(), 1001);
        assert_eq!(parts[0], (mon(), 201));
        assert_eq!(parts[4].1, 200);
    }

    #[test]
    fn spreading_weighs_days_by_their_available_minutes() {
        // Monday 480, Tuesday 240.
        let cal = Calendar::new(
            vec![
                HoursBlock {
                    weekday: 1,
                    start: t(8, 0),
                    end: t(16, 0),
                },
                HoursBlock {
                    weekday: 2,
                    start: t(8, 0),
                    end: t(12, 0),
                },
            ],
            vec![],
            1,
        );
        let parts = spread_load(720, mon(), d(2027, 2, 2), &cal);
        assert_eq!(parts, vec![(mon(), 480), (d(2027, 2, 2), 240)]);
    }

    #[test]
    fn spreading_skips_closed_days_and_handles_edges() {
        let cal = Calendar::new(vec![], vec![(d(2027, 2, 2), d(2027, 2, 2))], 1);
        let parts = spread_load(960, mon(), d(2027, 2, 3), &cal);
        assert_eq!(parts, vec![(mon(), 480), (d(2027, 2, 3), 480)]);
        // No working day in the range: everything lands on the start.
        let sat = d(2027, 2, 6);
        assert_eq!(
            spread_load(90, sat, d(2027, 2, 7), &std_cal()),
            vec![(sat, 90)]
        );
        // An end before the start counts as the start day.
        assert_eq!(
            spread_load(30, mon(), d(2027, 1, 1), &std_cal()),
            vec![(mon(), 30)]
        );
        assert!(spread_load(0, mon(), mon(), &std_cal()).is_empty());
    }
}
