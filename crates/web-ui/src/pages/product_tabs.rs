use leptos::prelude::*;
use serde_json::{json, Value};
use tradocraft_api_client::products::*;
use tradocraft_api_client::{DefinitionKind, Product};
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Lookup, Mutation, Status};
use super::product_engineering::{BomsTab, SerialsTab};
use super::product_media::MediaTab;
use crate::components::files::{begin_file_read, save_file};

#[component]
pub(super) fn ProductDetailTabs(product: Product) -> impl IntoView {
    let id = product.id;
    let product = StoredValue::new(product);
    let tab = RwSignal::new(0);
    let labels = [
        "Overview",
        "BOMs",
        "Serials & Genealogy",
        "Media",
        "Prices",
        "Options",
        "Power Grids",
        "Related",
        "Suitability",
    ];
    view! {
        <div class="tc-inline-tabs" aria-label="Product sections">
            {labels.into_iter().enumerate().map(|(index, label)| view! {
                <button type="button" class="tc-btn" aria-pressed=move || tab.get() == index
                    class:tc-btn-primary=move || tab.get() == index
                    on:click=move |_| tab.set(index)>{label}</button>
            }).collect_view()}
        </div>
        <div class="tc-phase-section">
            {move || match tab.get() {
                1 => view! { <BomsTab id /> }.into_any(),
                2 => view! { <SerialsTab id /> }.into_any(),
                3 => view! { <MediaTab id /> }.into_any(),
                4 => view! { <PricesTab id /> }.into_any(),
                5 => view! { <OptionsTab id /> }.into_any(),
                6 => view! { <PowerTab id /> }.into_any(),
                7 => view! { <RelatedTab id /> }.into_any(),
                8 => view! { <SuitabilityTab id /> }.into_any(),
                _ => view! { <OverviewTab product=product.get_value() /> }.into_any(),
            }}
        </div>
    }
}

#[component]
fn OverviewTab(product: Product) -> impl IntoView {
    let id = product.id;
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let initial = StoredValue::new(product);
    let data = ui::load(revision, move |client| async move {
        client.get_product(id).await
    });
    let details = |p: Product| {
        let values = [
            ("Code", p.code),
            ("Name", p.name),
            ("Type", p.product_type),
            ("Unit", p.unit),
            ("VAT (%)", p.vat_rate.to_string()),
            ("Tracking", p.tracking),
            ("Barcode", p.barcode.unwrap_or_default()),
            ("Family", p.family_code.unwrap_or_default()),
            ("Packaging", p.packaging_category_code.unwrap_or_default()),
            ("Description", p.description),
        ];
        view! {
            <dl class="tc-detail-grid">{values.into_iter().map(|(label, value)| view! {
                <div><dt class="tc-label">{label}</dt><dd>{value}</dd></div>
            }).collect_view()}</dl>
        }
    };
    let categories = ui::load(revision, |client| async move {
        Ok((
            client.list_families().await?,
            client.list_packaging().await?,
        ))
    });
    view! {
        <Status mutation=mutation />
        {move || {
            let p = data.get().and_then(Result::ok).unwrap_or_else(|| initial.get_value());
            details(p)
        }}
        {ui::loaded(categories, move |(families, packaging)| {
            let product = data.get().and_then(Result::ok).unwrap_or_else(|| initial.get_value());
            let fields = vec![
                Field::select("family_id", "Family", families.iter().filter(|f| f.active || product.family_id == Some(f.id)).map(|f| (f.id, f.name.clone()))),
                Field::select("packaging_category_id", "Packaging category", packaging.iter().filter(|p| p.active || product.packaging_category_id == Some(p.id)).map(|p| (p.id, p.name.clone()))),
            ];
            let edit = ui::save(mutation, "Assign family and packaging", fields, json!(product),
                move |client, selected: Value| async move {
                    let latest = client.get_product(id).await?;
                    let mut body = ProductInput::from(&latest);
                    body.family_id = selected["family_id"].as_str().and_then(|id| id.parse().ok());
                    body.packaging_category_id = selected["packaging_category_id"].as_str().and_then(|id| id.parse().ok());
                    client.update_product(id, &body).await
                });
            let family = family_management(mutation, families);
            let packaging = packaging_management(mutation, packaging);
            view! {<div class="tc-phase-actions">{edit}{family}{packaging}</div>}.into_any()
        })}
    }
}

