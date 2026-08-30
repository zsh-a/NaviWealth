import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef LocalQueryResultPaneBuilder = Widget Function({
  required String query,
  required DateTime now,
  void Function(String query)? onContinueInChat,
});

/// Optional local structured-answer pane for command-palette queries.
///
/// Core owns the command-palette chrome only. Domains that can answer
/// natural-language questions locally override this seam with a pane builder.
final localQueryResultPaneBuilderProvider =
    Provider<LocalQueryResultPaneBuilder?>((ref) => null);
