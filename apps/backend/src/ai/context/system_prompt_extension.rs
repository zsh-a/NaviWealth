//! Wave 27 — render a [`ContextPack`] into a short prompt appendix.
//!
//! The Worker route appends this string to `guardrails::SYSTEM_PROMPT`
//! (not replacing it) so the LLM sees the static base prompt AND the
//! per-turn derived signals. Tone: short, structured, deterministic —
//! never speculative.
//!
//! Token budget: aim for < 400 tokens. Skip empty sections rather than
//! emit headers with no rows. Signals are capped at six entries
//! (newest first when the caller orders them that way).

use super::context_pack::{
    BaseContext, CashflowTrend, ContextPack, FireGoalSummary, RecentSignal, RiskPreference,
    RouteContext, SignalSeverity, TaskContext,
};

const MAX_SIGNALS: usize = 6;

pub fn format_context_pack(pack: &ContextPack) -> String {
    let mut out = String::with_capacity(512);
    out.push_str("\n\n# 用户当前上下文 (server-derived, do not echo verbatim)\n");
    write_route(&mut out, &pack.task.route);
    write_base(&mut out, &pack.base);
    write_signals(&mut out, &pack.task.signals);
    write_aggregates_summary(&mut out, &pack.task);
    write_freshness_hint(&mut out, &pack.task);
    write_uploads_summary(&mut out, &pack.task);
    out
}

fn write_route(out: &mut String, r: &RouteContext) {
    out.push_str(&format!("- 当前路由: area={} path={}\n", r.area, r.path));
}

fn write_base(out: &mut String, b: &BaseContext) {
    out.push_str(&format!(
        "- 偏好币种: {} · 风险偏好: {}\n",
        b.preferred_currency,
        risk_label(b.risk_preference),
    ));
    if b.accounts.total_count > 0 || !b.accounts.by_kind.is_empty() {
        let by_kind = b
            .accounts
            .by_kind
            .iter()
            .map(|(kind, n)| format!("{kind}={n}"))
            .collect::<Vec<_>>()
            .join(", ");
        if by_kind.is_empty() {
            out.push_str(&format!("- 账户摘要: 总数 {}\n", b.accounts.total_count));
        } else {
            out.push_str(&format!(
                "- 账户摘要: 总数 {} · {}\n",
                b.accounts.total_count, by_kind
            ));
        }
    }
    out.push_str(&format!(
        "- 现金流: 月均流入≈{} 流出≈{} {} (趋势: {})\n",
        b.cashflow.average_inflow_minor,
        b.cashflow.average_outflow_minor,
        b.cashflow.base_currency,
        cashflow_trend_label(b.cashflow.trend),
    ));
    if let Some(fire) = &b.fire_goal {
        write_fire(out, fire);
    }
}

fn write_fire(out: &mut String, f: &FireGoalSummary) {
    let pct = (f.progress_fraction * 100.0).clamp(0.0, 100.0);
    let years = f
        .years_remaining_estimate
        .map(|y| format!("约 {y:.1} 年"))
        .unwrap_or_else(|| "未估算".into());
    out.push_str(&format!(
        "- FIRE 目标: 已完成 {pct:.1}% · 剩余 {years} · 目标 {} {}\n",
        f.target_minor, f.currency
    ));
}

fn write_signals(out: &mut String, signals: &[RecentSignal]) {
    if signals.is_empty() {
        return;
    }
    out.push_str("\n## 最近信号\n");
    for s in signals.iter().take(MAX_SIGNALS) {
        out.push_str(&format!(
            "- [{}] {:?}: {}\n",
            severity_tag(s.severity),
            s.kind,
            sanitise_summary(&s.summary_zh),
        ));
    }
    if signals.len() > MAX_SIGNALS {
        out.push_str(&format!(
            "- (...还有 {} 条未展示)\n",
            signals.len() - MAX_SIGNALS
        ));
    }
}