fn category_fields() -> Vec<Field> {
    vec![
        Field::text("code", "Code").required(),
        Field::text("name", "Name").required(),
        Field::new("active", "Active", FieldType::Toggle),
    ]
}

fn family_management(mutation: Mutation, families: Vec<ProductFamily>) -> AnyView {
    let new = ui::save(
        mutation,
        "New family",
        category_fields(),
        json!({"active": true}),
        |client, body| async move { client.create_family(&body).await },
    );
    let rows = families
        .into_iter()
        .map(|family| {
            let id = family.id;
            let edit = ui::save(
                mutation,
                "Edit family",
                category_fields(),
                json!(family),
                move |client, body| async move { client.update_family(id, &body).await },
            );
            vec![
                ui::text(family.code),
                ui::text(family.name),
                ui::text(family.product_count),
                edit,
            ]
        })
        .collect();
    ui::management("Manage families", move || {
        view! {
            {new}{ui::table(&["Code","Name","Products","Actions"], rows, "No families.")}
        }
        .into_any()
    })
}

fn packaging_fields() -> Vec<Field> {
    let mut fields = category_fields();
    fields.extend([
        Field::text("description", "Description"),
        Field::new(
            "requires_shipping_quote",
            "Requires shipping quote",
            FieldType::Toggle,
        ),
    ]);
    fields
}

fn packaging_management(mutation: Mutation, packaging: Vec<PackagingCategory>) -> AnyView {
    let new = ui::save(
        mutation,
        "New packaging category",
        packaging_fields(),
        json!({"active": true}),
        |client, body| async move { client.create_packaging(&body).await },
    );
    let rows = packaging
        .into_iter()
        .map(|category| {
            let id = category.id;
            let edit = ui::save(
                mutation,
                "Edit packaging category",
                packaging_fields(),
                json!(category),
                move |client, body| async move { client.update_packaging(id, &body).await },
            );
            vec![
                ui::text(category.code),
                ui::text(category.name),
                ui::text(category.product_count),
                edit,
            ]
        })
        .collect();
    ui::management("Manage packaging", move || {
        view! {
        {new}{ui::table(&["Code","Name","Products","Actions"], rows, "No packaging categories.")}
    }.into_any()
    })
}

fn price_fields() -> Vec<Field> {
    vec![
        Field::text("unit_price", "Unit price").required(),
        Field::new("valid_from", "Valid from", FieldType::Date).required(),
    ]
}

#[component]
fn PricesTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.list_product_prices(id).await
    });
    let zones = ui::load(RwSignal::new(0), |client| async move {
        client.list_price_zones().await
    });
    view! {
        <section>
            <h2>"Prices"</h2>
            <Status mutation=mutation />
            {move || zones.get().and_then(Result::ok).map(|zones| {
                let mut fields = price_fields();
                fields.insert(0, Field::select("zone_id","Price zone",zones.iter().map(|z| (z.id, format!("{} · {}", z.code, z.name)))).required());
                let add = ui::save(mutation, "Schedule price", fields, json!({}),
                    move |client, body| async move {client.add_product_price(id, &body).await});
                view! {<div class="tc-phase-actions">{add}<BulkPrices id revision /></div>}
            })}
            {ui::loaded(data, move |prices| ui::table(&["Zone","Unit price","Valid from","Actions"], prices.into_iter().map(|p| {
                let price_id = p.id;
                let correct = ui::save(mutation, "Correct price", price_fields(), json!(p),
                    move |client, body| async move {client.correct_product_price(id, price_id, &body).await});
                let delete = ui::action(mutation, "Delete", Some("Delete this price entry?"),
                    move |client| async move {client.delete_product_price(id, price_id).await});
                vec![ui::text(p.zone_code), ui::text(p.unit_price), ui::text(p.valid_from),
                    view! {<div class="tc-phase-actions">{correct}{delete}</div>}.into_any()]
            }).collect(), "No prices."))}
        </section>
    }
}

