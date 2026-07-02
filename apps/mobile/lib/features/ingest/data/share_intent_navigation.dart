import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ShareIntentDestination { financeIngest, knowledgeInbox }

typedef ShareIntentNavigationSink =
    void Function(ShareIntentDestination destination);

final shareIntentNavigationSinkProvider = Provider<ShareIntentNavigationSink>(
  (_) => (_) {},
);
