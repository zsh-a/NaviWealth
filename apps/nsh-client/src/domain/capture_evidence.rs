//! Attribution belongs to the proposed field. A provider cannot mark a value
//! as locally approved, and every replacement reply starts a fresh review.
use super::capture::{AskAnswer, Draft, Record, Turn};
use navi_finance::account::Account;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceSource {
    Text,
    Image,
    Inferred,
    Favorite,
    History,
    Owner,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldEvidence {
    pub field: String,
    pub source: EvidenceSource,
    pub reason: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CaptureDestination {
    Review,
    Assets,
    Records,
}

pub(super) fn schema() -> Value {
    json!({"type":"array","maxItems":16,"items":{"type":"object","additionalProperties":false,
        "required":["field","source","reason"],"properties":{
        "field":{"type":"string"},"source":{"type":"string","enum":["text","image","inferred","favorite","history"]},
        "reason":{"type":"string"}}}})
}

fn fields(record: &Record) -> &'static [&'static str] {
    match record {
        Record::Money { .. } => &[
            "day",
            "amount",
            "currency",
            "account",
            "other_account",
            "category",
            "time",
            "payee",
            "note",
        ],
        Record::Meal { .. } => &["day", "slot", "title", "foods", "grams", "nutrition"],
        Record::Weight { .. } => &["day", "weight_kg"],
        Record::Trade { .. } => &[
            "day", "security", "kind", "quantity", "price", "amount", "fee", "cash", "currency",
        ],
        Record::Balance { .. } => &["day", "account", "actual"],
        Record::Price { .. } => &["day", "security", "price", "currency"],
        Record::Note { .. } => &["day", "text"],
    }
}

fn account<'a>(record: &'a Record, field: &str) -> Option<&'a Account> {
    match (record, field) {
        (Record::Money { draft, .. }, "account") => draft.account.as_ref(),
        (Record::Money { draft, .. }, "other_account") => draft.other_account.as_ref(),
        (Record::Trade { cash, .. }, "cash") => cash.as_ref(),
        (Record::Balance { account, .. }, "account") => Some(account),
        _ => None,
    }
}

impl Draft {
    pub fn destination(&self) -> Option<CaptureDestination> {
        let Turn::Assistant { reply, .. } = self.transcript.last()? else {
            return None;
        };
        if !self.records.is_empty() {
            return None;
        }
        let value: Value = serde_json::from_str(reply).ok()?;
        serde_json::from_value(value.get("destination")?.clone()).ok()
    }

    /// Called by the field editor or the explicit suggestion-approval button.
    pub fn mark_owner_field(&mut self, index: usize, field: &str) {
        let Some(record) = self.records.get(index) else {
            return;
        };
        if !fields(record).contains(&field) {
            return;
        }
        self.evidence.resize_with(self.records.len(), Vec::new);
        let row = &mut self.evidence[index];
        row.retain(|e| e.field != field);
        row.push(FieldEvidence {
            field: field.into(),
            source: EvidenceSource::Owner,
            reason: String::new(),
        });
    }

    pub fn account_needs_approval(&self, index: usize, field: &str) -> bool {
        let Some(selected) = self.records.get(index).and_then(|r| account(r, field)) else {
            return false;
        };
        match self
            .evidence
            .get(index)
            .and_then(|row| row.iter().find(|e| e.field == field))
            .map(|e| e.source)
        {
            Some(EvidenceSource::Owner) => false,
            Some(EvidenceSource::Text) | None => !self.owner_named(selected),
            _ => true,
        }
    }

    fn owner_named(&self, selected: &Account) -> bool {
        // Verify a *model-selected account* against owner evidence. This
        // check never classifies intent or selects an account itself.
        let name = selected.name().to_lowercase();
        let mentions = |s: &str| {
            let text = s.to_lowercase();
            text.match_indices(&name).any(|(i, _)| {
                let touches_word = |a: Option<char>, b: Option<char>| {
                    a.is_some_and(|c| c.is_ascii_alphanumeric())
                        && b.is_some_and(|c| c.is_ascii_alphanumeric())
                };
                !touches_word(text[..i].chars().next_back(), name.chars().next())
                    && !touches_word(
                        name.chars().next_back(),
                        text[i + name.len()..].chars().next(),
                    )
            })
        };
        if mentions(&self.input) {
            return true;
        }
        self.transcript.iter().any(|turn| match turn {
            Turn::Owner { text, .. } => mentions(text),
            Turn::ToolAnswer {
                call_id,
                answers,
                text,
                ..
            } => {
                mentions(text)
                    || answers.iter().any(|answer| {
                        mentions(&answer.text)
                            || self.selected_label(call_id, answer).is_some_and(mentions)
                    })
            }
            _ => false,
        })
    }

    fn selected_label(&self, call_id: &str, answer: &AskAnswer) -> Option<&str> {
        let option_id = answer.option_id.as_ref()?;
        let request = self.transcript.iter().find_map(|turn| match turn {
            Turn::AskUser { request } if request.call_id == call_id => Some(request),
            _ => None,
        })?;
        let question = request
            .questions
            .iter()
            .find(|q| q.id == answer.question_id)?;
        question
            .options
            .iter()
            .find(|o| &o.id == option_id)
            .map(|o| o.label.as_str())
    }
}

pub fn accounts_approved(draft: &Draft) -> bool {
    draft.records.iter().enumerate().all(|(i, _)| {
        ["account", "other_account", "cash"]
            .iter()
            .all(|f| !draft.account_needs_approval(i, f))
    })
}

pub fn attach(draft: &mut Draft, reply: &str, context: &Value) {
    let value = serde_json::from_str::<Value>(reply).unwrap_or_default();
    let has_photos = !draft.image_names().is_empty();
    draft.evidence = draft
        .records
        .iter()
        .enumerate()
        .map(|(i, record)| {
            let mut row: Vec<FieldEvidence> = Vec::new();
            for entry in value["records"][i]["evidence"]
                .as_array()
                .into_iter()
                .flatten()
                .take(16)
            {
                let Ok(mut e) = serde_json::from_value::<FieldEvidence>(entry.clone()) else {
                    continue;
                };
                if !fields(record).contains(&e.field.as_str())
                    || row.iter().any(|a| a.field == e.field)
                {
                    continue;
                }
                let valid = match e.source {
                    EvidenceSource::Owner => false,
                    EvidenceSource::Image => has_photos,
                    EvidenceSource::Favorite => context["favorites"]
                        .as_array()
                        .is_some_and(|rows| !rows.is_empty()),
                    EvidenceSource::History => context["recent_records"]
                        .as_array()
                        .is_some_and(|rows| !rows.is_empty()),
                    EvidenceSource::Text => {
                        account(record, &e.field).is_none_or(|a| draft.owner_named(a))
                    }
                    EvidenceSource::Inferred => true,
                };
                if !valid {
                    e.source = EvidenceSource::Inferred;
                    e.reason.clear();
                }
                e.reason = e
                    .reason
                    .chars()
                    .filter(|c| !c.is_control())
                    .take(240)
                    .collect();
                row.push(e);
            }
            row
        })
        .collect();
}