#[component]
fn BulkPrices(id: Uuid, revision: RwSignal<u64>) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let preview = RwSignal::new(None::<(BulkPriceChangeInput, BulkPricePreview)>);
    let edit = ui::editor(
        "Bulk price adjustment",
        vec![
            Field::select(
                "kind",
                "Adjustment",
                [("percent", "Percent"), ("amount", "Fixed amount")],
            )
            .required(),
            Field::text("value", "Change (negative to reduce)").required(),
            Field::new("valid_from", "Valid from", FieldType::Date).required(),
            Field::text("rounding", "Rounding step"),
            Field::new(
                "replace_planned",
                "Replace prices already planned for that date",
                FieldType::Toggle,
            ),
        ],
        json!({"kind":"percent"}),
        mutation,
        move |mut value, open| {
            value["product_ids"] = json!([id]);
            let body: BulkPriceChangeInput = match serde_json::from_value(value) {
                Ok(body) => body,
                Err(err) => {
                    mutation.message.set(Some(Err(err.to_string())));
                    return;
                }
            };
            let snapshot = body.clone();
            mutation.run(
                move |client| async move { client.preview_bulk_prices(&body).await },
                move |result| {
                    preview.set(Some((snapshot, result)));
                    open.set(false);
                    Ok(())
                },
            );
        },
    );
    view! {
        {edit}
        <Status mutation=mutation />
        {move || preview.get().map(|(body, preview_data)| {
            let disabled = preview_data.conflicts > 0 || preview_data.lines.is_empty();
            let rows = preview_data.lines.into_iter().map(|r| vec![ui::text(r.zone_code),
                ui::text(r.current_price), ui::text(r.new_price), ui::text(if r.conflict {"Conflict"} else {""})]).collect();
            view! {
                <ui::DialogPanel title="Price adjustment preview" on_close=Callback::new(move |()| {
                    if !mutation.pending.get_untracked() {preview.set(None);}
                })>
                    <h3>"Price adjustment preview"</h3>
                    <p>{format!("{} · {} conflicts · {} without a price", preview_data.valid_from, preview_data.conflicts, preview_data.without_price)}</p>
                    {ui::table(&["Price zone","Current price","New price","Status"], rows, "No prices eligible for adjustment.")}
                    <Status mutation=mutation />
                    <div class="tc-phase-actions">
                        <button type="button" class="tc-btn tc-btn-primary" disabled=move || disabled || mutation.pending.get() on:click=move |_| {
                            let body = body.clone();
                            mutation.run(move |client| async move {client.apply_bulk_prices(&body).await}, move |report| {
                                preview.set(None);
                                mutation.saved(&format!("Updated {} prices.", report.applied));
                                Ok(())
                            });
                        }>"Apply adjustment"</button>
                        <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| preview.set(None)>"Close"</button>
                    </div>
                </ui::DialogPanel>
            }
        })}
    }
}

