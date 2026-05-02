import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // AiChatPage with no auth session falls into the LoginRequired surface —
  // a deterministic, network-free state that still exercises the GlassAppBar
  // + page padding, which is what we actually need to lock down. The
  // chat-thread layout itself is covered by message_bubble / chat_composer
  // widget tests; capturing the full SSE-streaming surface here would
  // require a backend stub on every CI run for no visual gain.
  runAllVariants('ai_chat_page_login_required', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'ai_chat_page_login_required',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AiChatPage(),
    );
  });
}
