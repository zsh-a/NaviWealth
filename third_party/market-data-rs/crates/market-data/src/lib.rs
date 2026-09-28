//! A-share market data. All monetary JSON values are decimal strings.
//! Provider failures, adjustment modes and partial history are explicit.
pub mod cache;
pub mod error;
pub mod model;
pub mod provider;
pub mod service;
pub mod transport;

pub use error::{Error, ErrorKind, Result};
pub use model::*;
pub use provider::{Eastmoney, Provider, Sina, Tencent};
pub use service::{MarketData, MarketDataBuilder, PriorityRouting, ServiceConfig};
