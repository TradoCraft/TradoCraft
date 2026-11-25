#!/usr/bin/env bash
# Verifies (and in --check mode fails on drift of) crates/api-client against api/openapi.json.
# Note: crates/api-client currently uses hand-written DTOs verified against api/openapi.json
# rather than progenitor (see crates/api-client/README.md for the OpenAPI 3.1 / offline rationale).
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" != "" && "${1:-}" != "--check" ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

python3 - <<'PY'
import json
import pathlib
import re

spec = json.loads(pathlib.Path("api/openapi.json").read_text())
schemas = spec["components"]["schemas"]
paths = spec["paths"]

def schema_ref_name(node):
    if not isinstance(node, dict):
        return None
    ref = node.get("$ref")
    if ref and ref.startswith("#/components/schemas/"):
        return ref.split("/")[-1]
    if node.get("type") == "array" and isinstance(node.get("items"), dict):
        inner = schema_ref_name(node["items"])
        if inner:
            return f"[{inner}]"
    return None

def check_path(
    path,
    method,
    expected_query_params=None,
    expected_request_schema=None,
    expected_response_schema=None,
):
    assert path in paths, f"Missing path in api/openapi.json: {path}"
    op = paths[path].get(method)
    assert op is not None, f"Missing method {method.upper()} on {path}"
    if expected_query_params is not None:
        actual = {
            p["name"]
            for p in op.get("parameters", [])
            if p.get("in") == "query"
        }
        missing = set(expected_query_params) - actual
        assert not missing, f"{method.upper()} {path} missing query params in OpenAPI: {sorted(missing)}"
    if expected_request_schema is not None:
        req_schema = (
            op.get("requestBody", {})
            .get("content", {})
            .get("application/json", {})
            .get("schema", {})
        )
        actual_req = schema_ref_name(req_schema)
        assert actual_req == expected_request_schema, (
            f"{method.upper()} {path} request schema mismatch: expected {expected_request_schema}, got {actual_req}"
        )
    if expected_response_schema is not None:
        responses = op.get("responses", {})
        ok_resp = responses.get("200") or responses.get("201") or responses.get("202") or {}
        if expected_response_schema == "":
            assert responses.get("202") is not None or responses.get("204") is not None, (
                f"{method.upper()} {path} expected empty 202/204 response, got {sorted(responses.keys())}"
            )
        else:
            resp_schema = (
                ok_resp.get("content", {})
                .get("application/json", {})
                .get("schema", {})
            )
            actual_resp = schema_ref_name(resp_schema)
            assert actual_resp == expected_response_schema, (
                f"{method.upper()} {path} response schema mismatch: expected {expected_response_schema}, got {actual_resp}"
            )

def rust_struct_fields(rs_path, struct_name):
    text = pathlib.Path(rs_path).read_text()
    m = re.search(rf"pub struct {struct_name}\s*\{{(.*?)\n\}}", text, re.S)
    assert m, f"Struct {struct_name} not found in {rs_path}"
    body = m.group(1)
    fields = {}
    attrs = []
    in_attr = False
    attr_buf = []
    field_buf = []
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        if in_attr:
            attr_buf.append(s)
            if "]" in s:
                attrs.append(" ".join(attr_buf))
                attr_buf = []
                in_attr = False
            continue
        if s.startswith("#["):
            if "]" in s:
                attrs.append(s)
            else:
                in_attr = True
                attr_buf = [s]
            continue
        field_buf.append(s)
        joined = " ".join(field_buf)
        if joined.endswith(","):
            fm = re.match(r"pub\s+([a-zA-Z0-9_]+)\s*:\s*(.+),$", joined)
            assert fm, f"Could not parse field in {struct_name} ({rs_path}): {joined}"
            rust_name = fm.group(1)
            rust_type = re.sub(r"\s+", "", fm.group(2))
            attr_text = " ".join(attrs)
            rm = re.search(r'rename\s*=\s*"([^"]+)"', attr_text)
            json_name = rm.group(1) if rm else rust_name
            has_default = bool(re.search(r"\bdefault\b", attr_text))
            fields[json_name] = (rust_type, has_default)
            attrs = []
            field_buf = []
    return fields

