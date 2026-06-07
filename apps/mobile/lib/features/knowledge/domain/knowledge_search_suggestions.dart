/// Search suggestion ranking helpers for KnowledgeOS Library.
///
/// Kept out of UI so autocomplete behavior can be tested without widget
/// scaffolding. Callers pass explicit high-signal fields (tags/status/title)
/// and lower-weight searchable body text; the helper handles normalization,
/// prefix/boundary scoring, duplicate boosting, and limiting.
library;

import 'knowledge_text.dart';

const int kKnowledgeSearchSuggestionLimit = 8;

List<String> rankKnowledgeSearchSuggestions({
  required Iterable<String> weightedSuggestions,
  required Iterable<String> searchableTexts,
  required String query,
  int limit = kKnowledgeSearchSuggestionLimit,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final ranked = <String, _RankedSearchSuggestion>{};
  var order = 0;

  void addCandidate(String raw, double sourceWeight) {
    final value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.length < 2) return;
    final key = value.toLowerCase();
    final score = _scoreSuggestion(key, normalizedQuery, sourceWeight);
    if (score == null) return;
    final existing = ranked[key];
    if (existing == null) {
      ranked[key] = _RankedSearchSuggestion(
        value: value,
        firstSeen: order++,
        score: score,
      );
    } else {
      existing.boost(score * 0.35);
    }
  }

  for (final raw in weightedSuggestions) {
    addCandidate(raw, 80);
  }
  for (final text in searchableTexts) {
    for (final raw in knowledgeSearchCandidatePhrases(text)) {
      addCandidate(raw, 12);
    }
  }

  final values = ranked.values.toList(growable: false)
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byFrequency = b.frequency.compareTo(a.frequency);
      if (byFrequency != 0) return byFrequency;
      final byLength = a.value.length.compareTo(b.value.length);
      if (byLength != 0) return byLength;
      return a.firstSeen.compareTo(b.firstSeen);
    });
  return values
      .take(limit)
      .map((candidate) => candidate.value)
      .toList(growable: false);
}

List<String> knowledgeSearchCandidatePhrases(String text) {
  final seen = <String>{};
  final out = <String>[];
  final chunks = text
      .split(RegExp(r'[\n\r。！？!?;；]+'))
      .map((chunk) => chunk.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where((chunk) => chunk.length >= 2);

  for (final chunk in chunks) {
    final phrase = knowledgeExcerpt(
      chunk,
      max: kKnowledgeHeadlineExcerptMaxChars,
    );
    if (seen.add(phrase.toLowerCase())) {
      out.add(phrase);
    }

    for (final token in chunk.split(RegExp(r'[\s,，、/|]+'))) {
      final value = token.trim();
      if (value.length < 3 || value.length > 32) continue;
      if (seen.add(value.toLowerCase())) {
        out.add(value);
      }
    }
  }
  return out;
}

class _RankedSearchSuggestion {
  _RankedSearchSuggestion({
    required this.value,
    required this.firstSeen,
    required this.score,
  });

  final String value;
  final int firstSeen;
  double score;
  int frequency = 1;

  void boost(double amount) {
    frequency += 1;
    score += amount;
  }
}

double? _scoreSuggestion(String value, String query, double sourceWeight) {
  if (query.isEmpty) return sourceWeight;

  final index = value.indexOf(query);
  if (index < 0) return null;
  if (value == query) return sourceWeight + 120;
  if (value.startsWith(query)) return sourceWeight + 90;
  final boundaryMatch =
      index > 0 &&
      RegExp(r'[\s,，、/:：\-_]').hasMatch(value.substring(index - 1, index));
  if (boundaryMatch) return sourceWeight + 64 - index.clamp(0, 32);
  return sourceWeight + 36 - index.clamp(0, 32);
}
