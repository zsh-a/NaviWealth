part of 'page_skeletons.dart';

/// Mirrors `AiChatPage` while the message stream is loading.
class AiChatSkeleton extends StatelessWidget {
  const AiChatSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: const [
              _ChatBubbleSkeleton(alignEnd: false),
              SizedBox(height: AppSpacing.s12),
              _ChatBubbleSkeleton(alignEnd: true, lines: 1),
              SizedBox(height: AppSpacing.s12),
              _ChatBubbleSkeleton(alignEnd: false, lines: 3),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: SkeletonBox(height: 48, radius: AppRadius.lg),
        ),
      ],
    );
  }
}

class _ChatBubbleSkeleton extends StatelessWidget {
  const _ChatBubbleSkeleton({required this.alignEnd, this.lines = 2});

  final bool alignEnd;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: context.theme.colors.muted,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < lines; i++) ...[
                if (i != 0) const SizedBox(height: AppSpacing.s6),
                SkeletonBox(width: 200.0 - (i * 24), height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
