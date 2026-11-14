//! The size limits of an import file (ADR 0064 section 4).

use crate::csv_io::{MAX_BODY_BYTES, MAX_COLUMNS, MAX_ROWS};

const MIB: u64 = 1024 * 1024;

/// How large an import file may be, and how much it may unpack to. Two presets exist: one request
/// ([`Limits::request`]) and a background job ([`Limits::job`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// Size of the uploaded file in bytes.
    pub file_bytes: usize,
    /// Data rows (the header is not counted).
    pub rows: usize,
    /// Cells in one row, the header included.
    pub cells_per_row: usize,
    /// Cells in the whole sheet.
    pub total_cells: usize,
    /// Sum of the uncompressed sizes an archive declares (XLSX and ODS only).
    pub unpacked_bytes: u64,
    /// Entries in the archive (XLSX and ODS only).
    pub archive_entries: usize,
}

impl Limits {
    /// The limits of one request: the entity endpoints and the inline run of the admin screen.
    pub const fn request() -> Self {
        Limits {
            file_bytes: MAX_BODY_BYTES,
            rows: MAX_ROWS,
            cells_per_row: MAX_COLUMNS,
            total_cells: 2_000_000,
            unpacked_bytes: 64 * MIB,
            archive_entries: 1_000,
        }
    }

    /// The limits of a background job.
    pub const fn job() -> Self {
        Limits {
            file_bytes: 50 * 1024 * 1024,
            rows: 200_000,
            cells_per_row: MAX_COLUMNS,
            total_cells: 5_000_000,
            unpacked_bytes: 512 * MIB,
            archive_entries: 1_000,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn presets_match_the_adr_table_and_the_csv_constants() {
        let r = Limits::request();
        assert_eq!(r.file_bytes, 5 * 1024 * 1024);
        assert_eq!(r.rows, 20_000);
        assert_eq!(r.cells_per_row, 100);
        assert_eq!(r.total_cells, 2_000_000);
        assert_eq!(r.unpacked_bytes, 64 * 1024 * 1024);
        assert_eq!(r.archive_entries, 1_000);
        assert_eq!(r.file_bytes, MAX_BODY_BYTES);
        assert_eq!(r.rows, MAX_ROWS);
        assert_eq!(r.cells_per_row, MAX_COLUMNS);
        let j = Limits::job();
        assert_eq!(j.file_bytes, 50 * 1024 * 1024);
        assert_eq!(j.rows, 200_000);
        assert_eq!(j.cells_per_row, 100);
        assert_eq!(j.total_cells, 5_000_000);
        assert_eq!(j.unpacked_bytes, 512 * 1024 * 1024);
        assert_eq!(j.archive_entries, 1_000);
    }
}
