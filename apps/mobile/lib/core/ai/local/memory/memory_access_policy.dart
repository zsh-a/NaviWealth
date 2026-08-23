/// Active-domain access policy for all AI-facing Memory Runtime reads.
///
/// Direct user-owned management surfaces may inspect local rows outside this
/// policy. AI context assembly, read tools, and AI-proposed mutations must all
/// use it so an inactive domain cannot be reached through a different path.
library;

class MemoryAccessPolicy {
  const MemoryAccessPolicy._(this.sourcePrefixes);

  const MemoryAccessPolicy.denyAll() : this._(const <String>{});

  factory MemoryAccessPolicy.allowPrefixes(Iterable<String> prefixes) {
    return MemoryAccessPolicy._(
      Set<String>.unmodifiable(
        prefixes
            .map((prefix) => prefix.trim())
            .where((prefix) => prefix.isNotEmpty),
      ),
    );
  }

  final Set<String> sourcePrefixes;

  bool get isEmpty => sourcePrefixes.isEmpty;

  bool allowsSource(String? source) {
    final normalized = source?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    return sourcePrefixes.any(normalized.startsWith);
  }
}
