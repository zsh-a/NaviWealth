# Structured Logging

NaviWealth uses `AppLogger` as the only business logging seam. Feature code
must emit structured diagnostic events or timed operations instead of building
free-form strings. Talker remains the local viewer/history sink; warning and
error events also follow the user-gated crash-reporting pipeline.

## Event contract

Event names use lowercase dot notation:

```text
<domain>.<operation>.<state>
finance.trade.submit.started
finance.trade.submit.stage.completed
core.sync.cycle.failed
```

Start a correlated operation at the application/UI orchestration boundary:

```dart
final operation = logger.startOperation(
  'finance.trade.submit',
  fields: {
    'trade_type': type,
    'asset_type': assetType,
    'has_price': price != null,
  },
);

final result = await operation.step('prepare', prepare);
operation.complete();
```

`AppLogOperation.step` uses a monotonic stopwatch, emits start/completion
events, and emits a warning while a stage is still running past its threshold.
Call exactly one of `complete`, `fail`, or `cancel`; duplicate terminal calls
are ignored.

## Privacy rules

The logger accepts only scalar fields whose keys match the diagnostic field
policy. Unsafe fields are dropped before reaching Talker or crash reporting.

Never log:

- user, device, account, transaction, or row identifiers;
- symbols, security/account names, notes, narration, or payees;
- quantities, prices, amounts, fees, balances, or tax values;
- tokens, request bodies, SQL, payloads, or arbitrary domain objects.

Safe examples include operation/stage/outcome, duration, counts, enum types,
booleans, provider/endpoint names, error codes, and retryability. The generated
`operation_id` is diagnostic-only and must not be replaced by a business ID.

Errors emitted through `AppLogger.event` are converted to `DiagnosticLogError`;
their original message is never stored or uploaded. Stack traces may be kept
because they contain code locations rather than business values.

## Levels

- `debug`: stage start/completion and fine-grained timings;
- `info`: operation start and successful terminal events;
- `warning`: slow stages and recoverable stage failures;
- `error`: one terminal operation failure.

Development retains all levels, staging retains info and above, and production
retains warning/error events. A slow-stage warning ensures a genuinely stuck
future remains diagnosable in production.

## Placement

- Start operations in application services or UI orchestration boundaries.
- Use the shared `FormSubmission` seam for form commits and Undo; do not add a
  second form-specific logger.
- Repositories may expose timed stages through a caller-owned operation, but
  must not create unrelated operations or log row contents.
- Domain calculations remain logger-free.
- Durable database commits may emit slow warnings but must not be abandoned by
  a generic timeout: the write may still succeed and a retry could duplicate it.

Riverpod's container-level automatic retry is disabled in production. A failed
async provider must expose its error; retry belongs to the owning workflow
(user Retry, sync backoff, or a provider-specific policy). Otherwise callers of
`.future` can remain loading while the framework silently rebuilds the provider.

## Export and tests

Copy/share runs all history through `sanitizeDiagnosticExport` as a second
defense for legacy free-form logs. New code must still be safe before export.

Tests for a new operation should verify event order, one terminal event, slow
or timeout behavior, and absence of representative private values. Logging
failures must never change the business result.