def unwrap_option(rust_type):
    is_opt = False
    cur = rust_type
    while cur.startswith("Option<") and cur.endswith(">"):
        is_opt = True
        cur = cur[7:-1]
    return is_opt, cur

def unwrap_openapi_nullable(node):
    if "oneOf" in node:
        non_null = [x for x in node["oneOf"] if x != {"type": "null"}]
        is_null = len(non_null) < len(node["oneOf"])
        if len(non_null) == 1:
            return is_null, non_null[0]
    t = node.get("type")
    if isinstance(t, list):
        is_null = "null" in t
        non_null = [x for x in t if x != "null"]
        copy = dict(node)
        copy["type"] = non_null[0] if len(non_null) == 1 else non_null
        return is_null, copy
    return False, node

def check_type_compat(rust_type, oa_node, rust_to_schema):
    _, inner = unwrap_option(rust_type)
    if "$ref" in oa_node:
        ref = oa_node["$ref"].split("/")[-1]
        if rust_to_schema.get(inner, inner) == ref:
            return True
        ref_schema = schemas.get(ref, {})
        if inner == "String" and ref_schema.get("type") == "string":
            return True
        return False
    t = oa_node.get("type")
    fmt = oa_node.get("format")
    if t == "string":
        if fmt == "uuid":
            return inner in ("Uuid", "String")
        if fmt == "date":
            return inner == "NaiveDate"
        if fmt == "date-time":
            return inner == "DateTime<Utc>"
        if inner in ("String", "Decimal"):
            return True
        return schemas.get(rust_to_schema.get(inner, ""), {}).get("type") == "string"
    if t == "boolean":
        return inner == "bool"
    if t == "integer":
        if fmt == "int32":
            return inner in ("i32", "i64", "u32")
        if fmt == "int64":
            return inner in ("i64", "u64")
        return inner in ("i32", "i64", "u32", "u64", "isize", "usize")
    if t == "number":
        return inner in ("f32", "f64", "Decimal")
    if t == "array":
        if not (inner.startswith("Vec<") and inner.endswith(">")):
            return False
        elem = inner[4:-1]
        return check_type_compat(elem, oa_node.get("items", {}), rust_to_schema)
    if t == "object":
        return (
            inner.startswith("BTreeMap<")
            or inner.startswith("HashMap<")
            or inner == "serde_json::Value"
        )
    return True

def check_schema_fields(rs_path, struct_name, schema_name, rust_to_schema):
    assert schema_name in schemas, f"Missing schema in api/openapi.json: {schema_name}"
    schema_obj = schemas[schema_name]
    props = schema_obj.get("properties", {})
    schema_props = set(props.keys())
    required_props = set(schema_obj.get("required", []))
    fields = rust_struct_fields(rs_path, struct_name)
    rust_fields = set(fields.keys())
    extra = rust_fields - schema_props
    missing = schema_props - rust_fields
    assert not extra, f"{struct_name} has fields not in {schema_name}: {sorted(extra)}"
    assert not missing, f"{struct_name} is missing fields from {schema_name}: {sorted(missing)}"

    for prop_name, oa_node in props.items():
        rust_type, has_default = fields[prop_name]
        is_opt, _ = unwrap_option(rust_type)
        oa_nullable, oa_base = unwrap_openapi_nullable(oa_node)
        is_req = prop_name in required_props
        if not is_req:
            assert is_opt or has_default, (
                f"{struct_name}.{prop_name} is optional in {schema_name} so Rust type "
                f"'{rust_type}' must be Option<...> or use #[serde(default)]"
            )
        if oa_nullable:
            assert is_opt, (
                f"{struct_name}.{prop_name} is nullable in {schema_name} so Rust type "
                f"'{rust_type}' must be Option<...>"
            )
        if is_opt and is_req and not oa_nullable:
            raise AssertionError(
                f"{struct_name}.{prop_name} is Option<...> in Rust but required and non-nullable in {schema_name}"
            )
        assert check_type_compat(rust_type, oa_base, rust_to_schema), (
            f"{struct_name}.{prop_name} type mismatch: Rust '{rust_type}' vs OpenAPI {oa_node}"
        )

