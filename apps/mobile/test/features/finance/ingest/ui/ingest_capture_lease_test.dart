import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_capture_lease.dart';

void main() {
  test('only one capture can hold the lease at a time', () {
    final lease = IngestCaptureLease();

    expect(lease.tryAcquire(), isTrue);
    expect(lease.isHeld, isTrue);
    expect(lease.tryAcquire(), isFalse);

    lease.release();

    expect(lease.isHeld, isFalse);
    expect(lease.tryAcquire(), isTrue);
  });

  test('release is idempotent', () {
    final lease = IngestCaptureLease();

    lease.release();

    expect(lease.isHeld, isFalse);
    expect(lease.tryAcquire(), isTrue);
  });
}
