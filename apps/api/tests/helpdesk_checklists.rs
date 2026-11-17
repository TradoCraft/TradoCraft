//! Template application holds a consistent version until its transaction completes.
use sqlx::PgPool;
use tradocraft_core::new_id;

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn application_holds_template_lock_through_item_copy(db: PgPool) {
    sqlx::raw_sql(tradocraft_api::DEV_SEED_SQL)
        .execute(&db)
        .await
        .unwrap();
    let company: uuid::Uuid = sqlx::query_scalar("SELECT id FROM core.companies LIMIT 1")
        .fetch_one(&db)
        .await
        .unwrap();
    let ticket = new_id();
    let template = new_id();
    sqlx::query("INSERT INTO helpdesk.tickets (id, company_id, number, subject, language) VALUES ($1, $2, 'LOCK-TEST', 'Lock test', 'en')")
        .bind(ticket).bind(company).execute(&db).await.unwrap();
    sqlx::query("INSERT INTO helpdesk.checklist_templates (id, company_id, name) VALUES ($1, $2, 'Version one')")
        .bind(template).bind(company).execute(&db).await.unwrap();
    sqlx::query("INSERT INTO helpdesk.checklist_template_items (id, template_id, position, description) VALUES ($1, $2, 1, 'Original item')")
        .bind(new_id()).bind(template).execute(&db).await.unwrap();

    let mut application = db.begin().await.unwrap();
    let (items, applied) = tradocraft_helpdesk::checklists::apply_template_to_ticket(
        &mut application,
        company,
        ticket,
        template,
        true,
    )
    .await
    .unwrap();
    assert!(applied);
    assert_eq!(items[0].description, "Original item");
    let mut editor = db.acquire().await.unwrap();
    sqlx::query("SET lock_timeout = '100ms'")
        .execute(&mut *editor)
        .await
        .unwrap();
    let error = sqlx::query("UPDATE helpdesk.checklist_templates SET active = false WHERE id = $1")
        .bind(template)
        .execute(&mut *editor)
        .await
        .unwrap_err();
    assert_eq!(
        error.as_database_error().unwrap().code().as_deref(),
        Some("55P03")
    );
    application.commit().await.unwrap();
    sqlx::query("UPDATE helpdesk.checklist_templates SET active = false WHERE id = $1")
        .bind(template)
        .execute(&mut *editor)
        .await
        .unwrap();
}
