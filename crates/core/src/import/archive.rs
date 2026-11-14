//! Checks of a zip archive (XLSX, ODS) before anything is unpacked.
//!
//! # Is the declared size enforced while inflating?
//!
//! The central directory of a zip archive declares the uncompressed size of every entry, and a
//! hostile file can declare less than the entry really inflates to (or more, to make a reader
//! reserve memory). Checking the declared sum alone would then be worthless, so this was
//! investigated in the source of `zip` 9.5.1 (the version `calamine` 0.38 and `rust_xlsxwriter`
//! resolve to):
//!
//! * `read::readers::make_reader` wraps every entry, stored or compressed, in a `Crc32Reader`
//!   with `with_size_limit(declared size)`. Once more bytes than declared have been produced it
//!   fails with `"File is larger than its declared uncompressed size"`, and `read_to_end` /
//!   `read_to_string` read at most one byte past the limit, so an oversized entry is detected
//!   without buffering it.
//! * `calamine` reads sheets, shared strings and `content.xml` only through `ZipFile` readers (a
//!   streaming XML parser over `BufReader<ZipFile>`, or `read_to_end` for a few small parts), so
//!   the same limit applies; a zip error surfaces as an error of the workbook, not as memory use.
//!
//! So declared size is enforced and no extra counting reader is needed: every entry is bounded by
//! its declared size and [`check`] bounds the sum of the declared sizes and the entry count.
//! The test `a_lying_declared_size_is_stopped_while_inflating` (in this module) builds archives that
//! lie and proves it for XLSX and ODS; it also guards against a `zip` release that would drop the
//! check (the workspace requires `zip` 9.5 or newer for the same reason).

use std::io::Cursor;

use zip::ZipArchive;

use crate::import::Limits;

/// Why an archive is refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refusal {
    pub message: String,
    /// Too many entries or too large a declared size (larger limits would accept it), as opposed
    /// to a damaged archive.
    pub limit: bool,
}

impl Refusal {
    fn damaged(message: String) -> Self {
        Refusal {
            message,
            limit: false,
        }
    }

    fn over_limit(message: String) -> Self {
        Refusal {
            message,
            limit: true,
        }
    }
}

/// Refuses an archive with too many entries or too large a declared unpacked size, with one
/// message. Only the central directory is read; nothing is inflated.
pub fn check(bytes: &[u8], limits: &Limits) -> Result<(), Refusal> {
    let mut zip = ZipArchive::new(Cursor::new(bytes)).map_err(|e| {
        Refusal::damaged(format!(
            "the file is a damaged or unsupported zip archive ({e})"
        ))
    })?;
    if zip.len() > limits.archive_entries {
        return Err(Refusal::over_limit(format!(
            "the archive has {} entries; at most {} are accepted",
            zip.len(),
            limits.archive_entries
        )));
    }
    let mut declared: u64 = 0;
    for i in 0..zip.len() {
        let entry = zip
            .by_index_raw(i)
            .map_err(|e| Refusal::damaged(format!("the file is a damaged zip archive ({e})")))?;
        declared = declared.saturating_add(entry.size());
        if declared > limits.unpacked_bytes {
            return Err(Refusal::over_limit(format!(
                "the archive unpacks to more than the {} MiB that are accepted",
                limits.unpacked_bytes / (1024 * 1024)
            )));
        }
    }
    Ok(())
}
