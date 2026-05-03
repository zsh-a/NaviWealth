/// Sampling cadence for dashboard net-worth trend charts.
///
/// The old transaction-replay `NetWorthService` has been removed. Net worth
/// is now derived by feature-specific read models over the forward ledger.
enum NetWorthGranularity { day, week, month }
