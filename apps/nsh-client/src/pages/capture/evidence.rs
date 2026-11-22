//! Field-level provenance and explicit acceptance of a proposed funding account.
use super::*;
use crate::{
    domain::capture::Record,
    domain::capture_evidence::{EvidenceSource, FieldEvidence},
    i18n::catalog::copy,
};

fn source_label(source: &EvidenceSource) -> &'static str {
    match source {
        EvidenceSource::Text => copy("Your words", "你说的"),
        EvidenceSource::Image => copy("Photo", "图片"),
        EvidenceSource::Inferred => copy("Inferred", "推断"),
        EvidenceSource::History => copy("Recent records", "最近记录"),
        EvidenceSource::Favorite => s().favorites,
        EvidenceSource::Owner => copy("You confirmed", "你确认的"),
    }
}

fn label(field: &str) -> &str {
    match field {
        "day" => s().transaction_date,
        "kind" => copy("Record type", "记录类型"),
        "amount" => s().money_amount,
        "account" => s().own_account,
        "other_account" => s().to_account,
        "cash" => s().cash_account,
        "time" => copy("Time", "时间"),
        "grams" => copy("Portion", "分量"),
        "nutrition" => copy("Nutrition", "营养"),
        "currency" => copy("Currency", "币种"),
        "category" => s().category,
        "payee" => s().capture_payee,
        "note" | "text" => copy("Note", "备注"),
        "weight_kg" => s().weight,
        "title" => s().name,
        "slot" => copy("Meal time", "餐次"),
        "foods" => copy("Foods", "食物"),
        "quantity" => s().quantity,
        "price" => s().holding_price,
        "security" => s().security_name,
        "fee" => s().fee,
        "actual" => s().actual_balance,
        _ => field,
    }
}

fn reason(item: &FieldEvidence) -> String {
    if !item.reason.trim().is_empty() {
        return item.reason.clone();
    }
    match item.source {
        EvidenceSource::Owner => copy(
            "You selected or edited this value in the draft.",
            "你在这份草稿里选择或修改了这个值。",
        ),
        EvidenceSource::Text => copy(
            "The model attributed this field to your message.",
            "模型将这个字段归因于你的描述。",
        ),
        EvidenceSource::Image => copy(
            "The model attributed this field to an attached image.",
            "模型将这个字段归因于所附图片。",
        ),
        EvidenceSource::History => copy(
            "The model used the recent records shared for this request.",
            "模型参考了本次识别获准使用的最近记录。",
        ),
        EvidenceSource::Favorite => copy(
            "The model used favorites shared for this request.",
            "模型参考了本次识别获准使用的收藏。",
        ),
        EvidenceSource::Inferred => copy(
            "The model inferred this value. Check it before saving.",
            "这是模型的推断，请在保存前核对。",
        ),
    }
    .into()
}

fn sources(fields: &[FieldEvidence]) -> AnyElement {
    let selected = signal(None::<usize>);
    let reasons: Vec<_> = fields.iter().map(reason).collect();
    view()
        .gap_1()
        .child(
            view()
                .flex_row()
                .flex_wrap()
                .gap_1()
                .children(fields.iter().enumerate().map(|(index, item)| {
                    let title = format!("{} · {}", label(&item.field), source_label(&item.source));
                    view()
                        .role(AccessibilityRole::Button)
                        .optional_label({
                            let title = title.clone();
                            move || Some(title.clone().into())
                        })
                        .accessibility_state(move || AccessibilityState {
                            expanded: Some(selected.get() == Some(index)),
                            ..Default::default()
                        })
                        .on_press(move || {
                            selected.update(|open| *open = (*open != Some(index)).then_some(index))
                        })
                        .min_h(px(44.0))
                        .px_2()
                        .rounded(px(radius::BADGE))
                        .justify_center()
                        .bg(move || {
                            if selected.get() == Some(index) {
                                color::ACCENT_SOFT
                            } else {
                                AdaptiveColor::TRANSPARENT
                            }
                        })
                        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                        .child(
                            text(title)
                                .typo(Type::Caption)
                                .text_color(color::ACCENT_INK),
                        )
                })),
        )
        .child(dynamic(move || {
            selected
                .get()
                .and_then(|i| reasons.get(i).cloned())
                .map(|why| text(why).typo(Type::Subhead).text_color(color::BODY))
        }))
        .into_element()
}

pub(super) fn field_sources(
    draft: &Draft,
    index: usize,
    live: Signal<Draft>,
    input: Signal<String>,
    error: Signal<Option<String>>,
) -> AnyElement {
    let fields = draft.evidence.get(index).filter(|items| !items.is_empty());
    let mut pane = view().gap_1().child(fields.map(|items| sources(items)));
    let record = &draft.records[index];
    for (field, proposed) in match record {
        Record::Money { draft: d, .. } => vec![
            ("account", d.account.as_ref()),
            ("other_account", d.other_account.as_ref()),
        ],
        Record::Trade { cash, .. } => vec![("cash", cash.as_ref())],
        Record::Balance { account, .. } => vec![("account", Some(account))],
        _ => vec![],
    } {
        let destination = field == "other_account";
        if let Some(account) = proposed.filter(|a| {
            draft.account_needs_approval(index, field, &crate::data::finance::active_accounts())
                && capture::accepts_account(record, destination, a)
        }) {
            let proposed = account.clone();
            let name = crate::pages::finance::selected_account_label(account);
            pane = pane.child(
                Btn::secondary()
                    .label(move || {
                        format!("{} · {}", copy("Use this account", "使用此账户"), name).into()
                    })
                    .on_press(move || {
                        let mut next = live.get_untracked();
                        if next.status != Status::Ready
                            || !next.account_needs_approval(
                                index,
                                field,
                                &crate::data::finance::active_accounts(),
                            )
                        {
                            return;
                        }
                        let current = match (next.records.get(index), field) {
                            (Some(Record::Money { draft, .. }), "account") => {
                                draft.account.as_ref()
                            }
                            (Some(Record::Money { draft, .. }), "other_account") => {
                                draft.other_account.as_ref()
                            }
                            (Some(Record::Trade { cash, .. }), "cash") => cash.as_ref(),
                            (Some(Record::Balance { account, .. }), "account") => Some(account),
                            _ => None,
                        };
                        if current != Some(&proposed)
                            || !capture::accepts_account(
                                &next.records[index],
                                destination,
                                &proposed,
                            )
                        {
                            return;
                        }
                        next.mark_owner_field(index, field);
                        next.correction = input.get_untracked();
                        match capture::put(next.clone()) {
                            Ok(()) => {
                                haptic(nsh_core::Haptic::Selection);
                                error.set(None);
                                live.set(next);
                            }
                            Err(cause) => {
                                log::error!("capture: could not keep approval: {cause}");
                                error.set(Some(s().error_transaction_storage.into()));
                            }
                        }
                    }),
            );
        }
    }
    pane.into_element()
}
