//! Requests per client address: a token bucket per address, and finding the client's address
//! behind a reverse proxy.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv6Addr};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Above this many tracked addresses, idle ones are dropped.
const PRUNE_ABOVE: usize = 10_000;
/// At most one scan of the map per this long, however many requests arrive: during a flood from
/// many addresses a scan frees little, and it runs while every other request waits.
const PRUNE_EVERY: Duration = Duration::from_secs(10);
/// A bucket that was not touched for this long is full again: forgetting it changes nothing.
const IDLE_AFTER: Duration = Duration::from_secs(60);

/// At most `per_minute` requests a minute per address, with bursts up to that number.
pub struct Limiter {
    per_minute: u32,
    state: Mutex<State>,
}

#[derive(Default)]
struct State {
    buckets: HashMap<IpAddr, Bucket>,
    /// When the map was last scanned for idle buckets.
    pruned: Option<Instant>,
}

impl State {
    fn prune(&mut self, now: Instant) {
        if self.buckets.len() <= PRUNE_ABOVE {
            return;
        }
        let due = self
            .pruned
            .is_none_or(|at| now.saturating_duration_since(at) >= PRUNE_EVERY);
        if due {
            self.buckets
                .retain(|_, b| now.saturating_duration_since(b.seen) < IDLE_AFTER);
            self.pruned = Some(now);
        }
    }
}

struct Bucket {
    tokens: f64,
    seen: Instant,
}

impl Limiter {
    /// `per_minute` 0 switches the limit off.
    pub fn new(per_minute: u32) -> Self {
        Limiter {
            per_minute,
            state: Mutex::new(State::default()),
        }
    }

    /// Counts one request from `ip`. `Err` is how long to wait before the next one is accepted.
    pub fn check(&self, ip: IpAddr, now: Instant) -> Result<(), Duration> {
        if self.per_minute == 0 {
            return Ok(());
        }
        let capacity = f64::from(self.per_minute);
        let per_second = capacity / 60.0;
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        state.prune(now);
        let bucket = state.buckets.entry(rate_key(ip)).or_insert(Bucket {
            tokens: capacity,
            seen: now,
        });
        let elapsed = now.saturating_duration_since(bucket.seen).as_secs_f64();
        bucket.tokens = (bucket.tokens + elapsed * per_second).min(capacity);
        bucket.seen = now;
        if bucket.tokens >= 1.0 {
            bucket.tokens -= 1.0;
            Ok(())
        } else {
            Err(Duration::from_secs_f64((1.0 - bucket.tokens) / per_second))
        }
    }
}

/// What a limit counts per: an IPv4 address, or an IPv6 /64 (one subscriber owns the whole /64
/// and could otherwise use a new address for every request).
fn rate_key(ip: IpAddr) -> IpAddr {
    match ip.to_canonical() {
        IpAddr::V6(v6) => {
            let s = v6.segments();
            IpAddr::V6(Ipv6Addr::new(s[0], s[1], s[2], s[3], 0, 0, 0, 0))
        }
        v4 => v4,
    }
}

/// An address or a network in CIDR notation (`10.0.0.5`, `172.16.0.0/12`, `fd00::/8`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IpNet {
    addr: IpAddr,
    prefix: u8,
}

impl IpNet {
    pub fn parse(text: &str) -> Result<Self, String> {
        let text = text.trim();
        let (addr, prefix) = match text.split_once('/') {
            Some((a, p)) => (a, Some(p)),
            None => (text, None),
        };
        let addr: IpAddr = addr
            .parse()
            .map_err(|_| format!("{text} is not an IP address or network"))?;
        let addr = addr.to_canonical();
        let max = if addr.is_ipv4() { 32 } else { 128 };
        let prefix = match prefix {
            Some(p) => p
                .parse::<u8>()
                .ok()
                .filter(|p| *p <= max)
                .ok_or_else(|| format!("{text} has an invalid prefix length"))?,
            None => max,
        };
        Ok(IpNet { addr, prefix })
    }

    pub fn contains(&self, ip: IpAddr) -> bool {
        match (self.addr, ip.to_canonical()) {
            (IpAddr::V4(net), IpAddr::V4(ip)) => {
                same_prefix(&net.octets(), &ip.octets(), self.prefix)
            }
            (IpAddr::V6(net), IpAddr::V6(ip)) => {
                same_prefix(&net.octets(), &ip.octets(), self.prefix)
            }
            _ => false,
        }
    }
}

fn same_prefix(a: &[u8], b: &[u8], prefix: u8) -> bool {
    let full = usize::from(prefix / 8);
    let rest = prefix % 8;
    if a[..full] != b[..full] {
        return false;
    }
    if rest == 0 {
        return true;
    }
    let mask = 0xffu8 << (8 - rest);
    a[full] & mask == b[full] & mask
}

