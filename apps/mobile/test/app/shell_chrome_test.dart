import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('shell tab spacing consumes bottom dock padding', (tester) async {
    late EdgeInsets contentPadding;
    late double floatingActionBottom;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 84)),
        child: Builder(
          builder: (context) {
            contentPadding = shellTabContentPadding(
              context,
              top: AppSpacing.s8,
              bottom: AppSpacing.s64,
            );
            floatingActionBottom = shellTabFloatingActionBottom(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      contentPadding,
      const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s64 + 84,
      ),
    );
    expect(floatingActionBottom, AppSpacing.s16 + 84);
  });
}
