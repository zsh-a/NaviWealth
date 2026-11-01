import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'app_icon_button.dart';

/// Shared search chrome; callers own query scheduling and result state.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearLabel,
    this.focusNode,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final String clearLabel;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late String _lastEmittedText = widget.controller.text;

  @override
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lastEmittedText = widget.controller.text;
    }
  }

  void _handleChange(TextEditingValue value) {
    // A composing range is input in progress, not a committed search term.
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    if (value.text == _lastEmittedText) return;
    _lastEmittedText = value.text;
    widget.onChanged?.call(value.text);
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => FTextField(
          control: FTextFieldControl.managed(
            controller: widget.controller,
            onChange: _handleChange,
          ),
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          hint: widget.hint,
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
                  tooltip: widget.clearLabel,
                  onPress: !widget.enabled
                      ? null
                      : () {
                          widget.controller.clear();
                          _handleChange(widget.controller.value);
                          widget.focusNode?.requestFocus();
                        },
                ),
        ),
      );
}
