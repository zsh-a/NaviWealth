/// Owns the single-capture concurrency invariant for the ingest review UI.
///
/// Capture sources may retain large byte buffers while awaiting a platform
/// picker or camera. Only one source is allowed to hold that memory budget at
/// a time.
class IngestCaptureLease {
  bool _held = false;

  bool get isHeld => _held;

  bool tryAcquire() {
    if (_held) return false;
    _held = true;
    return true;
  }

  void release() {
    _held = false;
  }
}