fn write_aggregates_summary(out: &mut String, t: &TaskContext) {
    if t.aggregates.is_empty() {
        return;
    }
    out.push_str(&format!(
        "\n## 客户端已聚合 ({} 条范围/分类摘要可作参考)\n",
        t.aggregates.len()
    ));
    // Don't dump details — those go through read_*_window tools when
    // the LLM needs them. Just acknowledge presence.
}

fn write_freshness_hint(out: &mut String, t: &TaskContext) {
    if let Some(hint) = &t.freshness_hint {
        if !hint.force_refresh_read_models.is_empty() {
            out.push_str("\n## 注意: 客户端检测到 read model 落后，已请求强制刷新:\n");
            for name in &hint.force_refresh_read_models {
                out.push_str(&format!("- {name}\n"));
            }
        }
    }
}

fn write_uploads_summary(out: &mut String, t: &TaskContext) {
    if t.analytical_uploads.is_empty() {
        return;
    }
    // 不展开 payload — 详细数据走 get_recurring_patterns /
    // get_anomaly_flags / get_subscription_changes 等工具。这里只让 LLM
    // 知道"本轮有新的端侧检测结果"。
    use std::collections::BTreeMap;
    let mut by_kind: BTreeMap<&str, u32> = BTreeMap::new();
    for u in &t.analytical_uploads {
        *by_kind.entry(u.kind.as_str()).or_insert(0) += 1;
    }
    out.push_str("\n## 本轮端侧分析上报\n");
    for (kind, n) in by_kind {
        out.push_str(&format!("- {kind}: {n}\n"));
    }
}

fn risk_label(r: RiskPreference) -> &'static str {
    match r {
        RiskPreference::Conservative => "conservative",
        RiskPreference::Moderate => "moderate",
        RiskPreference::Aggressive => "aggressive",
    }
}

fn cashflow_trend_label(t: CashflowTrend) -> &'static str {
    match t {
        CashflowTrend::Improving => "improving",
        CashflowTrend::Stable => "stable",
        CashflowTrend::Worsening => "worsening",
        CashflowTrend::Unknown => "unknown",
    }
}

fn severity_tag(s: SignalSeverity) -> &'static str {
    match s {
        SignalSeverity::Info => "info",
        SignalSeverity::Warn => "warn",
        SignalSeverity::Critical => "critical",
    }
}