#[component]
fn OptionsTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.list_product_options(id).await
    });
    view! {
        <section>
            <h2>"Product options"</h2><Status mutation=mutation />
            {ui::loaded(data, move |options| {
                let choices = options.iter().map(|option| (
                    option.option_product_id, format!("{} · {}", option.option_code, option.option_name)
                )).collect();
                let fields = vec![Field::new("options", "Options", FieldType::Rows(vec![
                    Field::lookup("option_product_id", "Option product", Lookup::Product, choices).required(),
                    Field::text("default_quantity", "Default quantity"),
                    Field::new("sort_order", "Sort order", FieldType::Integer),
                    Field::new("required", "Required", FieldType::Toggle),
                    Field::new("active", "Active", FieldType::Toggle),
                ]))];
                let edit = ui::save(mutation, "Edit options", fields, json!({"options":options}),
                    move |client, value: Value| async move {
                        let body: Vec<ProductOptionInput> = ui::decode(value["options"].clone())?;
                        client.replace_product_options(id, &body).await
                    });
                let table = ui::table(&["Product","Default quantity","Required","Active"], options.into_iter().map(|o| vec![
                    ui::link(format!("{} · {}", o.option_code, o.option_name), &format!("/products/{}", o.option_product_id)),
                    ui::text(o.default_quantity),ui::text(ui::yes_no(o.required)),ui::text(ui::yes_no(o.active)),
                ]).collect(), "No product options.");
                view! {{edit}{table}}.into_any()
            })}
        </section>
    }
}

fn grid_fields() -> Vec<Field> {
    vec![
        Field::text("country_code", "Country code").required(),
        Field::text("name", "Name"),
        Field::new("voltage_v", "Voltage (V)", FieldType::Integer).required(),
        Field::new("phases", "Phases", FieldType::Integer).required(),
        Field::new("frequency_hz", "Frequency (Hz)", FieldType::Integer).required(),
        Field::new("active", "Active", FieldType::Toggle),
    ]
}

#[component]
fn PowerTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let supplies = ui::load(revision, move |client| async move {
        client.get_product_power_supplies(id).await
    });
    let grids = ui::load(revision, |client| async move {
        client
            .list_power_grids(&ListPowerGridsParams::default())
            .await
    });
    let grid = RwSignal::new(None::<Uuid>);
    let compatibility = ui::load(revision, move |client| {
        let grid_id = grid.get();
        async move {
            if grid_id.is_none() {
                return Ok(None);
            }
            client
                .get_product_power_compatibility(
                    id,
                    &GetProductPowerCompatibilityParams {
                        grid_id,
                        country: None,
                    },
                )
                .await
                .map(Some)
        }
    });
    view! {
        <section>
            <h2>"Power grids & supply requirements"</h2><Status mutation=mutation />
            {ui::loaded(supplies, move |supplies| {
                let fields = vec![Field::new("supplies","Supported power supplies",FieldType::Rows(vec![
                    Field::select("current_type","Current",[("ac","AC"),("dc","DC")]).required(),
                    Field::new("voltage_v","Nominal voltage (V)",FieldType::Integer).required(),
                    Field::new("voltage_min_v","Minimum voltage (V)",FieldType::Integer),
                    Field::new("voltage_max_v","Maximum voltage (V)",FieldType::Integer),
                    Field::new("tolerance_pct","Tolerance (%)",FieldType::Integer),
                    Field::new("phases","Phases",FieldType::Integer),
                    Field::new("frequency_hz","Frequency (Hz)",FieldType::Integer),
                ]))];
                let edit = ui::save(mutation,"Edit power supplies",fields,json!({"supplies":supplies}),move |client, value:Value| async move {
                    let body: Vec<PowerSupplyInput> = ui::decode(value["supplies"].clone())?;
                    client.replace_product_power_supplies(id,&body).await
                });
                let rows = supplies.into_iter().map(|s| vec![ui::text(s.current_type.to_uppercase()),ui::text(s.voltage_v),
                    ui::text(match (s.voltage_min_v,s.voltage_max_v) {(Some(min),Some(max))=>format!("{min}–{max} V"), _=>format!("±{}%",s.tolerance_pct)}),
                    ui::text(s.phases.map(|n|n.to_string()).unwrap_or_default()),ui::text(s.frequency_hz.map(|n|n.to_string()).unwrap_or_default())]).collect();
                view! {{edit}{ui::table(&["Current","Nominal voltage (V)","Range or tolerance","Phases","Frequency (Hz)"],rows,"No power supplies configured.")}}.into_any()
            })}
            {ui::loaded(grids, move |grids| {
                let options = grids.iter().filter(|g|g.active).map(|g| view! {
                    <option value=g.id.to_string()>{format!("{} · {} · {} V",g.country_code,g.name,g.voltage_v)}</option>
                }).collect_view();
                let edit = power_management(mutation, grids);
                view! {
                    <div class="tc-phase-actions">
                        <label class="tc-phase-field">"Check against a grid"
                            <select class="tc-input" on:change=move |ev| grid.set(event_target_value(&ev).parse().ok())>
                                <option value="">"Select a grid"</option>{options}
                            </select>
                        </label>
                        {edit}
                    </div>
                }.into_any()
            })}
            {ui::loaded(compatibility, |report| ui::text(report.map(|report| match report.status {
                PowerStatus::Compatible => "Compatible",PowerStatus::Incompatible => "Incompatible",
                PowerStatus::UnknownGrid => "Unknown grid",PowerStatus::NotApplicable => "Not applicable",
                PowerStatus::NeedsExternalSupply => "Needs external supply",
            }).unwrap_or_default()))}
        </section>
    }
}

