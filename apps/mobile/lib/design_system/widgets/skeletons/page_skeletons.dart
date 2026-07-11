/// Page-level skeleton templates that mirror each top-level surface's
/// resolved layout: stretched cards, hero blocks, and list rows. The
/// transition from loading to data should land without reflowing the page.
///
/// The shimmer cells re-use [SkeletonBox] / [SkeletonCard], which already
/// honor `MediaQuery.disableAnimations` and the design-system surface tones.
///
/// All page skeletons are wrapped in [PageSkeletonShell], which guarantees
/// the skeleton stays visible for at least [PageSkeletonShell.minDisplay]
/// before swapping to real data. Under local-first reads a bare
/// `loading: () => skeleton` can otherwise flash for a single frame.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../tokens/app_motion_policy.dart';
import '../../tokens/breakpoints.dart';
import '../../tokens/dimens_tokens.dart';
import '../../tokens/motion_tokens.dart';
import '../responsive_two_column.dart';
import '../skeleton.dart';

part 'page_skeletons_cashflow.dart';
part 'page_skeletons_chat.dart';
part 'page_skeletons_dashboard.dart';
part 'page_skeletons_portfolio.dart';
part 'page_skeletons_shell.dart';
