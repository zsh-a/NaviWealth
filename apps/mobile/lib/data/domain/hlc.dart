/// Hybrid Logical Clock timestamp.
///
/// Local devices may have skewed wall clocks; HLC pairs the wall time with a
/// monotonically-increasing logical counter so two events still get a stable
/// total order even when one device's clock drifts backwards. The total order
/// is `(wallMillis, counter, nodeId)` lexicographically — `nodeId` is only the
/// final tie-breaker and never affects causality.
///
/// Wire format: `<wallMillis>:<counter>-<nodeId>`. The counter is base-10 to
/// keep logs grep-able; we don't gain anything by hex-encoding it.
class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.wallMillis,
    required this.counter,
    required this.nodeId,
  });

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
    return Hlc(
      wallMillis: lastSeen.wallMillis,
      counter: lastSeen.counter + 1,
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

    return Hlc(wallMillis: maxWall, counter: nextCounter, nodeId: nodeId);
  }

  /// Parse the wire format `<wallMillis>:<counter>-<nodeId>`. Throws
  /// [FormatException] on malformed input — callers should treat this as a
  /// non-recoverable corruption signal.
  factory Hlc.parse(String packed) {
    final colon = packed.indexOf(':');
    final dash = packed.indexOf('-', colon + 1);
    if (colon < 1 || dash < 0) {
      throw FormatException('Malformed HLC: $packed');
    }
    final wall = int.parse(packed.substring(0, colon));
    final counter = int.parse(packed.substring(colon + 1, dash));
    final node = packed.substring(dash + 1);
    if (node.isEmpty) {
      throw FormatException('Malformed HLC (missing nodeId): $packed');
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
  String toString() => '$wallMillis:$counter-$nodeId';
}
