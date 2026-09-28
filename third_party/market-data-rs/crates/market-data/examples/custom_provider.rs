//! Run: cargo run -p market-data-rs --example custom_provider
//! A standalone quote-only provider, with no engine changes or network calls.
use async_trait::async_trait;
use chrono::Utc;
use market_data_rs::{
    provider::{Capabilities, ProviderContext, ProviderInfo, QuoteProvider, QuoteResults},
    *,
};
use rust_decimal::Decimal;

struct MyProvider;
impl Provider for MyProvider {
    fn info(&self) -> ProviderInfo {
        ProviderInfo {
            id: "my-provider".into(),
            capabilities: Capabilities {
                exchanges: vec![Exchange::SSE, Exchange::SZSE],
                quotes: true,
                max_quote_batch: 20,
                daily_adjustments: vec![],
            },
        }
    }
    fn quotes(&self) -> Option<&dyn QuoteProvider> {
        Some(self)
    }
}
#[async_trait]
impl QuoteProvider for MyProvider {
    async fn fetch_quotes(
        &self,
        _context: &ProviderContext,
        symbols: &[Symbol],
    ) -> Result<QuoteResults> {
        // In a real adapter call context.get/send, then parse with strict validation.
        // Do not create another HTTP client or add a nested retry loop.
        Ok(symbols
            .iter()
            .map(|symbol| {
                (
                    symbol.clone(),
                    Ok(Quote {
                        symbol: symbol.clone(),
                        name: "Synthetic example, not a market quote".into(),
                        currency: "CNY".into(),
                        price: Decimal::new(1234, 2),
                        previous_close: Some(Decimal::new(1200, 2)),
                        observed_at: Utc::now(),
                        previous_close_only: false,
                    }),
                )
            })
            .collect())
    }
}
#[tokio::main]
async fn main() -> Result<()> {
    let engine = MarketData::builder().register(MyProvider).build()?;
    let quote = engine
        .quote("600519".parse()?, FetchOptions::default())
        .await?;
    println!("{}", serde_json::to_string_pretty(&quote).unwrap());
    Ok(())
}