/// The address a request comes from. `peer` is the other end of the TCP connection. Only when
/// that is one of our own reverse proxies is `X-Forwarded-For` believed, and then the right-most
/// address that is not a proxy of ours: everything left of it was supplied by the client.
pub fn client_ip(peer: IpAddr, forwarded_for: &[&str], trusted: &[IpNet]) -> IpAddr {
    let is_trusted = |ip: IpAddr| trusted.iter().any(|n| n.contains(ip));
    let peer = peer.to_canonical();
    if !is_trusted(peer) {
        return peer;
    }
    for entry in forwarded_for.iter().rev().flat_map(|h| h.rsplit(',')) {
        match entry.trim().parse::<IpAddr>() {
            Ok(ip) if is_trusted(ip.to_canonical()) => continue,
            Ok(ip) => return ip.to_canonical(),
            // An entry we cannot read ends the chain we can vouch for.
            Err(_) => break,
        }
    }
    peer
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    #[test]
    fn a_burst_is_allowed_then_refused_and_refills_with_time() {
        let limiter = Limiter::new(6); // one every ten seconds
        let start = Instant::now();
        for _ in 0..6 {
            assert!(limiter.check(ip("203.0.113.7"), start).is_ok());
        }
        let wait = limiter.check(ip("203.0.113.7"), start).unwrap_err();
        assert!(wait > Duration::from_secs(9) && wait <= Duration::from_secs(10));
        // Another address has its own allowance.
        assert!(limiter.check(ip("203.0.113.8"), start).is_ok());
        // Ten seconds later one more request fits, and only one.
        let later = start + Duration::from_secs(10);
        assert!(limiter.check(ip("203.0.113.7"), later).is_ok());
        assert!(limiter.check(ip("203.0.113.7"), later).is_err());
    }

    #[test]
    fn idle_addresses_are_forgotten_on_an_interval_not_on_every_request() {
        let limiter = Limiter::new(60);
        let tracked = || limiter.state.lock().unwrap().buckets.len();
        let start = Instant::now();
        // More addresses than are kept, all seen at the start.
        for n in 0..=(PRUNE_ABOVE as u32) {
            let addr = IpAddr::V4(std::net::Ipv4Addr::from(0x0b00_0000 + n));
            limiter.check(addr, start).unwrap();
        }
        assert_eq!(tracked(), PRUNE_ABOVE + 1);
        // Over the threshold: this request scans (nothing is idle yet) and starts the clock.
        let scan = start + Duration::from_secs(55);
        limiter.check(ip("203.0.113.7"), scan).unwrap();
        assert_eq!(tracked(), PRUNE_ABOVE + 2);
        // Six seconds on the first addresses are idle, but the map is not scanned again yet.
        limiter
            .check(ip("203.0.113.7"), scan + Duration::from_secs(6))
            .unwrap();
        assert_eq!(tracked(), PRUNE_ABOVE + 2);
        // Once the interval has passed, the 60-second rule is applied again.
        limiter
            .check(ip("203.0.113.8"), scan + PRUNE_EVERY)
            .unwrap();
        assert_eq!(tracked(), 2, "the two addresses seen in the last minute");
    }

    #[test]
    fn zero_switches_the_limit_off() {
        let limiter = Limiter::new(0);
        let now = Instant::now();
        for _ in 0..1000 {
            assert!(limiter.check(ip("203.0.113.7"), now).is_ok());
        }
    }

    #[test]
    fn ipv6_addresses_of_one_subscriber_share_an_allowance() {
        let limiter = Limiter::new(1);
        let now = Instant::now();
        assert!(limiter.check(ip("2001:db8:1:2::1"), now).is_ok());
        assert!(limiter.check(ip("2001:db8:1:2:ffff::9"), now).is_err());
        assert!(limiter.check(ip("2001:db8:1:3::1"), now).is_ok());
        // An IPv4 client seen over a dual-stack socket is still that IPv4 client.
        assert!(limiter.check(ip("::ffff:203.0.113.7"), now).is_ok());
        assert!(limiter.check(ip("203.0.113.7"), now).is_err());
    }

    #[test]
    fn networks_match_by_prefix() {
        let net = IpNet::parse("172.16.0.0/12").unwrap();
        assert!(net.contains(ip("172.31.255.1")));
        assert!(!net.contains(ip("172.32.0.1")));
        assert!(IpNet::parse("10.0.0.5").unwrap().contains(ip("10.0.0.5")));
        assert!(!IpNet::parse("10.0.0.5").unwrap().contains(ip("10.0.0.6")));
        assert!(IpNet::parse("fd00::/8").unwrap().contains(ip("fd12::1")));
        assert!(!IpNet::parse("fd00::/8").unwrap().contains(ip("fe80::1")));
        assert!(IpNet::parse("0.0.0.0/0").unwrap().contains(ip("8.8.8.8")));
        assert!(!IpNet::parse("0.0.0.0/0")
            .unwrap()
            .contains(ip("2001:db8::1")));
        assert!(IpNet::parse("10.0.0.0/33").is_err());
        assert!(IpNet::parse("proxy.internal").is_err());
    }

    #[test]
    fn forwarded_for_is_believed_only_from_our_own_proxy() {
        let trusted = [IpNet::parse("10.0.0.0/8").unwrap()];
        // Directly connected client: the header is the client's own claim and is ignored.
        assert_eq!(
            client_ip(ip("203.0.113.7"), &["198.51.100.1"], &trusted),
            ip("203.0.113.7")
        );
        // Through our proxy: the address the proxy saw.
        assert_eq!(
            client_ip(ip("10.0.0.2"), &["203.0.113.7"], &trusted),
            ip("203.0.113.7")
        );
        // The client prepended a made-up address; the proxy appended the real one.
        assert_eq!(
            client_ip(ip("10.0.0.2"), &["1.2.3.4, 203.0.113.7"], &trusted),
            ip("203.0.113.7")
        );
        // Two proxies of ours in a row, and the header split over two lines.
        assert_eq!(
            client_ip(
                ip("10.0.0.2"),
                &["1.2.3.4", "203.0.113.7, 10.0.0.9"],
                &trusted
            ),
            ip("203.0.113.7")
        );
        // No usable header: the proxy itself.
        assert_eq!(client_ip(ip("10.0.0.2"), &[], &trusted), ip("10.0.0.2"));
        assert_eq!(
            client_ip(ip("10.0.0.2"), &["1.2.3.4, unknown"], &trusted),
            ip("10.0.0.2")
        );
    }
}
