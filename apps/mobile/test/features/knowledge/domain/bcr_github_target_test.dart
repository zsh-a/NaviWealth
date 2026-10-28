import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/domain/bcr_github_target.dart';

void main() {
  test(
    'normalizes strict GitHub repository identities and optional .git suffix',
    () {
      for (final address in <String>[
        'Alice/Notes',
        'https://github.com/Alice/Notes',
        'https://github.com/Alice/Notes.git/',
      ]) {
        expect(parseRepository(address), (owner: 'alice', repository: 'notes'));
      }
    },
  );

  test(
    'rejects custom origins, credentials, ports, traversal and ambiguous URLs',
    () {
      for (final address in <String>[
        'https://evil.test/alice/notes',
        'http://github.com/alice/notes',
        'https://github.com@evil.test/alice/notes',
        'https://secret@github.com/alice/notes',
        'https://github.com:443/alice/notes',
        'https://github.com/alice/notes?token=secret',
        'https://github.com/alice/notes#main',
        'alice/notes/tree/main',
        'alice/../notes',
        'alice/%2e%2e',
        'alice/.git',
        'alice/..',
        '-alice/notes',
        'alice-/notes',
        'alice_name/notes',
        '',
      ]) {
        expect(
          () => parseRepository(address),
          throwsFormatException,
          reason: address,
        );
      }
    },
  );

  test('preserves valid branch case and refuses unsafe Git refs', () {
    expect(isValidBcrGithubBranch('Notes/sync-1.0'), isTrue);
    for (final branch in <String>[
      '',
      'main/../other',
      'notes//sync',
      '.hidden',
      'main/',
      'main.',
      'main.lock',
      'notes/.hidden',
      'notes/old.lock/current',
      'main@{1}',
      'main?token=x',
      'main#secret',
      'main\\other',
      'main branch',
    ]) {
      expect(isValidBcrGithubBranch(branch), isFalse, reason: branch);
    }
  });

  test(
    'source identity is stable across owner/repo case but branch-specific',
    () {
      BcrGithubTarget target(String owner, String repo, String branch) =>
          BcrGithubTarget(owner: owner, repository: repo, branch: branch);
      final first = target('Alice', 'Notes', 'main');
      expect(first.sourceId, startsWith('bcr-github-'));
      expect(first.sourceId, target('alice', 'notes', 'main').sourceId);
      expect(first.sourceId, isNot(target('alice', 'notes', 'Main').sourceId));
      expect(first.sourceId, isNot(target('alice', 'other', 'main').sourceId));
    },
  );
}
