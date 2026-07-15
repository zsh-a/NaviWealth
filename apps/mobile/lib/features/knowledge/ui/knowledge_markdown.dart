part of '_widgets.dart';

/// KnowledgeOS long-form markdown — reading density, not chat density.
///
/// Use on object detail bodies and writer previews so edit/preview match
/// what the user will read after save. Chat bubbles keep [AiMarkdown]
/// defaults.
class KnowledgeMarkdown extends StatelessWidget {
  const KnowledgeMarkdown({
    super.key,
    required this.text,
    this.selectable = true,
  });

  final String text;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return AiMarkdown(
      text: text,
      selectable: selectable,
      baseStyle: AiType.readingBody(context),
    );
  }
}
