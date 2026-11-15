//! Strict boundaries for Tencent raw daily bars and dated ECB reference rates.
use crate::{
    catalog::SecurityBinding,
    history::{DailyBar, Error},
    market,
};
use jiff::{Timestamp, civil::Date};
/// Provider request identity. US exchange suffix is resolved from Tencent's own quote.
pub fn request_symbol(b: &SecurityBinding) -> Result<String, Error> {
    b.validate().map_err(|_| Error::Invalid)?;
    match b.market.as_str() {
        "cn_a" => {
            let c = market::canonical_binding(b).ok_or(Error::Invalid)?;
            let (code, ex) = c.split_once('.').ok_or(Error::Invalid)?;
            Ok(format!("{}{code}", ex.to_ascii_lowercase()))
        }
        "hk_stock" => Ok(format!(
            "hk{}",
            market::hong_kong_code(&b.symbol).ok_or(Error::Invalid)?
        )),
        "us_stock" => Ok(format!("us{}", b.symbol)),
        _ => Err(Error::Invalid),
    }
}
pub fn us_request_symbol(b: &SecurityBinding, raw: &str) -> Result<String, Error> {
    market::parse_tencent(b, raw, Timestamp::now())?;
    let fields = raw.trim().split('"').nth(1).ok_or(Error::Invalid)?;
    let id = fields.split('~').nth(2).ok_or(Error::Invalid)?;
    Ok(format!("us{id}"))
}
pub fn tencent(
    b: &SecurityBinding,
    request: &str,
    raw: &str,
    from: Date,
    to: Date,
    now: Timestamp,
) -> Result<Vec<DailyBar>, Error> {
    if raw.len() > 2_000_000 || from > to {
        return Err(Error::Invalid);
    }
    let expected = request_symbol(b)?;
    if request != expected
        && !(b.market == "us_stock"
            && request
                .strip_prefix(&expected)
                .is_some_and(|s| matches!(s, ".OQ" | ".N" | ".A" | ".P")))
    {
        return Err(Error::Invalid);
    }
    let v: serde_json::Value = serde_json::from_str(raw).map_err(|_| Error::Invalid)?;
    if v["code"].as_i64() != Some(0) {
        return Err(Error::Invalid);
    }
    let data = v["data"]
        .as_object()
        .filter(|x| x.len() == 1)
        .and_then(|x| x.get(request))
        .ok_or(Error::Invalid)?;
    if data.get("qfqday").is_some() || data.get("hfqday").is_some() {
        return Err(Error::Invalid);
    }
    let qt = data["qt"][request].as_array().ok_or(Error::Invalid)?;
    let id = qt.get(2).and_then(|x| x.as_str()).ok_or(Error::Invalid)?;
    let request_id = request.get(2..).ok_or(Error::Invalid)?;
    if id != request_id {
        return Err(Error::Invalid);
    }
    let currency_index = match b.market.as_str() {
        "hk_stock" => Some(75),
        "us_stock" => Some(35),
        _ => None,
    };
    if currency_index
        .is_some_and(|i| qt.get(i).and_then(|x| x.as_str()) != Some(b.currency.as_str()))
    {
        return Err(Error::Invalid);
    }
    let rows = data["day"]
        .as_array()
        .filter(|r| r.len() <= 400)
        .ok_or(Error::Invalid)?;
    let mut out = vec![];
    let mut previous = None;
    for row in rows {
        let a = row
            .as_array()
            .filter(|a| a.len() >= 6)
            .ok_or(Error::Invalid)?;
        let day: Date = a[0]
            .as_str()
            .ok_or(Error::Invalid)?
            .parse()
            .map_err(|_| Error::Invalid)?;
        if day < from || day > to || previous.is_some_and(|p| day <= p) {
            return Err(Error::Invalid);
        }
        previous = Some(day);
        let units = |i: usize| {
            crate::holdings::parse_units(a[i].as_str().ok_or(Error::Invalid)?).ok_or(Error::Invalid)
        };
        let volume = units(5)?;
        if volume % 1_000_000 != 0 {
            return Err(Error::Invalid);
        }
        let bar = DailyBar {
            market: b.market.clone(),
            symbol: market::canonical_binding(b).ok_or(Error::Invalid)?,
            currency: b.currency.clone(),
            provider: "tencent:raw".into(),
            day,
            open: units(1)?,
            close: units(2)?,
            high: units(3)?,
            low: units(4)?,
            volume: Some(volume / 1_000_000),
            fetched_at: now,
        };
        bar.validate(b, now)?;
        out.push(bar);
    }
    Ok(out)
}
pub fn fx(
    raw: &str,
    currency: crate::currency::Currency,
    from: Date,
    to: Date,
    today: Date,
) -> Result<Vec<crate::currency::FxRate>, Error> {
    if raw.len() > 200_000 || from > to {
        return Err(Error::Invalid);
    }
    let v: serde_json::Value = serde_json::from_str(raw).map_err(|_| Error::Invalid)?;
    let rows = v
        .as_array()
        .filter(|a| a.len() <= 400)
        .ok_or(Error::Invalid)?;
    let mut out = vec![];
    let mut previous = None;
    for row in rows {
        let rate = market::parse_fx(&serde_json::json!([row]).to_string(), currency, today)?;
        if rate.day < from || rate.day > to || previous.is_some_and(|p| rate.day <= p) {
            return Err(Error::Invalid);
        }
        previous = Some(rate.day);
        out.push(rate);
    }
    Ok(out)
}
