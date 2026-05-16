//! ContextPack freshness and analytical upload ingest.

use worker::D1Database;

use crate::ai::context::ContextPack;
use crate::error::AppError;

pub async fn ingest_context_pack(
    db: &D1Database,
    user_id: &str,
    pack: Option<&ContextPack>,
) -> Result<(), AppError> {
    let Some(pack) = pack else {
        return Ok(());
    };

    clear_freshness_hints(db, user_id, pack).await?;
    ingest_analytical_uploads(db, user_id, pack).await
}

async fn clear_freshness_hints(
    db: &D1Database,
    user_id: &str,
    pack: &ContextPack,
) -> Result<(), AppError> {
    let Some(hint) = &pack.task.freshness_hint else {
        return Ok(());
    };

    for name in &hint.force_refresh_read_models {
        if name.is_empty() {
            continue;
        }
        crate::ai::read_models::projection::clear_freshness_meta(db, user_id, name).await?;
        worker::console_log!("freshness_hint: cleared read_model={name} for user={user_id}");
    }
    Ok(())
}

async fn ingest_analytical_uploads(
    db: &D1Database,
    user_id: &str,
    pack: &ContextPack,
) -> Result<(), AppError> {
    if pack.task.analytical_uploads.is_empty() {
        return Ok(());
    }

    let device_hlc = pack
        .task
        .device_hlc
        .as_deref()
        .filter(|s| !s.is_empty())
        .unwrap_or("0.0000-00000000-0000-0000-0000-000000000000");

    let recurring: Vec<crate::ai::read_models::recurring_patterns::RecurringPatternUpload<'_>> =
        pack.task
            .analytical_uploads
            .iter()
            .filter(|u| u.kind == "recurring_pattern")
            .map(
                |u| crate::ai::read_models::recurring_patterns::RecurringPatternUpload {
                    id: &u.id,
                    payload: &u.payload,
                    source_device_id: None,
                },
            )
            .collect();
    if !recurring.is_empty() {
        let n =
            crate::ai::read_models::recurring_patterns::ingest(db, user_id, device_hlc, &recurring)
                .await?;
        worker::console_log!(
            "analytical_uploads: ingested {n} recurring_patterns for user={user_id}"
        );
    }

    let anomalies: Vec<crate::ai::read_models::anomaly_flags::AnomalyFlagUpload<'_>> = pack
        .task
        .analytical_uploads
        .iter()
        .filter(|u| u.kind == "anomaly_flag")
        .map(
            |u| crate::ai::read_models::anomaly_flags::AnomalyFlagUpload {
                id: &u.id,
                payload: &u.payload,
                source_device_id: None,
            },
        )
        .collect();
    if !anomalies.is_empty() {
        let n = crate::ai::read_models::anomaly_flags::ingest(db, user_id, device_hlc, &anomalies)
            .await?;
        worker::console_log!("analytical_uploads: ingested {n} anomaly_flags for user={user_id}");
    }

    let refunds: Vec<crate::ai::read_models::refund_links::RefundLinkUpload<'_>> = pack
        .task
        .analytical_uploads
        .iter()
        .filter(|u| u.kind == "refund_link")
        .map(|u| crate::ai::read_models::refund_links::RefundLinkUpload {
            id: &u.id,
            payload: &u.payload,
            source_device_id: None,
        })
        .collect();
    if !refunds.is_empty() {
        let n =
            crate::ai::read_models::refund_links::ingest(db, user_id, device_hlc, &refunds).await?;
        worker::console_log!("analytical_uploads: ingested {n} refund_links for user={user_id}");
    }

    let transfers: Vec<crate::ai::read_models::transfer_links::TransferLinkUpload<'_>> = pack
        .task
        .analytical_uploads
        .iter()
        .filter(|u| u.kind == "transfer_link")
        .map(
            |u| crate::ai::read_models::transfer_links::TransferLinkUpload {
                id: &u.id,
                payload: &u.payload,
                source_device_id: None,
            },
        )
        .collect();
    if !transfers.is_empty() {
        let n = crate::ai::read_models::transfer_links::ingest(db, user_id, device_hlc, &transfers)
            .await?;
        worker::console_log!("analytical_uploads: ingested {n} transfer_links for user={user_id}");
    }

    let perfs: Vec<
        crate::ai::read_models::investment_performance::InvestmentPerformanceUpload<'_>,
    > = pack
        .task
        .analytical_uploads
        .iter()
        .filter(|u| u.kind == "investment_performance")
        .map(
            |u| crate::ai::read_models::investment_performance::InvestmentPerformanceUpload {
                id: &u.id,
                payload: &u.payload,
                source_device_id: None,
            },
        )
        .collect();
    if !perfs.is_empty() {
        let n =
            crate::ai::read_models::investment_performance::ingest(db, user_id, device_hlc, &perfs)
                .await?;
        worker::console_log!(
            "analytical_uploads: ingested {n} investment_performance for user={user_id}"
        );
    }

    let subs: Vec<crate::ai::read_models::subscription_changes::SubscriptionChangeUpload<'_>> =
        pack.task
            .analytical_uploads
            .iter()
            .filter(|u| u.kind == "subscription_change")
            .map(
                |u| crate::ai::read_models::subscription_changes::SubscriptionChangeUpload {
                    id: &u.id,
                    payload: &u.payload,
                    source_device_id: None,
                },
            )
            .collect();
    if !subs.is_empty() {
        let n =
            crate::ai::read_models::subscription_changes::ingest(db, user_id, device_hlc, &subs)
                .await?;
        worker::console_log!(
            "analytical_uploads: ingested {n} subscription_changes for user={user_id}"
        );
    }

    Ok(())
}