def check_symbol(rs_path, pattern, label):
    text = pathlib.Path(rs_path).read_text()
    assert re.search(pattern, text, re.M), f"Missing {label} in {rs_path}"

endpoints = [
    # Auth / meta
    ("/api/v1/auth/providers", "get", None, None, "[PublicProvider]"),
    ("/api/v1/meta/environment", "get", None, None, "EnvironmentInfo"),
    ("/api/v1/me", "get", None, None, "Me"),
    ("/api/v1/me/preferences", "get", None, None, "UserPreferences"),
    ("/api/v1/me/preferences", "put", None, "UserPreferences", "UserPreferences"),
    # Products
    (
        "/api/v1/products",
        "get",
        ["q", "code", "active", "family_id", "product_type", "sort", "limit", "offset"],
        None,
        "ProductPage",
    ),
    ("/api/v1/products", "post", None, "ProductInput", "Product"),
    ("/api/v1/products/{id}", "get", None, None, "Product"),
    ("/api/v1/products/{id}", "put", None, "ProductInput", "Product"),
    # Customers
    (
        "/api/v1/customers",
        "get",
        ["q", "sort", "active", "country_code", "limit", "offset"],
        None,
        "CustomerPage",
    ),
    ("/api/v1/customers", "post", None, "CustomerInput", "Customer"),
    ("/api/v1/customers/{id}", "get", None, None, "Customer"),
    ("/api/v1/customers/{id}", "put", None, "CustomerInput", "Customer"),
    # Sales (quotations & orders)
    (
        "/api/v1/quotations",
        "get",
        ["q", "status", "customer_id", "opportunity_id", "sort", "limit", "offset"],
        None,
        "QuotationPage",
    ),
    ("/api/v1/quotations", "post", None, "QuotationInput", "Quotation"),
    ("/api/v1/quotations/{id}", "get", None, None, "Quotation"),
    ("/api/v1/quotations/{id}", "put", None, "QuotationInput", "Quotation"),
    ("/api/v1/quotations/{id}/send", "post", ["override_shipping"], None, "Quotation"),
    ("/api/v1/quotations/{id}/accept", "post", None, None, "Quotation"),
    ("/api/v1/quotations/{id}/convert", "post", None, "ConvertInput", "Order"),
    (
        "/api/v1/orders",
        "get",
        ["q", "customer_id", "status", "limit", "offset"],
        None,
        "OrderPage",
    ),
    ("/api/v1/orders/{id}", "get", None, None, "Order"),
    ("/api/v1/orders/{id}/send", "post", None, None, "Order"),
    ("/api/v1/orders/{id}/confirm", "post", None, "ConfirmOrderInput", "Order"),
    # Public KB & Customer Portal
    ("/api/v1/public/kb/{company_id}/categories", "get", ["language"], None, "[ReaderCategory]"),
    (
        "/api/v1/public/kb/{company_id}/entries",
        "get",
        ["q", "category_id", "tag", "language", "limit", "offset"],
        None,
        "[ReaderSummary]",
    ),
    ("/api/v1/public/kb/{company_id}/entries/{id}", "get", ["language"], None, "ReaderEntry"),
    ("/api/v1/portal/login-links", "post", None, "LoginLinkInput", ""),
    ("/api/v1/portal/sessions", "post", None, "SessionInput", "PortalSession"),
    ("/api/v1/portal/me", "get", None, None, "PortalProfile"),
    ("/api/v1/portal/tickets", "get", None, None, "[PortalTicket]"),
    ("/api/v1/portal/tickets/{id}", "get", None, None, "PortalTicketDetail"),
    ("/api/v1/portal/tickets", "post", None, "NewTicket", "PortalTicketDetail"),
    ("/api/v1/portal/tickets/{id}/messages", "post", None, "MessageInput", "PortalTicketDetail"),
    ("/api/v1/portal/orders", "get", None, None, "[PortalOrder]"),
    ("/api/v1/portal/orders/{id}", "get", None, None, "PortalOrderDetail"),
    ("/api/v1/portal/orders/{id}/confirm", "post", None, "ConfirmPortalOrder", "PortalOrderDetail"),
    # Helpdesk
    (
        "/api/v1/tickets",
        "get",
        [
            "q", "status", "owner", "customer_id", "category", "team_id",
            "mine", "unassigned", "sla", "tag", "unread", "watching",
            "escalated", "limit", "offset",
        ],
        None,
        "TicketPage",
    ),
    ("/api/v1/tickets", "post", None, "NewTicketInput", "TicketDetail"),
    ("/api/v1/tickets/{id}", "get", None, None, "TicketDetail"),
    ("/api/v1/tickets/{id}", "put", None, "TicketInput", "TicketDetail"),
    ("/api/v1/tickets/{id}/replies", "post", None, "ReplyInput", "TicketDetail"),
    ("/api/v1/tickets/{id}/notes", "post", None, "NoteInput", "TicketDetail"),
    ("/api/v1/tickets/{id}/tags", "post", None, "TagInput", "TicketDetail"),
    ("/api/v1/tickets/{id}/time-entries", "get", None, None, "TimeEntries"),
    ("/api/v1/tickets/{id}/time-entries", "post", None, "TimeEntryInput", "TimeEntries"),
    ("/api/v1/tickets/{id}/escalate", "post", None, "EscalateInput", "TicketDetail"),
    ("/api/v1/tickets/{id}/status", "post", None, "TicketStatusInput", "TicketDetail"),
    ("/api/v1/prepared-answers", "get", ["q", "active", "kind", "team_id"], None, "[PreparedAnswer]"),
]

