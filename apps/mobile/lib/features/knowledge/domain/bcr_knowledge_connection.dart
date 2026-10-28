import 'bcr_github_target.dart';

class BcrKnowledgeConnection {
  const BcrKnowledgeConnection({
    required this.target,
    required this.label,
    required this.libraryUrl,
    required this.revision,
    required this.credentialId,
    this.remoteHead,
    this.checkedAt,
  });

  final BcrGithubTarget target;
  String get id => target.sourceId;
  final String label;
  final Uri libraryUrl;
  final String revision;
  final String credentialId;
  final String? remoteHead;
  final DateTime? checkedAt;
}
