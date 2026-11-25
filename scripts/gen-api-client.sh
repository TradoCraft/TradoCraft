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
        ok_resp = responses.get("200") or responses.get("201") or {}
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
    pending_rename = None
    for line in body.splitlines():
        s = line.strip()
        rm = re.match(r'#\[serde\(rename\s*=\s*"([^"]+)"\)\]', s)
        if rm:
            pending_rename = rm.group(1)
            continue
        fm = re.match(r"pub\s+([a-zA-Z0-9_]+)\s*:", s)
        if fm:
            name = pending_rename or fm.group(1)
            fields[name] = fm.group(1)
            pending_rename = None
        elif not s.startswith("#[") and not s.startswith("//") and s:
            pending_rename = None
    return set(fields.keys())

def check_schema_fields(rs_path, struct_name, schema_name):
    assert schema_name in schemas, f"Missing schema in api/openapi.json: {schema_name}"
    schema_props = set(schemas[schema_name].get("properties", {}).keys())
    rust_fields = rust_struct_fields(rs_path, struct_name)
    extra = rust_fields - schema_props
    missing = schema_props - rust_fields
    assert not extra, f"{struct_name} has fields not in {schema_name}: {sorted(extra)}"
    assert not missing, f"{struct_name} is missing fields from {schema_name}: {sorted(missing)}"

def check_symbol(rs_path, pattern, label):
    text = pathlib.Path(rs_path).read_text()
    assert re.search(pattern, text, re.M), f"Missing {label} in {rs_path}"

endpoints = [
    ("/api/v1/auth/providers", "get", None, None, None),
    ("/api/v1/meta/environment", "get", None, None, "EnvironmentInfo"),
    ("/api/v1/me", "get", None, None, "Me"),
    ("/api/v1/me/preferences", "get", None, None, "UserPreferences"),
    ("/api/v1/me/preferences", "put", None, "UserPreferences", "UserPreferences"),
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
]

for path, method, query_params, req_schema, resp_schema in endpoints:
    check_path(path, method, query_params, req_schema, resp_schema)

checks = [
    ("crates/api-client/src/error.rs", "ErrorBody", "ErrorBody"),
    ("crates/api-client/src/auth.rs", "PublicProvider", "PublicProvider"),
    ("crates/api-client/src/auth.rs", "EnvironmentInfo", "EnvironmentInfo"),
    ("crates/api-client/src/auth.rs", "Company", "Company"),
    ("crates/api-client/src/auth.rs", "Membership", "Membership"),
    ("crates/api-client/src/auth.rs", "MeModule", "MeModule"),
    ("crates/api-client/src/auth.rs", "Me", "Me"),
    ("crates/api-client/src/auth.rs", "ShortcutBinding", "ShortcutBinding"),
    ("crates/api-client/src/auth.rs", "UserPreferences", "UserPreferences"),
    ("crates/api-client/src/products.rs", "Product", "Product"),
    ("crates/api-client/src/products.rs", "ProductPage", "ProductPage"),
    ("crates/api-client/src/products.rs", "ProductInput", "ProductInput"),
    ("crates/api-client/src/customers.rs", "Customer", "Customer"),
    ("crates/api-client/src/customers.rs", "CustomerPage", "CustomerPage"),
    ("crates/api-client/src/customers.rs", "CustomerInput", "CustomerInput"),
]

for rs_path, struct_name, schema_name in checks:
    check_schema_fields(rs_path, struct_name, schema_name)

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
]

for rs_path, pattern, label in symbols:
    check_symbol(rs_path, pattern, label)

print(f"OK: {len(checks)} DTO structs and {len(endpoints)} endpoints match api/openapi.json")
PY
