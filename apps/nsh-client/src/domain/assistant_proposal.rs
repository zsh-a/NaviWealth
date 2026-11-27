//! Untrusted assistant record proposals reuse capture's domain parser and editor.
//! The persisted value is parsed again before review; only the owner can approve
//! funding accounts, and opening a proposal never saves a business record.

use super::{
    capture::{self, Draft, Record, Status, Turn},
    capture_evidence::{EvidenceSource, FieldEvidence},
};
use serde_json::{Value, json};

const MAX_BYTES: usize = 80_000;
const MAX_RECORDS: usize = 10;
const INVALID: &str = "invalid record proposal";
const REVIEW_REQUEST: &str = "Review assistant-proposed records";

#[derive(Debug)]
pub struct Proposal {
    pub text: String,
    pub records: Vec<Record>,
}

pub fn schema() -> Value {
    let mut records = capture::schema()["properties"]["records"].clone();
    records["minItems"] = json!(1);
    records["maxItems"] = json!(MAX_RECORDS);
    // Assistant conversations do not attach capture photos. Never let a model
    // refer to an unrelated local image merely by supplying its ordinal.
    records["items"]["properties"]["meal"]["anyOf"][0]["properties"]["source_image"] =
        json!({"type":"null"});
    let fields = &mut records["items"]["properties"];
    fields["money"]["anyOf"][0]["properties"]["amount"]["description"] = json!(
        "Exact major-currency decimal string, at most 2 decimal places: 35 CNY is \"35.00\", never minor units \"3500\". Use null when unknown."
    );
    fields["trade"]["anyOf"][0]["properties"]["quantity"]["description"] = json!(
        "Unscaled share or unit count as an exact decimal string with at most 6 decimal places. One share is \"1\", never the read-tool scaled value \"1000000\". Null for dividends."
    );
    for kind in ["trade", "price"] {
        fields[kind]["anyOf"][0]["properties"]["unit_price"]["description"] = json!(
            "Major-currency price per unscaled share/unit as an exact decimal string with at most 6 decimal places, e.g. \"120.123456\" USD per share. Never scaled integer units."
        );
    }
    for field in ["amount", "fee"] {
        fields["trade"]["anyOf"][0]["properties"][field]["description"] = json!(
            "Exact major-currency decimal string with at most 2 decimal places, e.g. \"12.34\" means 12.34 in the security currency. Never integer minor units. Use null when inapplicable."
        );
    }
    fields["balance"]["anyOf"][0]["properties"]["actual"]["description"] = json!(
        "Displayed balance in major currency as an exact decimal string with at most 2 decimal places, e.g. \"123.45\", never minor units \"12345\". A positive liability balance means debt owed; a negative one means credit."
    );
    json!({"type":"object","additionalProperties":false,
    "required":["text","records"],"properties":{
        "text":{"type":"string","minLength":1,"maxLength":capture::MAX_INPUT,
            "description":"Short description of the records to review; never claim they are saved."},
        "records":records
    }})
}

/// Domain parsing checks semantic validity. This extra boundary rejects fields
/// outside the published tool schema, including fabricated approval/evidence.
/// Nullable omitted payload fields retain capture's backwards-compatible parser.
fn known_fields(value: &Value, schema: &Value) -> bool {
    if value.is_null() {
        return true;
    }
    if let Some(alternatives) = schema["anyOf"].as_array() {
        return alternatives
            .iter()
            .filter(|candidate| candidate["type"] != "null")
            .any(|candidate| known_fields(value, candidate));
    }
    match value {
        Value::Object(fields) => schema["properties"].as_object().is_some_and(|properties| {
            fields.iter().all(|(key, value)| {
                properties
                    .get(key)
                    .is_some_and(|field| known_fields(value, field))
            })
        }),
        Value::Array(items) => items
            .iter()
            .all(|value| known_fields(value, &schema["items"])),
        _ => true,
    }
}

pub fn parse(value: &Value) -> Result<Proposal, String> {
    if value.to_string().len() > MAX_BYTES || !known_fields(value, &schema()) {
        return Err(INVALID.into());
    }
    let text = value["text"]
        .as_str()
        .map(str::trim)
        .filter(|text| {
            !text.is_empty()
                && text.chars().count() <= capture::MAX_INPUT
                && !text
                    .chars()
                    .any(|c| c.is_control() && c != '\n' && c != '\t')
        })
        .ok_or(INVALID)?;
    let (records, questions) =
        capture::parse(&json!({"records":value["records"]}).to_string()).map_err(|_| INVALID)?;
    if records.is_empty()
        || records.len() > MAX_RECORDS
        || !questions.is_empty()
        || !capture::valid_meal_image_numbers(&records, 0)
    {
        return Err(INVALID.into());
    }
    Ok(Proposal {
        text: text.to_owned(),
        records,
    })
}

