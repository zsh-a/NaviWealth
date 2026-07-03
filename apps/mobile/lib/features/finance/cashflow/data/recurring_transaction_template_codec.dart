part of 'recurring_transaction_repository.dart';

class JournalBuildTemplate {
  const JournalBuildTemplate({required this.entry, required this.postings});

  final JournalEntryDraft entry;
  final List<PostingDraft> postings;

  JournalEntryDraft entryForOccurrence(DateTime occurrence, {String? id}) {
    final date = DateTime.utc(
      occurrence.year,
      occurrence.month,
      occurrence.day,
    );
    final settlementOffset = entry.settledOn?.difference(entry.date).inDays;
    return JournalEntryDraft(
      id: id,
      date: date,
      settledOn: settlementOffset == null
          ? null
          : date.add(Duration(days: settlementOffset)),
      narration: entry.narration,
      payee: entry.payee,
      tagIds: entry.tagIds,
      flag: entry.flag,
    );
  }
}

class JournalBuildTemplateCodec {
  const JournalBuildTemplateCodec._();

  static String encode(JournalEntryBuild build) {
    return jsonEncode({
      'entry': _entryToJson(build.entry),
      'postings': build.postings.map(_postingToJson).toList(growable: false),
    });
  }

  static JournalBuildTemplate decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Template must be a JSON object.');
    }
    final map = Map<String, Object?>.from(decoded);
    final entryRaw = map['entry'];
    final postingsRaw = map['postings'];
    if (entryRaw is! Map || postingsRaw is! List) {
      throw const FormatException('Template requires entry and postings.');
    }
    return JournalBuildTemplate(
      entry: _entryFromJson(Map<String, Object?>.from(entryRaw)),
      postings: postingsRaw
          .map((p) => _postingFromJson(Map<String, Object?>.from(p as Map)))
          .toList(growable: false),
    );
  }

  static Map<String, Object?> _entryToJson(JournalEntryDraft entry) {
    return {
      'id': entry.id,
      'date': _iso(entry.date),
      'settled_on': _isoOrNull(entry.settledOn),
      'narration': entry.narration,
      'payee': entry.payee,
      'tag_ids': entry.tagIds,
      'flag': entry.flag.name,
    };
  }

  static JournalEntryDraft _entryFromJson(Map<String, Object?> json) {
    final tagIdsRaw = json['tag_ids'];
    return JournalEntryDraft(
      id: json['id'] as String?,
      date: DateTime.parse(json['date'] as String).toUtc(),
      settledOn: json['settled_on'] == null
          ? null
          : DateTime.parse(json['settled_on'] as String).toUtc(),
      narration: json['narration'] as String,
      payee: json['payee'] as String?,
      tagIds: tagIdsRaw is List
          ? tagIdsRaw.map((v) => v as String).toList(growable: false)
          : const <String>[],
      flag: EntryFlag.values.byName((json['flag'] as String?) ?? 'confirmed'),
    );
  }

  static Map<String, Object?> _postingToJson(PostingDraft posting) {
    return {
      'id': posting.id,
      'position': posting.position,
      'account_id': posting.accountId,
      'units': posting.units.toString(),
      'unit': posting.unit,
      'cost': posting.cost == null ? null : _costToJson(posting.cost!),
      'price': posting.price == null ? null : _priceToJson(posting.price!),
    };
  }

  static PostingDraft _postingFromJson(Map<String, Object?> json) {
    return PostingDraft(
      id: json['id'] as String?,
      position: json['position'] as int?,
      accountId: json['account_id'] as String,
      units: Decimal.parse(json['units'] as String),
      unit: json['unit'] as String,
      cost: json['cost'] == null
          ? null
          : _costFromJson(Map<String, Object?>.from(json['cost']! as Map)),
      price: json['price'] == null
          ? null
          : _priceFromJson(Map<String, Object?>.from(json['price']! as Map)),
    );
  }

  static Map<String, Object?> _costToJson(Cost cost) {
    return {
      'per_unit': cost.perUnit.toString(),
      'currency': cost.currency,
      'lot_id': cost.lotId,
      'acquired_on': _isoOrNull(cost.acquiredOn),
    };
  }

  static Cost _costFromJson(Map<String, Object?> json) {
    return Cost(
      perUnit: Decimal.parse(json['per_unit'] as String),
      currency: json['currency'] as String,
      lotId: json['lot_id'] as String?,
      acquiredOn: json['acquired_on'] == null
          ? null
          : DateTime.parse(json['acquired_on'] as String).toUtc(),
    );
  }

  static Map<String, Object?> _priceToJson(Price price) {
    return {'per_unit': price.perUnit.toString(), 'currency': price.currency};
  }

  static Price _priceFromJson(Map<String, Object?> json) {
    return Price(
      perUnit: Decimal.parse(json['per_unit'] as String),
      currency: json['currency'] as String,
    );
  }
}

String _iso(DateTime value) => value.toUtc().toIso8601String();
String? _isoOrNull(DateTime? value) => value?.toUtc().toIso8601String();
