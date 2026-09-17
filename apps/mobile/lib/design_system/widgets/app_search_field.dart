import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'app_icon_button.dart';

/// Shared search chrome; callers own query scheduling and result state.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearLabel,
    this.focusNode,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String clearLabel;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => FTextField(
          control: FTextFieldControl.managed(
            controller: controller,
            onChange: (value) => onChanged?.call(value.text),
          ),
          focusNode: focusNode,
          hint: hint,
          maxLines: 1,
          textInputAction: TextInputAction.search,
          prefixBuilder: (_, _, _) => const Padding(
            padding: EdgeInsetsDirectional.only(
              start: AppSpacing.s12,
              end: AppSpacing.s8,
            ),
            child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
          ),
          suffixBuilder: value.text.isEmpty
              ? null
              : (_, _, _) => AppIconButton(
                  icon: FLucideIcons.x,
                  tooltip: clearLabel,
                  onPress: () {
                    controller.clear();
                    onChanged?.call('');
                    focusNode?.requestFocus();
                  },
                ),
        ),
      );
}