fn power_management(mutation: Mutation, grids: Vec<PowerGrid>) -> AnyView {
    let new = ui::save(
        mutation,
        "New power grid",
        grid_fields(),
        json!({"active":true}),
        |client, body| async move { client.create_power_grid(&body).await },
    );
    let rows = grids
        .into_iter()
        .map(|g| {
            let id = g.id;
            let edit = ui::save(
                mutation,
                "Edit grid",
                grid_fields(),
                json!(g),
                move |client, body| async move { client.update_power_grid(id, &body).await },
            );
            vec![
                ui::text(g.country_code),
                ui::text(g.name),
                ui::text(g.voltage_v),
                ui::text(g.phases),
                ui::text(g.frequency_hz),
                edit,
            ]
        })
        .collect();
    ui::management("Manage power grids", move || {
        view! {
        {new}{ui::table(&["Country","Grid","Voltage (V)","Phases","Frequency (Hz)","Actions"],rows,"No power grids.")}
    }.into_any()
    })
}

#[component]
fn RelatedTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.get_related_products(id).await
    });
    let catalogs = ui::load(revision, |client| async move {
        Ok((
            client
                .list_products(&ListProductsParams::new().limit(500))
                .await?,
            client.list_families().await?,
        ))
    });
    view! {
        <section>
            <h2>"Related products"</h2><Status mutation=mutation />
            {ui::loaded(data, move |related| {
                let table = ui::table(&["Product","Based on","Note"],related.suggestions.into_iter().map(|p| vec![
                    ui::link(format!("{} · {}",p.product_code,p.product_name),&format!("/products/{}",p.product_id)),
                    ui::text(p.because_of_code),ui::text(p.note),
                ]).collect(),"No related product suggestions.");
                let manage = catalogs.get().and_then(Result::ok).map(|(products,families)| relations_management(mutation,id,related.rules,products.items,families));
                view! {{manage}{table}}.into_any()
            })}
        </section>
    }
}

