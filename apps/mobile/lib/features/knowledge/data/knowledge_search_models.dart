part of 'knowledge_search_service.dart';

class KnowledgeSearchHit {
  const KnowledgeSearchHit({
    required this.document,
    required this.score,
    required this.semanticScore,
    required this.semanticSim,
    required this.lexicalScore,
    required this.matchedFields,
  });

  final KnowledgeSearchDocument document;
  final double score;
  final double? semanticScore;
  final double? semanticSim;
  final double lexicalScore;
  final List<String> matchedFields;

  String get id => document.id;
  String get kind => document.kind;
  String get title => document.title;
  String get excerpt => document.excerpt;
  String get source => kKnowledgeMemorySources[kind] ?? '';
}

class KnowledgeDecisionSearchHit {
  const KnowledgeDecisionSearchHit({required this.decision, required this.hit});

  final KnowledgeDecision decision;
  final KnowledgeSearchHit hit;
}

class KnowledgeSimilarityHit {
  const KnowledgeSimilarityHit({
    required this.document,
    required this.similarity,
    required this.tokenOverlap,
    required this.source,
  });

  final KnowledgeSearchDocument document;
  final double similarity;
  final double tokenOverlap;
  final String source;

  String get id => document.id;
  String get kind => document.kind;
  String get title => document.title;
}

class KnowledgeSearchDocument {
  KnowledgeSearchDocument._({
    required this.kind,
    required this.id,
    required this.title,
    required String excerptSource,
    required this.searchText,
    required this.updatedAt,
    this.note,
    this.decision,
  }) : _excerptSource = excerptSource;

  final String kind;
  final String id;
  final String title;
  final String _excerptSource;
  // Ranking scans canonical rows, but only visible hits need Markdown cleanup.
  late final String excerpt = _excerpt(_excerptSource);
  final String searchText;
  final DateTime updatedAt;
  final KnowledgeNote? note;
  final KnowledgeDecision? decision;

  static KnowledgeSearchDocument fromNote(
    KnowledgeNote n, {
    String untitled = 'Untitled',
  }) {
    final title = n.title.isEmpty ? untitled : n.title;
    return KnowledgeSearchDocument._(
      kind: 'note',
      id: n.id,
      title: title,
      excerptSource: n.bodyMd.isEmpty ? title : n.bodyMd,
      searchText:
          '$title ${n.bodyMd} ${n.tags.join(' ')} '
          '${n.sourceUrl ?? ''}',
      updatedAt: n.sync.updatedAt,
      note: n,
    );
  }

  static KnowledgeSearchDocument fromDecision(KnowledgeDecision d) {
    return KnowledgeSearchDocument._(
      kind: 'decision',
      id: d.id,
      title: d.question,
      excerptSource: d.rationaleMd.isEmpty ? d.selectedLabel : d.rationaleMd,
      searchText:
          '${d.question} ${d.selectedLabel} ${d.rationaleMd} '
          '${d.expectedOutcome ?? ''} ${d.actualOutcomeMd ?? ''} '
          '${d.status.wire}',
      updatedAt: d.sync.updatedAt,
      decision: d,
    );
  }
}

class KnowledgeLexicalMatch {
  const KnowledgeLexicalMatch({
    required this.score,
    required this.matchedFields,
  });

  final double score;
  final List<String> matchedFields;

  static KnowledgeLexicalMatch calculate(
    String query,
    KnowledgeSearchDocument doc, {
    Set<String>? queryTokens,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const KnowledgeLexicalMatch(score: 0, matchedFields: <String>[]);
    }

    final title = doc.title.toLowerCase();
    final body = doc.searchText.toLowerCase();
    final fields = <String>[];
    var score = 0.0;

    if (title == q) {
      score = 1.0;
      fields.add('title_exact');
    } else if (title.startsWith(q)) {
      score = 0.9;
      fields.add('title_prefix');
    } else if (title.contains(q)) {
      score = 0.75;
      fields.add('title');
    }

    if (body.contains(q)) {
      score = score < 0.55 ? 0.55 : score;
      fields.add('body');
    }

    final tokens = queryTokens ?? _tokenize(q);
    final titleOverlap = _jaccard(tokens, _tokenize(title));
    final bodyOverlap = _jaccard(tokens, _tokenize(body));
    if (titleOverlap > 0) fields.add('title_tokens');
    if (bodyOverlap > 0) fields.add('body_tokens');
    final overlapScore = (titleOverlap * 0.85 + bodyOverlap * 0.55)
        .clamp(0.0, 1.0)
        .toDouble();
    if (overlapScore > score) score = overlapScore;

    return KnowledgeLexicalMatch(
      score: score.clamp(0.0, 1.0).toDouble(),
      matchedFields: fields.toSet().toList(growable: false),
    );
  }
}

String _excerpt(String s, [int n = kKnowledgeSupportingExcerptMaxChars]) =>
    knowledgeExcerpt(s, max: n);

final _wordSeparator = RegExp(r'[^a-z0-9一-鿿]+');
final _cjkWord = RegExp(r'[一-鿿]');

Set<String> _tokenize(String s) {
  final lower = s.toLowerCase();
  final tokens = <String>{};
  final seen = <String>{};
  for (final word in lower.split(_wordSeparator)) {
    if (word.isEmpty || !seen.add(word)) continue;
    if (_cjkWord.hasMatch(word)) {
      if (word.length == 1) {
        tokens.add(word);
      } else {
        for (var i = 0; i < word.length - 1; i++) {
          tokens.add(word.substring(i, i + 2));
        }
      }
    } else {
      tokens.add(word);
    }
  }
  return tokens;
}

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final smaller = a.length <= b.length ? a : b;
  final larger = identical(smaller, a) ? b : a;
  var inter = 0;
  for (final token in smaller) {
    if (larger.contains(token)) inter++;
  }
  if (inter == 0) return 0;
  return inter / (a.length + b.length - inter);
}