for path, method, query_params, req_schema, resp_schema in endpoints:
    check_path(path, method, query_params, req_schema, resp_schema)

checks = [
    # Error & Auth
    ("crates/api-client/src/error.rs", "ErrorBody", "ErrorBody"),
    ("crates/api-client/src/auth.rs", "PublicProvider", "PublicProvider"),
    ("crates/api-client/src/auth.rs", "EnvironmentInfo", "EnvironmentInfo"),
    ("crates/api-client/src/auth.rs", "Company", "Company"),
    ("crates/api-client/src/auth.rs", "Membership", "Membership"),
    ("crates/api-client/src/auth.rs", "MeModule", "MeModule"),
    ("crates/api-client/src/auth.rs", "Me", "Me"),
    ("crates/api-client/src/auth.rs", "ShortcutBinding", "ShortcutBinding"),
    ("crates/api-client/src/auth.rs", "UserPreferences", "UserPreferences"),
    # Products
    ("crates/api-client/src/products.rs", "Product", "Product"),
    ("crates/api-client/src/products.rs", "ProductPage", "ProductPage"),
    ("crates/api-client/src/products.rs", "ProductInput", "ProductInput"),
    # Customers
    ("crates/api-client/src/customers.rs", "Customer", "Customer"),
    ("crates/api-client/src/customers.rs", "CustomerPage", "CustomerPage"),
    ("crates/api-client/src/customers.rs", "CustomerInput", "CustomerInput"),
    # Sales
    ("crates/api-client/src/sales.rs", "QuotationSummary", "QuotationSummary"),
    ("crates/api-client/src/sales.rs", "QuotationPage", "QuotationPage"),
    ("crates/api-client/src/sales.rs", "VatGroup", "VatGroup"),
    ("crates/api-client/src/sales.rs", "SalesWarning", "SalesWarning"),
    ("crates/api-client/src/sales.rs", "SalesSuggestion", "SalesSuggestion"),
    ("crates/api-client/src/sales.rs", "QuotationLine", "QuotationLine"),
    ("crates/api-client/src/sales.rs", "Quotation", "Quotation"),
    ("crates/api-client/src/sales.rs", "QuotationLineInput", "QuotationLineInput"),
    ("crates/api-client/src/sales.rs", "QuotationInput", "QuotationInput"),
    ("crates/api-client/src/sales.rs", "ConvertInput", "ConvertInput"),
    ("crates/api-client/src/sales.rs", "OrderSummary", "OrderSummary"),
    ("crates/api-client/src/sales.rs", "OrderPage", "OrderPage"),
    ("crates/api-client/src/sales.rs", "OrderRevisionInfo", "OrderRevisionInfo"),
    ("crates/api-client/src/sales.rs", "OrderLine", "OrderLine"),
    ("crates/api-client/src/sales.rs", "Order", "Order"),
    ("crates/api-client/src/sales.rs", "OrderLineEdit", "OrderLineEdit"),
    ("crates/api-client/src/sales.rs", "OrderEditInput", "OrderEditInput"),
    ("crates/api-client/src/sales.rs", "ConfirmOrderInput", "ConfirmOrderInput"),
    # Public KB & Customer Portal
    ("crates/api-client/src/portal.rs", "ReaderCategory", "ReaderCategory"),
    ("crates/api-client/src/portal.rs", "ReaderSummary", "ReaderSummary"),
    ("crates/api-client/src/portal.rs", "ReaderImage", "ReaderImage"),
    ("crates/api-client/src/portal.rs", "ReaderLink", "ReaderLink"),
    ("crates/api-client/src/portal.rs", "ReaderEntry", "ReaderEntry"),
    ("crates/api-client/src/portal.rs", "LoginLinkInput", "LoginLinkInput"),
    ("crates/api-client/src/portal.rs", "SessionInput", "SessionInput"),
    ("crates/api-client/src/portal.rs", "PortalProfile", "PortalProfile"),
    ("crates/api-client/src/portal.rs", "PortalSession", "PortalSession"),
    ("crates/api-client/src/portal.rs", "PortalTicket", "PortalTicket"),
    ("crates/api-client/src/portal.rs", "FileInfo", "FileInfo"),
    ("crates/api-client/src/portal.rs", "PortalMessage", "PortalMessage"),
    ("crates/api-client/src/portal.rs", "PortalTicketDetail", "PortalTicketDetail"),
    ("crates/api-client/src/portal.rs", "NewTicket", "NewTicket"),
    ("crates/api-client/src/portal.rs", "MessageInput", "MessageInput"),
    ("crates/api-client/src/portal.rs", "PortalOrder", "PortalOrder"),
    ("crates/api-client/src/portal.rs", "PortalOrderLine", "PortalOrderLine"),
    ("crates/api-client/src/portal.rs", "PortalOrderDetail", "PortalOrderDetail"),
    ("crates/api-client/src/portal.rs", "ConfirmPortalOrder", "ConfirmPortalOrder"),
    # Helpdesk
    ("crates/api-client/src/helpdesk.rs", "TargetState", "TargetState"),
    ("crates/api-client/src/helpdesk.rs", "TicketSla", "TicketSla"),
    ("crates/api-client/src/helpdesk.rs", "TicketSummary", "Ticket"),
    ("crates/api-client/src/helpdesk.rs", "TicketPage", "TicketPage"),
    ("crates/api-client/src/helpdesk.rs", "TicketArticle", "Article"),
    ("crates/api-client/src/helpdesk.rs", "TicketWatcher", "Watcher"),
    ("crates/api-client/src/helpdesk.rs", "TicketReader", "Reader"),
    ("crates/api-client/src/helpdesk.rs", "TicketDetail", "TicketDetail"),
    ("crates/api-client/src/helpdesk.rs", "CreateTicketInput", "NewTicketInput"),
    ("crates/api-client/src/helpdesk.rs", "UpdateTicketInput", "TicketInput"),
    ("crates/api-client/src/helpdesk.rs", "LibraryPdf", "LibraryPdf"),
    ("crates/api-client/src/helpdesk.rs", "ReplyInput", "ReplyInput"),
    ("crates/api-client/src/helpdesk.rs", "NoteInput", "NoteInput"),
    ("crates/api-client/src/helpdesk.rs", "TagInput", "TagInput"),
    ("crates/api-client/src/helpdesk.rs", "TicketTimeEntry", "TimeEntry"),
    ("crates/api-client/src/helpdesk.rs", "TicketTimeEntries", "TimeEntries"),
    ("crates/api-client/src/helpdesk.rs", "TimeEntryInput", "TimeEntryInput"),
    ("crates/api-client/src/helpdesk.rs", "EscalateInput", "EscalateInput"),
    ("crates/api-client/src/helpdesk.rs", "TicketStatusInput", "TicketStatusInput"),
    ("crates/api-client/src/helpdesk.rs", "AnswerText", "AnswerText"),
    ("crates/api-client/src/helpdesk.rs", "PreparedAnswer", "PreparedAnswer"),
]

