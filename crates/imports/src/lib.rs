//! Data import (ADR 0064): the registry of importable entities, the admin screen's endpoints and
//! the job runner that the API (inline) and the worker (queued jobs) share.

pub mod mapping;
mod registry;
mod routes;
pub mod run;

pub use mapping::ColumnPair;
pub use registry::{entities, entity};
pub use routes::router;
pub use run::{
    cap_errors, claim_next, fail_job, fits_one_request, run_claimed, run_job, ClaimedJob,
    StoredError, MAX_STORED_ERRORS,
};