fn account_evidence(record: &Record) -> Vec<FieldEvidence> {
    let fields = match record {
        Record::Money { draft, .. } => vec![
            ("account", draft.account.is_some()),
            ("other_account", draft.other_account.is_some()),
        ],
        Record::Trade { cash, .. } => vec![("cash", cash.is_some())],
        Record::Balance { .. } => vec![("account", true)],
        _ => Vec::new(),
    };
    fields
        .into_iter()
        .filter(|(_, present)| *present)
        .map(|(field, _)| FieldEvidence {
            field: field.into(),
            source: EvidenceSource::Inferred,
            reason: String::new(),
        })
        .collect()
}

/// Populate a fresh draft only after the owner opens the proposed records.
/// No network or storage is used here. Capture's normal editable review and
/// atomic confirmation remain responsible for the final write and Undo.
pub fn apply(value: &Value, draft: &mut Draft) -> Result<(), String> {
    let proposal = parse(value)?;
    let evidence: Vec<_> = proposal.records.iter().map(account_evidence).collect();
    let mut reply = json!({"records":value["records"],"destination":null});
    for (record, evidence) in reply["records"]
        .as_array_mut()
        .expect("parsed records")
        .iter_mut()
        .zip(&evidence)
    {
        record["evidence"] = json!(evidence);
    }
    // The tool description is model-authored. Never replay it as owner text:
    // a later capture correction verifies selected accounts against owner text.
    draft.input = REVIEW_REQUEST.into();
    draft.correction.clear();
    draft.photo = None;
    draft.attachments.clear();
    draft.answers.clear();
    draft.question.clear();
    draft.transcript = vec![
        Turn::Owner {
            text: REVIEW_REQUEST.into(),
            photo: false,
            images: Vec::new(),
        },
        Turn::Assistant {
            reply: reply.to_string(),
            records: proposal.records.len(),
            questions: Vec::new(),
            provider_output: None,
        },
    ];
    draft.records = proposal.records;
    draft.evidence = evidence;
    draft.status = Status::Ready;
    draft.model = "Assistant".into();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::capture_evidence;

    fn money() -> Value {
        json!({"kind":"money","day":"2026-11-27","money":{
            "kind":"expense","amount":"35.00","currency":"CNY",
            "account":null,"other_account":null,"category":"支出:餐饮",
            "time":null,"payee":"Lunch","note":""}})
    }

    fn proposal(record: Value) -> Value {
        json!({"text":"午餐35元","records":[record]})
    }

    fn draft() -> Draft {
        serde_json::from_value(json!({"id":"capture:proposal","created_at_ms":123,
            "input":"","correction":"","photo":null,"records":[],
            "status":"Editing","model":""}))
        .unwrap()
    }

    #[test]
    fn missing_money_fields_stay_editable_and_exact() {
        let mut value = money();
        for field in ["amount", "account", "category"] {
            value["money"][field] = Value::Null;
        }
        let result = parse(&proposal(value)).unwrap();
        let Record::Money { draft, .. } = &result.records[0] else {
            panic!("money record");
        };
        assert!(draft.valid());
        assert!(draft.amount.is_none());
        assert!(draft.account.is_none());
        assert!(draft.category.is_none());
        assert!(
            account_evidence(&result.records[0]).is_empty(),
            "missing accounts are not inferred values"
        );

        let result = parse(&proposal(money())).unwrap();
        let Record::Money { draft, .. } = &result.records[0] else {
            panic!("money record");
        };
        assert_eq!(draft.amount.as_deref(), Some("35.00"));
        for amount in [json!(35.0), json!("35.005"), json!("-35"), json!("0")] {
            let mut invalid = money();
            invalid["money"]["amount"] = amount;
            assert!(parse(&proposal(invalid)).is_err());
        }
    }

    #[test]
    fn model_text_never_approves_accounts_and_restart_preserves_review() {
        let mut value = proposal(money());
        value["text"] = json!("从资产:现金支付午餐35元");
        value["records"][0]["money"]["account"] = json!("资产:现金");
        let mut draft = draft();
        apply(&value, &mut draft).unwrap();
        assert_eq!(draft.id, "capture:proposal");
        assert_eq!(draft.created_at_ms, 123);
        assert_eq!(draft.status, Status::Ready);
        assert_eq!(draft.transcript.len(), 2);
        assert_eq!(draft.input, REVIEW_REQUEST);
        assert!(draft.account_needs_approval(0, "account", &[]));
        assert!(!capture_evidence::accounts_approved(&draft, &[]));
        let Turn::Assistant { reply, .. } = &draft.transcript[1] else {
            panic!("review reply");
        };
        assert_eq!(capture::parse(reply).unwrap().0, draft.records);
        let restored: Draft = serde_json::from_value(json!(draft)).unwrap();
        assert_eq!(draft, restored);
        // A later recognition reply cannot turn the model-authored account
        // mention in the proposal description into evidence from the owner.
        let mut correction = value.clone();
        correction["records"][0]["evidence"] =
            json!([{"field":"account","source":"text","reason":"named"}]);
        capture_evidence::attach(&mut draft, &correction.to_string(), &json!({}));
        assert!(draft.account_needs_approval(0, "account", &[]));
        draft.mark_owner_field(0, "account");
        assert!(capture_evidence::accounts_approved(&draft, &[]));
    }

    #[test]
    fn rejects_unknown_approvals_photos_duplicates_and_partial_batches() {
        let mut unknown = proposal(money());
        unknown["approved"] = json!(true);
        assert!(parse(&unknown).is_err());
        let mut evidence = proposal(money());
        evidence["records"][0]["evidence"] =
            json!([{"field":"account","source":"owner","reason":"approved"}]);
        assert!(parse(&evidence).is_err());
        let mut nested = proposal(money());
        nested["records"][0]["money"]["approved"] = json!(true);
        assert!(parse(&nested).is_err());
        let meal = json!({"kind":"meal","day":"2026-11-27","slot":"lunch","meal":{
            "source_image":1,"title":"rice","foods":[{"name":"rice","grams":100,
                "catalog_id":null,"confidence":"high",
                "per_100g":{"kcal":100,"protein":2,"carbs":22,"fat":0}}]}});
        assert!(parse(&proposal(meal.clone())).is_err());
        let mut text_meal = meal;
        text_meal["meal"]["source_image"] = Value::Null;
        assert!(parse(&proposal(text_meal)).is_ok());
        assert!(parse(&json!({"text":"repeat","records":[money(),money()]})).is_err());
        let bad = json!({"text":"partial","records":[money(),{
            "kind":"weight","day":"2026-11-27","weight_kg":-1} ]});
        let mut untouched = draft();
        let before = untouched.clone();
        assert!(apply(&bad, &mut untouched).is_err());
        assert_eq!(untouched, before);
    }

    #[test]
    fn rejects_empty_oversized_and_contradictory_proposals() {
        for value in [
            json!({"text":"empty","records":[]}),
            json!({"text":" ","records":[money()]}),
            json!({"text":"x".repeat(capture::MAX_INPUT+1),"records":[money()]}),
            json!({"text":"many","records":vec![money();11]}),
            json!({"text":"control\u{0}","records":[money()]}),
        ] {
            assert!(parse(&value).is_err());
        }
        let mut both = proposal(money());
        both["records"][0]["weight_kg"] = json!(75);
        assert!(parse(&both).is_err());
    }

    #[test]
    fn other_capture_records_keep_exact_values_and_account_review() {
        let value = json!({"text":"Review these records","records":[
            {"kind":"weight","day":"2026-11-27","weight_kg":72.5},
            {"kind":"trade","day":"2026-11-27","trade":{
                "security":"AAPL","currency":"USD","kind":"buy",
                "quantity":"1.000001","unit_price":"120.123456","amount":null,
                "fee":"0.01","cash":"资产/USD:Broker"}},
            {"kind":"balance","day":"2026-11-27","balance":{
                "account":"资产:现金","actual":"123.45"}},
            {"kind":"price","day":"2026-11-27","price":{
                "security":"AAPL","currency":"USD","unit_price":"121.234567"}},
            {"kind":"note","day":"2026-11-27","note":"Walked after lunch"}
        ]});
        let mut draft = draft();
        apply(&value, &mut draft).unwrap();
        assert_eq!(draft.records.len(), 5);
        assert!(matches!(
            draft.records[1],
            Record::Trade {
                quantity: 1_000_001,
                price: 120_123_456,
                fee: 1,
                ..
            }
        ));
        assert!(matches!(
            draft.records[2],
            Record::Balance { actual: 12_345, .. }
        ));
        assert!(matches!(
            draft.records[3],
            Record::Price {
                price: 121_234_567,
                ..
            }
        ));
        assert!(draft.account_needs_approval(1, "cash", &[]));
        assert!(draft.account_needs_approval(2, "account", &[]));
        draft.mark_owner_field(1, "cash");
        draft.mark_owner_field(2, "account");
        assert!(capture_evidence::accounts_approved(&draft, &[]));
    }

    #[test]
    fn tool_schema_distinguishes_proposal_decimals_from_read_tool_units() {
        let schema = schema();
        let fields = &schema["properties"]["records"]["items"]["properties"];
        for (kind, field) in [
            ("money", "amount"),
            ("trade", "amount"),
            ("trade", "fee"),
            ("balance", "actual"),
        ] {
            let description = fields[kind]["anyOf"][0]["properties"][field]["description"]
                .as_str()
                .unwrap();
            assert!(description.contains("major"));
            assert!(description.contains("2 decimal places"));
        }
        for kind in ["trade", "price"] {
            let description = fields[kind]["anyOf"][0]["properties"]["unit_price"]["description"]
                .as_str()
                .unwrap();
            assert!(description.contains("Major-currency"));
            assert!(description.contains("6 decimal places"));
        }
        assert!(
            fields["trade"]["anyOf"][0]["properties"]["quantity"]["description"]
                .as_str()
                .unwrap()
                .contains("Unscaled")
        );
    }
}
