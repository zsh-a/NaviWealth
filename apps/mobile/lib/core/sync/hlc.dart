/// Hybrid Logical Clock timestamp.
///
/// Pairs the wall time with a monotonically-increasing logical counter so two
/// events still get a stable total order even when one device's clock drifts
/// backwards. The total order is `(wallMillis, counter, nodeId)`
/// lexicographically — `nodeId` is only the final tie-breaker and never
/// affects causality.
///
/// **Canonical string form:** `<wallMillis>.<counter:%04x>-<nodeId>`. The dot
/// separator and zero-padded hex counter make it sort lexicographically the
/// same as the `(wallMillis, counter, nodeId)` tuple — which is why sync v3
/// uses this string directly as the opaque, ordered `version` token
/// (`docs/sync/sync-v3.md`).
class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.wallMillis,
    required this.counter,
    required this.nodeId,
  });

  /// Logical counter is u16; overflow bumps `wallMillis`.
  static const int counterMax = 0xFFFF;

  /// Local wall-clock reading (milliseconds since Unix epoch) at the moment
  /// the event was generated *or* observed — whichever is later. This is
  /// what makes HLC robust to backward jumps: a remote event with a higher
  /// wall time bumps every subsequent local event past it.
  final int wallMillis;

  /// Logical counter. Resets to 0 each time `wallMillis` increases; otherwise
  /// increments to disambiguate events within the same millisecond.
  final int counter;

  /// Stable per-device identifier (the [Device.id]). Acts only as a
  /// tie-breaker in [compareTo] and is never used for causality reasoning.
  final String nodeId;

  /// Initial HLC for a node with no prior history.
  factory Hlc.zero(String nodeId) =>
      Hlc(wallMillis: 0, counter: 0, nodeId: nodeId);

  /// Generate the next local HLC tick for a new event on this node.
  ///
  /// `lastSeen` is the most recent HLC observed locally (whether generated
  /// or received). Pass `now` (defaulting to the wall clock) for testability.
  factory Hlc.tick({required Hlc lastSeen, int? nowMillis}) {
    final wall = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    if (wall > lastSeen.wallMillis) {
      return Hlc(wallMillis: wall, counter: 0, nodeId: lastSeen.nodeId);
    }
    final nextCounter = lastSeen.counter + 1;
    if (nextCounter > counterMax) {
      return Hlc(
        wallMillis: lastSeen.wallMillis + 1,
        counter: 0,
        nodeId: lastSeen.nodeId,
      );
    }
    return Hlc(
      wallMillis: lastSeen.wallMillis,
      counter: nextCounter,
      nodeId: lastSeen.nodeId,
    );
  }

  /// Merge a remote HLC into the local clock when receiving an event.
  ///
  /// Returns the new local clock value. Per the HLC paper:
  ///   - If wall clock leads both, take wall + counter 0.
  ///   - If local leads, bump local counter.
  ///   - If remote leads, take remote wall + counter+1.
  ///   - If they tie on wall, take max(counter)+1.
  Hlc merge(Hlc remote, {int? nowMillis}) {
    final wall = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final maxWall = [
      wall,
      wallMillis,
      remote.wallMillis,
    ].reduce((a, b) => a > b ? a : b);

    int nextCounter;
    if (maxWall == wallMillis && maxWall == remote.wallMillis) {
      nextCounter = (counter > remote.counter ? counter : remote.counter) + 1;
    } else if (maxWall == wallMillis) {
      nextCounter = counter + 1;
    } else if (maxWall == remote.wallMillis) {
      nextCounter = remote.counter + 1;
    } else {
      nextCounter = 0;
    }

    if (nextCounter > counterMax) {
      return Hlc(wallMillis: maxWall + 1, counter: 0, nodeId: nodeId);
    }
    return Hlc(wallMillis: maxWall, counter: nextCounter, nodeId: nodeId);
  }

  /// Parse the canonical string form `<wallMillis>.<counter:%04x>-<nodeId>`.
  /// Throws [FormatException] on malformed input — callers should treat this
  /// as a non-recoverable corruption signal.
  factory Hlc.parse(String packed) {
    final dot = packed.indexOf('.');
    final dash = dot < 0 ? -1 : packed.indexOf('-', dot + 1);
    if (dot < 1 || dash < 0) {
      throw FormatException('Malformed HLC: $packed');
    }
    final wallStr = packed.substring(0, dot);
    final counterStr = packed.substring(dot + 1, dash);
    final node = packed.substring(dash + 1);
    if (node.isEmpty) {
      throw FormatException('Malformed HLC (missing nodeId): $packed');
    }
    final wall = int.tryParse(wallStr);
    if (wall == null || wall < 0) {
      throw FormatException('Malformed HLC wall: $packed');
    }
    if (counterStr.length != 4) {
      throw FormatException('Malformed HLC counter (expect 4 hex): $packed');
    }
    final counter = int.tryParse(counterStr, radix: 16);
    if (counter == null || counter < 0 || counter > counterMax) {
      throw FormatException('Malformed HLC counter: $packed');
    }
    return Hlc(wallMillis: wall, counter: counter, nodeId: node);
  }

  /// Wall-clock view, useful for debugging.
  DateTime get wallTime =>
      DateTime.fromMillisecondsSinceEpoch(wallMillis, isUtc: true);

  @override
  int compareTo(Hlc other) {
    final byWall = wallMillis.compareTo(other.wallMillis);
    if (byWall != 0) return byWall;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMillis == wallMillis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(wallMillis, counter, nodeId);

  @override
  String toString() {
    final hex = counter.toRadixString(16).padLeft(4, '0');
    return '$wallMillis.$hex-$nodeId';
  }
}
