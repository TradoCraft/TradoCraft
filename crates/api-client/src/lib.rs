//! WASM-safe typed HTTP client and DTOs for the TradoCraft REST API.
//!
//! Designed to compile for both native targets and `wasm32-unknown-unknown`
//! without `sqlx`, `tokio`, or `axum`.

pub mod admin;
pub mod attributes;
pub mod audit;
pub mod auth;
pub mod client;
pub mod customers;
pub mod error;
pub mod helpdesk;
pub mod identity;
pub mod imports;
pub mod kb;
pub mod portal;
pub mod price_zones;
pub mod products;
pub mod sales;
pub mod suppliers;
pub mod todo;
pub mod translations;
pub mod vat;

pub use admin::{
    AdminUser, AdminUserCreate, AdminUserUpdate, CompanyLanguagesInput, CompanyLogoInfo,
    CompanySettingsInput, LanguageInfo, ModuleInfo, ModulesInput, OidcSubjectInput, RoleInfo,
};
pub use attributes::{
    AttributeDefinition, AttributeDefinitionInput, BaselineItemType, DefinitionKind, SelectOption,
};
pub use audit::{AuditEvent, AuditFacets, AuditPage, ListAuditEventsParams};
pub use auth::{
    Auth, Company, EnvKind, EnvironmentInfo, Me, MeModule, Membership, PublicProvider, Session,
    ShortcutBinding, UserPreferences,
};
pub use client::Client;
pub use customers::{
    CreateCustomerRequest, Customer, CustomerInput, CustomerPage, ListCustomersParams,
    UpdateCustomerRequest,
};
pub use error::{ApiError, ErrorBody};
pub use helpdesk::{
    AnswerText, CreateTicketInput, EscalateInput, LibraryPdf, ListPreparedAnswersParams,
    ListTicketsParams, NoteInput, PreparedAnswer, ReplyInput, TagInput, TargetState, TicketArticle,
    TicketDetail, TicketPage, TicketReader, TicketSla, TicketStatusInput, TicketSummary,
    TicketTimeEntries, TicketTimeEntry, TicketWatcher, TimeEntryInput, UpdateTicketInput,
};
pub use identity::{
    BindingResult, IdentityProviderInfo, IdentityProviderInput, IdentityProviderTest,
    IdentityProviderTestResult, TokenTestResult,
};
pub use imports::{
    ColumnKind, ColumnPair, CreateJob, ImportColumn, ImportDescription, ImportFile, ImportJob,
    ImportJobPage, ImportMapping, ImportPreview, ListImportJobsParams, MappingInput, StoredError,
};
pub use portal::{
    ConfirmPortalOrder, FileInfo, KbLanguageParams, ListPublicKbEntriesParams, LoginLinkInput,
    MessageInput, NewTicket, PortalMessage, PortalOrder, PortalOrderDetail, PortalOrderLine,
    PortalProfile, PortalSession, PortalTicket, PortalTicketDetail, ReaderCategory, ReaderEntry,
    ReaderImage, ReaderLink, ReaderSummary, SessionInput,
};
pub use price_zones::{PriceZone, PriceZoneInput};
pub use products::{
    CreateProductRequest, ListProductsParams, Product, ProductInput, ProductPage,
    UpdateProductRequest,
};
pub use sales::{
    ConfirmOrderInput, ConfirmOrderRequest, ConvertInput, ConvertQuotationRequest,
    CreateQuotationRequest, ListOrdersParams, ListQuotationsParams, Order, OrderEditInput,
    OrderLine, OrderLineEdit, OrderPage, OrderRevisionInfo, OrderSummary, PercentBase, Quotation,
    QuotationInput, QuotationLine, QuotationLineInput, QuotationPage, QuotationStatus,
    QuotationSummary, SalesSuggestion, SalesWarning, UpdateQuotationRequest, VatGroup,
};
pub use suppliers::{
    CreateSupplierRequest, ListSuppliersParams, SetSupplierProductInput, Supplier, SupplierInput,
    SupplierProduct, SupplierProductInput, UpdateSupplierInput, UpdateSupplierRequest,
};
pub use todo::{ListTodosParams, TodoCounts, TodoCreate, TodoItem, TodoPatch, TodoScope};
pub use vat::{CountryVatRate, CountryVatRateInput};
