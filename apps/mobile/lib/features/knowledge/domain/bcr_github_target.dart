import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A Git identity is independent of the optional BCR reading-page URL.
class BcrGithubTarget {
  BcrGithubTarget({
    required String owner,
    required String repository,
    required String branch,
  }) : owner = owner.trim().toLowerCase(),
       repository = repository.trim().toLowerCase(),
       branch = branch.trim() {
    if (!_validRepository(this.owner, this.repository) ||
        !isValidBcrGithubBranch(this.branch)) {
      throw const FormatException('Invalid BCR GitHub target');
    }
  }

  final String owner;
  final String repository;
  final String branch;

  String get sourceId =>
      'bcr-github-${sha256.convert(utf8.encode(jsonEncode(<String>[owner, repository, branch])))}';

  static ({String owner, String repository}) parseRepository(String address) =>
      _parseRepository(address);
}

({String owner, String repository}) parseRepository(String address) =>
    _parseRepository(address);

({String owner, String repository}) _parseRepository(String address) {
  if (address.length > 512) {
    throw const FormatException('Invalid GitHub repository');
  }
  final match = RegExp(
    r'^(?:https://github\.com/)?([A-Za-z0-9-]+)/([A-Za-z0-9_.-]+)/?$',
    caseSensitive: false,
  ).firstMatch(address.trim());
  if (match == null) throw const FormatException('Invalid GitHub repository');
  final owner = match.group(1)!.toLowerCase();
  final repository = match
      .group(2)!
      .replaceFirst(RegExp(r'\.git$', caseSensitive: false), '')
      .toLowerCase();
  if (!_validRepository(owner, repository)) {
    throw const FormatException('Invalid GitHub repository');
  }
  return (owner: owner, repository: repository);
}

bool _validRepository(String owner, String repository) =>
    owner.length <= 100 &&
    RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(owner) &&
    repository.isNotEmpty &&
    repository.length <= 100 &&
    repository != '.' &&
    repository != '..' &&
    RegExp(r'^[a-z0-9_.-]+$').hasMatch(repository);

bool isValidBcrGithubBranch(String branch) =>
    branch.isNotEmpty &&
    branch.length <= 200 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(branch) &&
    !branch.contains('..') &&
    !branch.contains('//') &&
    !branch.endsWith('/') &&
    !branch.endsWith('.') &&
    !branch
        .split('/')
        .any((part) => part.startsWith('.') || part.endsWith('.lock'));