fn relations_management(
    mutation: Mutation,
    id: Uuid,
    rules: Vec<ProductRelation>,
    products: Vec<Product>,
    families: Vec<ProductFamily>,
) -> AnyView {
    let product_choices = products
        .into_iter()
        .map(|p| (p.id, format!("{} · {}", p.code, p.name)))
        .collect::<Vec<_>>();
    let family_choices = families
        .into_iter()
        .map(|f| (f.id, format!("{} · {}", f.code, f.name)))
        .collect::<Vec<_>>();
    let fields = || {
        vec![
            Field::select(
                "kind",
                "Relation",
                [
                    ("compatible", "Compatible"),
                    ("incompatible", "Incompatible"),
                    ("suggested", "Suggested"),
                ],
            )
            .required(),
            Field::select("a_product_id", "From product", product_choices.clone()),
            Field::select("a_family_id", "From family", family_choices.clone()),
            Field::select("b_product_id", "To product", product_choices.clone()),
            Field::select("b_family_id", "To family", family_choices.clone()),
            Field::new("bidirectional", "Bidirectional", FieldType::Toggle),
            Field::new("active", "Active", FieldType::Toggle),
            Field::new("strength", "Strength", FieldType::Integer),
            Field::text("note", "Note"),
        ]
    };
    let new = ui::save(
        mutation,
        "New relation",
        fields(),
        json!({"a_product_id":id,"active":true}),
        |client, body| async move { client.create_product_relation(&body).await },
    );
    let rows = rules
        .into_iter()
        .map(|p| {
            let id = p.id;
            let edit = ui::save(
                mutation,
                "Edit relation",
                fields(),
                json!(p),
                move |client, body| async move { client.update_product_relation(id, &body).await },
            );
            vec![
                ui::text(p.a_product_code.or(p.a_family_code).unwrap_or_default()),
                ui::text(p.b_product_code.or(p.b_family_code).unwrap_or_default()),
                ui::text(p.kind),
                ui::text(ui::yes_no(p.active)),
                edit,
            ]
        })
        .collect();
    ui::management("Manage relations", move || {
        view! {
            {new}{ui::table(&["From","To","Relation","Active","Actions"],rows,"No relation rules.")}
        }
        .into_any()
    })
}

#[component]
fn SuitabilityTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        Ok((
            client.list_product_attributes(id).await?,
            client.list_attribute_definitions().await?,
        ))
    });
    view! {
        <section>
            <h2>"Site suitability"</h2><Status mutation=mutation />
            {ui::loaded(data, move |(attrs, definitions)| {
                let mut fields = vec![];
                let mut initial = serde_json::Map::new();
                let defs = definitions.into_iter().filter(|d| d.active && d.scope == "product").collect::<Vec<_>>();
                for def in &defs {
                    let label = def.unit.as_ref().map(|unit|format!("{} ({unit})",def.label)).unwrap_or_else(||def.label.clone());
                    let saved = attrs.iter().find(|attr|attr.key==def.key);
                    if def.kind == DefinitionKind::Range {
                        for (suffix,value) in [("min",saved.and_then(|a|a.value_min.as_ref())),("max",saved.and_then(|a|a.value_max.as_ref()))] {
                            let key = format!("{}.{}", def.key, suffix);
                            initial.insert(key.clone(),json!(value));
                            fields.push(Field::owned(key,format!("{label} {suffix}"),FieldType::Text));
                        }
                    } else {
                        initial.insert(def.key.clone(),json!(saved.map(|a|&a.value)));
                        let kind = match def.kind {
                            DefinitionKind::Boolean => FieldType::Select(vec![("true".into(),"Yes".into()),("false".into(),"No".into())]),
                            DefinitionKind::Select => FieldType::Select(def.options.iter().map(|o|(o.value.clone(),o.label.clone())).collect()),
                            _ => FieldType::Text,
                        };
                        fields.push(Field::owned(def.key.clone(),label,kind));
                    }
                }
                let rows = attrs.iter().map(|a| vec![ui::text(defs.iter().find(|d|d.key==a.key).map_or(&a.key,|d|&d.label)),
                    ui::text(&a.value),ui::text(a.unit.as_deref().unwrap_or_default())]).collect();
                let edit = (!fields.is_empty()).then(|| ui::save(mutation,"Edit suitability",fields,Value::Object(initial),move |client,value:Value| {
                    let mut body = attrs.iter().filter(|a| !defs.iter().any(|d|d.key==a.key)).cloned().collect::<Vec<_>>();
                    for def in &defs {
                        let get = |key:&str|value.get(key).and_then(Value::as_str).map(str::to_owned);
                        let value_min = get(&format!("{}.min",def.key));
                        let value_max = get(&format!("{}.max",def.key));
                        let raw = get(&def.key);
                        if raw.is_some() || value_min.is_some() || value_max.is_some() {
                            let kind = match def.kind {
                                DefinitionKind::Number => AttributeKind::Number,
                                DefinitionKind::Range => AttributeKind::Range,
                                DefinitionKind::Boolean => AttributeKind::Boolean,
                                _ => AttributeKind::Text,
                            };
                            body.push(ProductAttribute {key:def.key.clone(),kind,unit:def.unit.clone(),value:raw.unwrap_or_default(),value_min,value_max});
                        }
                    }
                    async move {client.replace_product_attributes(id,&body).await}
                }));
                view! {{edit}{ui::table(&["Attribute","Value","Unit"],rows,"No suitability attributes set.")}}.into_any()
            })}
        </section>
    }
}

