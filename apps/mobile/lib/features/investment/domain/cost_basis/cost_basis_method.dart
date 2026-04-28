/// Strategy used to determine which lot is consumed when a position is sold.
///
/// - [fifo]: First-In-First-Out — the oldest lot is consumed first. Default in
///   most jurisdictions and what the IRS assumes for U.S. equities.
/// - [lifo]: Last-In-First-Out — the newest lot is consumed first.
/// - [average]: Weighted-average cost across all open lots; consumption is
///   distributed proportionally so each lot's history is preserved.
enum CostBasisMethod { fifo, lifo, average }