rust_to_schema = {struct_name: schema_name for _, struct_name, schema_name in checks}
rust_to_schema["EnvKind"] = "EnvKind"
rust_to_schema["QuotationStatus"] = "QuotationStatus"
rust_to_schema["PercentBase"] = "PercentBase"

for rs_path, struct_name, schema_name in checks:
    check_schema_fields(rs_path, struct_name, schema_name, rust_to_schema)

symbols = [
    ("crates/api-client/src/products.rs", r"pub type CreateProductRequest = ProductInput;", "CreateProductRequest"),
    ("crates/api-client/src/products.rs", r"pub type UpdateProductRequest = ProductInput;", "UpdateProductRequest"),
    ("crates/api-client/src/products.rs", r"pub async fn get_product\(", "Client::get_product"),
    ("crates/api-client/src/products.rs", r"pub async fn create_product\(", "Client::create_product"),
    ("crates/api-client/src/products.rs", r"pub async fn update_product\(", "Client::update_product"),
    ("crates/api-client/src/customers.rs", r"pub type CreateCustomerRequest = CustomerInput;", "CreateCustomerRequest"),
    ("crates/api-client/src/customers.rs", r"pub type UpdateCustomerRequest = CustomerInput;", "UpdateCustomerRequest"),
    ("crates/api-client/src/customers.rs", r"pub async fn get_customer\(", "Client::get_customer"),
    ("crates/api-client/src/customers.rs", r"pub async fn create_customer\(", "Client::create_customer"),
    ("crates/api-client/src/customers.rs", r"pub async fn update_customer\(", "Client::update_customer"),
    ("crates/api-client/src/sales.rs", r"pub type CreateQuotationRequest = QuotationInput;", "CreateQuotationRequest"),
    ("crates/api-client/src/sales.rs", r"pub type UpdateQuotationRequest = QuotationInput;", "UpdateQuotationRequest"),
    ("crates/api-client/src/sales.rs", r"pub type ConvertQuotationRequest = ConvertInput;", "ConvertQuotationRequest"),
    ("crates/api-client/src/sales.rs", r"pub type ConfirmOrderRequest = ConfirmOrderInput;", "ConfirmOrderRequest"),
    ("crates/api-client/src/sales.rs", r"pub async fn list_quotations\(", "Client::list_quotations"),
    ("crates/api-client/src/sales.rs", r"pub async fn list_orders\(", "Client::list_orders"),
    ("crates/api-client/src/portal.rs", r"pub async fn request_portal_login_link\(", "Client::request_portal_login_link"),
    ("crates/api-client/src/portal.rs", r"pub async fn list_portal_tickets\(", "Client::list_portal_tickets"),
    ("crates/api-client/src/portal.rs", r"pub async fn list_portal_orders\(", "Client::list_portal_orders"),
    ("crates/api-client/src/helpdesk.rs", r"pub async fn list_tickets\(", "Client::list_tickets"),
    ("crates/api-client/src/helpdesk.rs", r"pub async fn list_prepared_answers\(", "Client::list_prepared_answers"),
]

for rs_path, pattern, label in symbols:
    check_symbol(rs_path, pattern, label)

print(f"OK: {len(checks)} DTO structs and {len(endpoints)} endpoints match api/openapi.json")
PY
