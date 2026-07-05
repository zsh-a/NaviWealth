part of 'account_repository.dart';

extension AccountRepositoryTreeQueries on AccountRepository {
  /// Live children of [parentId]. Pass `null` to fetch the top-level set
  /// (Beancount-style root nodes whose `parent_id` is NULL).
  ///
  /// Excludes archived / soft-deleted; *includes* system accounts because
  /// the picker needs them. Sorted by name for stable display order.
  Stream<List<Account>> watchChildrenOf(String? parentId) {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (parentId == null) {
      query.where((t) => t.parentId.isNull());
    } else {
      query.where((t) => t.parentId.equals(parentId));
    }
    return query.watch().map((rows) => rows.map(_toAccount).toList());
  }

  /// One-shot variant of [watchChildrenOf]. Same filters and ordering.
  Future<List<Account>> accountsByParent(String? parentId) async {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (parentId == null) {
      query.where((t) => t.parentId.isNull());
    } else {
      query.where((t) => t.parentId.equals(parentId));
    }
    final rows = await query.get();
    return rows.map(_toAccount).toList();
  }

  /// Depth-first walk through the subtree rooted at [rootId]. The root
  /// itself comes first, followed by descendants in name-sorted DFS
  /// order. Returns an empty list when the root doesn't exist or has
  /// been soft-deleted.
  ///
  /// Implementation: BFS by levels via repeated [accountsByParent]
  /// queries — fine for the seeded tree (<= 4 levels, <= 20 nodes) and
  /// keeps us out of recursive-CTE territory. Larger user-built trees
  /// will still be linear in the row count.
  Future<List<Account>> walkSubtree(String rootId) async {
    final root = await findById(rootId);
    if (root == null || root.archived || root.sync.deletedAt != null) {
      return const [];
    }
    final out = <Account>[root];
    final stack = <Account>[root];
    while (stack.isNotEmpty) {
      final parent = stack.removeLast();
      final children = await accountsByParent(parent.id);
      for (final c in children.reversed) {
        out.add(c);
        stack.add(c);
      }
    }
    return out;
  }

  /// Returns the chain from the tree root down to [accountId], inclusive
  /// of both. Returns an empty list if [accountId] doesn't exist.
  ///
  /// Defensive against malformed parent links: stops walking after
  /// 64 hops to prevent an accidental cycle from spinning forever.
  Future<List<Account>> pathOf(String accountId) async {
    final out = <Account>[];
    var cursor = await findById(accountId);
    var hops = 0;
    while (cursor != null && hops < 64) {
      out.add(cursor);
      final parentId = cursor.parentId;
      if (parentId == null) break;
      cursor = await findById(parentId);
      hops++;
    }
    return out.reversed.toList();
  }
}