#[component]
pub(super) fn ProductCsvActions(reload: RwSignal<u64>) -> impl IntoView {
    let mutation = Mutation::new(reload);
    let preview = RwSignal::new(None::<(Vec<u8>, ImportReport)>);
    view! {
        <div class="tc-phase-actions">
            <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| {
                mutation.run(|client| async move {
                    client.export_products(&ExportProductsParams {format:Some("csv".into())}).await
                }, |bytes| save_file("products.csv","text/csv",&bytes));
            }>"Export CSV"</button>
            <label class="tc-phase-field">"Import CSV"
                <input type="file" accept=".csv,text/csv" disabled=move || mutation.pending.get() on:change=move |ev| {
                    preview.set(None);
                    begin_file_read(ev,10*1024*1024,"The maximum file size is 10 MB.",move |file| {
                        if preview.is_disposed() {return;}
                        match file {
                            Ok(file) => {
                                let payload = file.bytes.clone();
                                mutation.run(move |client| async move {
                                    client.import_products(&ImportProductsParams {dry_run:Some(true),sheet:None},payload).await
                                },move |report| {preview.set(Some((file.bytes,report)));Ok(())});
                            }
                            Err(err) if !err.is_empty() => mutation.message.set(Some(Err(err))),
                            _ => (),
                        }
                    });
                } />
            </label>
        </div>
        <Status mutation=mutation />
        {move || preview.get().map(|(bytes,report)| {
            let has_errors = !report.errors.is_empty();
            view! {
                <ui::DialogPanel title="Product import preview" on_close=Callback::new(move |()| {
                    if !mutation.pending.get_untracked() {preview.set(None);}
                })>
                    <h3>"Product import preview"</h3>
                    <p>{format!("{} new · {} updates · {} unchanged",report.created,report.updated,report.unchanged)}</p>
                    <ul>{report.errors.into_iter().map(|r|view! {<li>{format!("Row {} · {}",r.row,r.message)}</li>}).collect_view()}</ul>
                    <Status mutation=mutation />
                    <div class="tc-phase-actions">
                        <button type="button" class="tc-btn tc-btn-primary" disabled=move || has_errors || mutation.pending.get() on:click=move |_| {
                            let bytes = bytes.clone();
                            mutation.run(move |client|async move {
                                client.import_products(&ImportProductsParams {dry_run:Some(false),sheet:None},bytes).await
                            },move |report| {
                                preview.set(None);
                                if report.errors.is_empty() {
                                    mutation.saved(&format!("Imported {} new and {} updated products.",report.created,report.updated));
                                    Ok(())
                                } else {Err(format!("Import failed on {} rows. Preview the file again.",report.errors.len()))}
                            });
                        }>"Import products"</button>
                        <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| preview.set(None)>"Close"</button>
                    </div>
                </ui::DialogPanel>
            }
        })}
    }
}