/// Truncate noisy summaries; the field is user-facing copy so we trim
/// rather than reject to keep diagnostics readable.
fn sanitise_summary(s: &str) -> String {
    const MAX_LEN: usize = 120;
    let trimmed = s.trim();
    if trimmed.chars().count() > MAX_LEN {
        let cut: String = trimmed.chars().take(MAX_LEN).collect();
        format!("{cut}…")
    } else {
        trimmed.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::context::context_pack::*;
    use crate::ai::context::disclosure::*;
    use std::collections::BTreeMap;

    fn minimal_pack() -> ContextPack {
        ContextPack {
            version: ContextPackVersion { major: 1, minor: 0 },
            base: BaseContext {
                preferred_currency: "USD".into(),
                risk_preference: RiskPreference::Moderate,
                accounts: AccountSummary {
                    total_count: 7,
                    by_kind: BTreeMap::new(),
                },
                cashflow: CashflowSummary {
                    base_currency: "USD".into(),
                    months_covered: 12,
                    average_inflow_minor: "500000".into(),
                    average_outflow_minor: "320000".into(),
                    trend: CashflowTrend::Stable,
                },
                fire_goal: None,
            },
            task: TaskContext {
                route: RouteContext {
                    path: "/".into(),
                    area: "home".into(),
                },
                intent: IntentHint {
                    capability: Capability::Analyze,
                    risk: RiskLevel::Info,
                    side_effect: None,
                    label: None,
                },
                signals: vec![],
                retrieved: vec![],
                aggregates: vec![],
                freshness_hint: None,
                analytical_uploads: vec![],
                device_hlc: None,
            },
            budget: PrivacyBudget {
                tier: BudgetTier::Small,
            },
        }
    }

    #[test]
    fn includes_route_and_base_for_minimal_pack() {
        let s = format_context_pack(&minimal_pack());
        assert!(s.contains("当前路由: area=home"));
        assert!(s.contains("偏好币种: USD"));
        assert!(s.contains("风险偏好: moderate"));
        assert!(s.contains("现金流"));
    }

    #[test]
    fn skips_signals_section_when_empty() {
        let s = format_context_pack(&minimal_pack());
        assert!(!s.contains("最近信号"));
    }

    #[test]
    fn surfaces_signals_with_severity_tag() {
        let mut pack = minimal_pack();
        pack.task.signals.push(RecentSignal {
            kind: SignalKind::SubscriptionPriceUp,
            severity: SignalSeverity::Warn,
            summary_zh: "Netflix 涨了 18%".into(),
            detail_ref: None,
        });
        let s = format_context_pack(&pack);
        assert!(s.contains("## 最近信号"));
        assert!(s.contains("[warn]"));
        assert!(s.contains("Netflix"));
    }

    #[test]
    fn caps_signals_at_six_with_overflow_line() {
        let mut pack = minimal_pack();
        for i in 0..10 {
            pack.task.signals.push(RecentSignal {
                kind: SignalKind::SpendingSpike,
                severity: SignalSeverity::Info,
                summary_zh: format!("信号 {i}"),
                detail_ref: None,
            });
        }
        let s = format_context_pack(&pack);
        // 6 shown, 4 hidden.
        assert!(s.contains("还有 4 条未展示"));
    }

    #[test]
    fn freshness_hint_surfaces_force_refresh_list() {
        let mut pack = minimal_pack();
        pack.task.freshness_hint = Some(FreshnessHint {
            force_refresh_read_models: vec![
                "holdings_snapshot".into(),
                "net_worth_snapshot".into(),
            ],
            last_local_hlc: None,
        });
        let s = format_context_pack(&pack);
        assert!(s.contains("强制刷新"));
        assert!(s.contains("holdings_snapshot"));
        assert!(s.contains("net_worth_snapshot"));
    }

    #[test]
    fn empty_freshness_hint_does_not_render_section() {
        let mut pack = minimal_pack();
        pack.task.freshness_hint = Some(FreshnessHint {
            force_refresh_read_models: vec![],
            last_local_hlc: None,
        });
        let s = format_context_pack(&pack);
        assert!(!s.contains("强制刷新"));
    }

    #[test]
    fn uploads_grouped_by_kind() {
        let mut pack = minimal_pack();
        for kind in &["recurring_pattern", "recurring_pattern", "anomaly_flag"] {
            pack.task.analytical_uploads.push(AnalyticalUpload {
                kind: (*kind).into(),
                id: format!("id_{}", pack.task.analytical_uploads.len()),
                payload: serde_json::Value::Null,
            });
        }
        let s = format_context_pack(&pack);
        assert!(s.contains("## 本轮端侧分析上报"));
        assert!(s.contains("recurring_pattern: 2"));
        assert!(s.contains("anomaly_flag: 1"));
    }

    #[test]
    fn fire_goal_renders_percentage_and_estimate() {
        let mut pack = minimal_pack();
        pack.base.fire_goal = Some(FireGoalSummary {
            target_minor: "100000000".into(),
            currency: "USD".into(),
            progress_fraction: 0.42,
            years_remaining_estimate: Some(8.3),
        });
        let s = format_context_pack(&pack);
        assert!(s.contains("FIRE"));
        assert!(s.contains("42.0%"));
        assert!(s.contains("8.3 年"));
    }

    #[test]
    fn long_summary_is_truncated() {
        let mut pack = minimal_pack();
        pack.task.signals.push(RecentSignal {
            kind: SignalKind::Other,
            severity: SignalSeverity::Info,
            summary_zh: "あ".repeat(200),
            detail_ref: None,
        });
        let s = format_context_pack(&pack);
        assert!(s.contains("…"));
    }
}
