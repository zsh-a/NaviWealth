//! Provider extension contract. Providers own protocol mapping, not retries or caching.
use crate::{
    model::{china_time, decimal},
    transport::HttpClient,
    *,
};
use async_trait::async_trait;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, sync::Arc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capabilities {
    pub exchanges: Vec<Exchange>,
    pub quotes: bool,
    pub max_quote_batch: usize,
    /// Empty = no daily history. Unsupported adjustment is never silently substituted.
    pub daily_adjustments: Vec<Adjustment>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderInfo {
    pub id: String,
    pub capabilities: Capabilities,
}

#[derive(Clone)]
pub struct ProviderContext {
    pub http: Arc<HttpClient>,
    pub quota_key: String,
}
impl ProviderContext {
    pub async fn send(&self, request: &crate::transport::HttpRequest) -> Result<Vec<u8>> {
        self.http.send(&self.quota_key, request).await
    }
    pub async fn get(
        &self,
        url: &str,
        params: &[(&str, String)],
        headers: &[(&str, &str)],
    ) -> Result<Vec<u8>> {
        self.http.get(&self.quota_key, url, params, headers).await
    }
}

pub type QuoteResults = HashMap<Symbol, Result<Quote>>;

#[async_trait]
pub trait QuoteProvider: Send + Sync {
    /// Missing symbols are normalized by the engine into per-symbol NoData failures.
    async fn fetch_quotes(
        &self,
        context: &ProviderContext,
        symbols: &[Symbol],
    ) -> Result<QuoteResults>;
}
#[async_trait]
pub trait HistoryProvider: Send + Sync {
    async fn fetch_daily(
        &self,
        context: &ProviderContext,
        request: &HistoryRequest,
    ) -> Result<HistoryPage>;
}
pub trait Provider: Send + Sync {
    fn info(&self) -> ProviderInfo;
    fn quotes(&self) -> Option<&dyn QuoteProvider> {
        None
    }
    fn history(&self) -> Option<&dyn HistoryProvider> {
        None
    }
}

fn capabilities(quotes: bool, adjusted: bool) -> Capabilities {
    Capabilities {
        exchanges: vec![Exchange::SSE, Exchange::SZSE, Exchange::BSE],
        quotes,
        max_quote_batch: if quotes { 50 } else { 0 },
        daily_adjustments: if adjusted {
            vec![Adjustment::Raw, Adjustment::Forward, Adjustment::Backward]
        } else {
            vec![Adjustment::Raw]
        },
    }
}

/// Public quote and fqkline endpoints. No authentication or service SLA.
#[derive(Default)]
pub struct Tencent;
impl Provider for Tencent {
    fn info(&self) -> ProviderInfo {
        ProviderInfo {
            id: "tencent".into(),
            capabilities: capabilities(true, true),
        }
    }
    fn quotes(&self) -> Option<&dyn QuoteProvider> {
        Some(self)
    }
    fn history(&self) -> Option<&dyn HistoryProvider> {
        Some(self)
    }
}
#[async_trait]
impl QuoteProvider for Tencent {
    async fn fetch_quotes(
        &self,
        ctx: &ProviderContext,
        symbols: &[Symbol],
    ) -> Result<QuoteResults> {
        let list = symbols
            .iter()
            .map(Symbol::wire_code)
            .collect::<Vec<_>>()
            .join(",");
        let bytes = ctx.get("https://qt.gtimg.cn/", &[("q", list)], &[]).await?;
        parse_quotes(&bytes, symbols, false)
    }
}
#[async_trait]
impl HistoryProvider for Tencent {
    async fn fetch_daily(
        &self,
        ctx: &ProviderContext,
        req: &HistoryRequest,
    ) -> Result<HistoryPage> {
        let adjust = match req.adjustment {
            Adjustment::Raw => "",
            Adjustment::Forward => "qfq",
            Adjustment::Backward => "hfq",
        };
        let key = format!("{adjust}day");
        let symbol = req.symbol.wire_code();
        let mut end = req.to;
        let mut rows = Vec::new();
        // Bound work independently of caller deadline. Every page consumes the same quota.
        for _ in 0..64 {
            let param = format!("{symbol},day,{},{end},640,{adjust}", req.from);
            let bytes = ctx
                .get(
                    "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get",
                    &[("param", param)],
                    &[],
                )
                .await?;
            let root: Value = json(&bytes)?;
            if root.get("code").and_then(Value::as_i64) != Some(0) {
                return Err(parse_error("Tencent returned an error envelope"));
            }
            let node = &root["data"][&symbol];
            // Deliberately no qfq/hfq -> raw fallback.
            let raw = node[&key].as_array().ok_or_else(|| {
                Error::new(
                    ErrorKind::NoData,
                    "requested Tencent adjustment series is absent",
                )
            })?;
            if raw.is_empty() {
                break;
            }
            let mut page = Vec::new();
            for row in raw {
                let f = row
                    .as_array()
                    .ok_or_else(|| parse_error("invalid Tencent daily row"))?;
                if f.len() < 6 {
                    return Err(parse_error("truncated Tencent daily row"));
                }
                page.push(Bar {
                    date: date(text(&f[0])?)?,
                    open: number(&f[1])?,
                    close: number(&f[2])?,
                    high: number(&f[3])?,
                    low: number(&f[4])?,
                    volume_shares: number(&f[5])? * Decimal::from(100),
                });
            }
            page.sort_by_key(|b| b.date);
            let earliest = page[0].date;
            rows.extend(page);
            if raw.len() < 640 || earliest <= req.from {
                break;
            }
            let next = earliest
                .pred_opt()
                .ok_or_else(|| parse_error("date underflow"))?;
            if next >= end {
                return Err(parse_error("Tencent pagination made no progress"));
            }
            end = next;
        }
        Ok(HistoryPage {
            symbol: req.symbol.clone(),
            adjustment: req.adjustment,
            bars: rows,
            warnings: vec![],
        })
    }
}

#[derive(Default)]
pub struct Sina;
impl Provider for Sina {
    fn info(&self) -> ProviderInfo {
        ProviderInfo {
            id: "sina".into(),
            capabilities: capabilities(true, false),
        }
    }
    fn quotes(&self) -> Option<&dyn QuoteProvider> {
        Some(self)
    }
    fn history(&self) -> Option<&dyn HistoryProvider> {
        Some(self)
    }
}
#[async_trait]
impl QuoteProvider for Sina {
    async fn fetch_quotes(
        &self,
        ctx: &ProviderContext,
        symbols: &[Symbol],
    ) -> Result<QuoteResults> {
        let list = symbols
            .iter()
            .map(Symbol::wire_code)
            .collect::<Vec<_>>()
            .join(",");
        let bytes = ctx
            .get(
                &format!("https://hq.sinajs.cn/list={list}"),
                &[],
                &[
                    ("Referer", "https://finance.sina.com.cn/"),
                    ("User-Agent", "Mozilla/5.0"),
                ],
            )
            .await?;
        parse_quotes(&bytes, symbols, true)
    }
}
#[async_trait]
impl HistoryProvider for Sina {
    async fn fetch_daily(
        &self,
        ctx: &ProviderContext,
        req: &HistoryRequest,
    ) -> Result<HistoryPage> {
        if req.adjustment != Adjustment::Raw {
            return Err(Error::new(
                ErrorKind::Unsupported,
                "Sina daily endpoint is unadjusted only",
            ));
        }
        // The live endpoint returns JSON null for datalen=10000. Request only
        // the trailing window needed, capped at the verified 1023-bar limit.
        let today = chrono::Utc::now()
            .with_timezone(&chrono::FixedOffset::east_opt(8 * 3600).unwrap())
            .date_naive();
        let count = ((today - req.from).num_days() + 8).clamp(1, 1023);
        let bytes = ctx
            .get(
                "https://quotes.sina.cn/cn/api/json_v2.php/CN_MarketDataService.getKLineData",
                &[
                    ("symbol", req.symbol.wire_code()),
                    ("scale", "240".into()),
                    ("ma", "no".into()),
                    ("datalen", count.to_string()),
                ],
                &[("Referer", "https://finance.sina.com.cn/")],
            )
            .await?;
        let root: Value = json(&bytes)?;
        let rows = root
            .as_array()
            .ok_or_else(|| Error::new(ErrorKind::NoData, "Sina returned no daily series"))?;
        let mut bars = Vec::new();
        for row in rows {
            bars.push(Bar {
                date: date(text(&row["day"])?)?,
                open: number(&row["open"])?,
                high: number(&row["high"])?,
                low: number(&row["low"])?,
                close: number(&row["close"])?,
                volume_shares: number(&row["volume"])?,
            });
        }
        Ok(HistoryPage {
            symbol: req.symbol.clone(),
            adjustment: Adjustment::Raw,
            bars,
            warnings: vec![
                "Sina returns at most 1023 trailing daily bars; older coverage may be unavailable"
                    .into(),
            ],
        })
    }
}

#[derive(Default)]
pub struct Eastmoney;
impl Provider for Eastmoney {
    fn info(&self) -> ProviderInfo {
        ProviderInfo {
            id: "eastmoney".into(),
            capabilities: capabilities(false, true),
        }
    }
    fn history(&self) -> Option<&dyn HistoryProvider> {
        Some(self)
    }
}
#[async_trait]
impl HistoryProvider for Eastmoney {
    async fn fetch_daily(
        &self,
        ctx: &ProviderContext,
        req: &HistoryRequest,
    ) -> Result<HistoryPage> {
        let bytes = ctx
            .get(
                "https://push2his.eastmoney.com/api/qt/stock/kline/get",
                &[
                    ("secid", req.symbol.eastmoney_id()),
                    ("klt", "101".into()),
                    (
                        "fqt",
                        match req.adjustment {
                            Adjustment::Raw => "0",
                            Adjustment::Forward => "1",
                            Adjustment::Backward => "2",
                        }
                        .into(),
                    ),
                    ("beg", req.from.format("%Y%m%d").to_string()),
                    ("end", req.to.format("%Y%m%d").to_string()),
                    ("lmt", "30000".into()),
                    ("fields1", "f1,f2,f3,f4,f5,f6".into()),
                    (
                        "fields2",
                        "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61".into(),
                    ),
                ],
                &[
                    ("Referer", "https://quote.eastmoney.com/"),
                    ("User-Agent", "Mozilla/5.0"),
                ],
            )
            .await?;
        parse_eastmoney(&bytes, req)
    }
}

fn parse_eastmoney(bytes: &[u8], req: &HistoryRequest) -> Result<HistoryPage> {
    let root: Value = json(bytes)?;
    if root["rc"].as_i64() != Some(0) {
        return Err(parse_error("Eastmoney returned an error envelope"));
    }
    let data = &root["data"];
    if data.is_null() {
        return Err(Error::new(
            ErrorKind::NoData,
            "Eastmoney returned no security",
        ));
    }
    if data["code"].as_str() != Some(req.symbol.code()) {
        return Err(parse_error("Eastmoney security mismatch"));
    }
    let expected_market = if req.symbol.exchange() == Exchange::SSE {
        1
    } else {
        0
    };
    if data["market"].as_i64() != Some(expected_market) {
        return Err(parse_error("Eastmoney exchange mismatch"));
    }
    let rows = data["klines"]
        .as_array()
        .ok_or_else(|| parse_error("missing Eastmoney klines"))?;
    let mut bars = Vec::new();
    for row in rows {
        let f: Vec<_> = text(row)?.split(',').collect();
        if f.len() < 6 {
            return Err(parse_error("truncated Eastmoney daily row"));
        }
        bars.push(Bar {
            date: date(f[0])?,
            open: decimal(f[1])?,
            close: decimal(f[2])?,
            high: decimal(f[3])?,
            low: decimal(f[4])?,
            volume_shares: decimal(f[5])? * Decimal::from(100),
        });
    }
    Ok(HistoryPage {
        symbol: req.symbol.clone(),
        adjustment: req.adjustment,
        bars,
        warnings: vec![],
    })
}

fn parse_quotes(bytes: &[u8], symbols: &[Symbol], sina: bool) -> Result<QuoteResults> {
    let (text, _, invalid) = encoding_rs::GBK.decode(bytes);
    if invalid {
        return Err(parse_error("invalid quote text encoding"));
    }
    let prefix = if sina { "var hq_str_" } else { "v_" };
    let mut result = HashMap::new();
    for line in text.split(';') {
        let Some((key, payload)) = line.trim().split_once('=') else {
            continue;
        };
        let Some(key) = key.strip_prefix(prefix) else {
            continue;
        };
        let Some(symbol) = symbols.iter().find(|s| s.wire_code() == key) else {
            continue;
        };
        let parsed = (|| {
            let payload = payload
                .trim()
                .strip_prefix('"')
                .and_then(|s| s.strip_suffix('"'))
                .ok_or_else(|| parse_error("malformed quote line"))?;
            if payload.is_empty() {
                return Err(Error::new(ErrorKind::NoData, "empty quote"));
            }
            let f: Vec<_> = payload.split(if sina { ',' } else { '~' }).collect();
            if f.len() < if sina { 32 } else { 31 } {
                return Err(parse_error("truncated quote"));
            }
            if !sina && f[2] != symbol.code() {
                return Err(parse_error("Tencent security mismatch"));
            }
            let price = decimal(f[3])?;
            let previous_close = decimal(f[if sina { 2 } else { 4 }])?;
            if previous_close < Decimal::ZERO {
                return Err(parse_error("negative previous close"));
            }
            let observed_at = if sina {
                china_time(&format!("{} {}", f[30], f[31]), "%Y-%m-%d %H:%M:%S")?
            } else {
                china_time(f[30], "%Y%m%d%H%M%S")?
            };
            let quote = Quote {
                symbol: symbol.clone(),
                name: f[usize::from(!sina)].into(),
                currency: "CNY".into(),
                price: if price.is_zero() {
                    previous_close
                } else {
                    price
                },
                previous_close: (previous_close > Decimal::ZERO).then_some(previous_close),
                observed_at,
                previous_close_only: price.is_zero(),
            };
            quote.validate(symbol)?;
            Ok(quote)
        })();
        result.insert(symbol.clone(), parsed);
    }
    Ok(result)
}
fn json(bytes: &[u8]) -> Result<Value> {
    serde_json::from_slice(bytes).map_err(|_| parse_error("malformed upstream JSON"))
}
fn parse_error(message: &str) -> Error {
    Error::new(ErrorKind::Parse, message)
}
fn text(value: &Value) -> Result<&str> {
    value
        .as_str()
        .ok_or_else(|| parse_error("expected string field"))
}
fn number(value: &Value) -> Result<Decimal> {
    match value {
        Value::String(s) => decimal(s),
        Value::Number(n) => decimal(&n.to_string()),
        _ => Err(parse_error("missing numeric field")),
    }
}
fn date(s: &str) -> Result<NaiveDate> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| parse_error("invalid trading date"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn quote_parser_preserves_identity_and_china_time() {
        let symbol: Symbol = "600519".parse().unwrap();
        let mut f = vec!["0"; 32];
        f[0] = "STOCK";
        f[2] = "10";
        f[3] = "12.30";
        f[30] = "2026-01-05";
        f[31] = "15:00:00";
        let raw = format!("var hq_str_sh600519=\"{}\";", f.join(","));
        let quote = parse_quotes(raw.as_bytes(), std::slice::from_ref(&symbol), true)
            .unwrap()
            .remove(&symbol)
            .unwrap()
            .unwrap();
        assert_eq!(quote.symbol.to_string(), "600519.SH");
        assert_eq!(quote.observed_at.to_rfc3339(), "2026-01-05T07:00:00+00:00");
        assert_eq!(quote.price, Decimal::new(1230, 2));
    }
    #[test]
    fn malformed_quote_does_not_become_zero_price() {
        let symbol: Symbol = "600519".parse().unwrap();
        let raw = b"v_sh600519=\"1~name~600519~garbage\";";
        assert!(parse_quotes(raw, std::slice::from_ref(&symbol), false).unwrap()[&symbol].is_err());
    }
    #[test]
    fn eastmoney_converts_lots_to_shares() {
        let req = HistoryRequest {
            symbol: "600519".parse().unwrap(),
            from: date("2026-01-05").unwrap(),
            to: date("2026-01-05").unwrap(),
            adjustment: Adjustment::Raw,
            allow_partial: false,
        };
        let raw = br#"{"rc":0,"data":{"code":"600519","market":1,"klines":["2026-01-05,10,11,12,9,123.45"]}}"#;
        let page = parse_eastmoney(raw, &req).unwrap();
        assert_eq!(page.bars[0].volume_shares, Decimal::from(12345));
    }

    #[test]
    fn tencent_decodes_gbk_and_preserves_missing_previous_close() {
        let symbol: Symbol = "600519".parse().unwrap();
        let mut fields = vec!["0"; 31];
        fields[1] = "贵州茅台";
        fields[2] = "600519";
        fields[3] = "1234.56";
        fields[30] = "20260105150000";
        let line = format!("v_sh600519=\"{}\";", fields.join("~"));
        let (bytes, _, _) = encoding_rs::GBK.encode(&line);
        let quote = parse_quotes(&bytes, std::slice::from_ref(&symbol), false)
            .unwrap()
            .remove(&symbol)
            .unwrap()
            .unwrap();
        assert_eq!(quote.name, "贵州茅台");
        assert_eq!(quote.previous_close, None);
        assert_eq!(quote.observed_at.to_rfc3339(), "2026-01-05T07:00:00+00:00");
    }
}
