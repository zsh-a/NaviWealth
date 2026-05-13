// Wave 44 — static contract checks on the AI regression corpus.
//
// These tests don't make any LLM calls. They guarantee the corpus,
// intent registry, and renderer dispatch stay consistent: every
// expected tool in the corpus has a real renderer (or is on the
// allowlisted JSON-only set), and every intent is registered.
//
// The live nightly job (planned, not in this commit) will pump each
// prompt through a real runtime and verify the dispatched tool set
// is a superset of `expectedTools`. The static check keeps that
// future job from accumulating dead references in the meantime.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/core/ai/regression/regression_corpus.dart';

/// Tool names that have an inline domain renderer in
/// `tool_invocation_renderers.dart`. Extracted at test-time so adding
/// a renderer never requires touching this allowlist.
Set<String> _renderersOnDisk() {
  final src = File(
    'lib/features/ai_chat/ui/tool_invocation_renderers.dart',
  ).readAsStringSync();
  // Match the switch arms in `renderToolOutput`: `'foo' => …` / `'foo' || 'bar' =>`.
  final out = <String>{};
  final pattern = RegExp(r"'([a-z_]+)'\s*=>");
  for (final m in pattern.allMatches(src)) {
    out.add(m.group(1)!);
  }
  // Handle `||` arms like `'get_industry_breakdown' || 'get_geo_breakdown' …`.
  final orPattern = RegExp(r"'([a-z_]+)'\s*\|\|");
  for (final m in orPattern.allMatches(src)) {
    out.add(m.group(1)!);
  }
  return out;
}

void main() {
  group('Wave 44 — regression corpus contract', () {
    test('corpus is non-empty (degenerate coverage check)', () {
      expect(regressionCorpus, isNotEmpty);
      expect(regressionCorpus.length, greaterThanOrEqualTo(5),
          reason: 'shrinking coverage requires explicit rationale — see '
              'lib/core/ai/regression/regression_corpus.dart');
    });

    test('every prompt id is unique', () {
      final seen = <String>{};
      for (final p in regressionCorpus) {
        expect(seen.add(p.id), isTrue, reason: 'duplicate prompt id: ${p.id}');
      }
    });

    test('every prompt.intent is registered in intent_policy', () {
      for (final p in regressionCorpus) {
        expect(lookupIntent(p.intent), isNotNull,
            reason: 'prompt ${p.id} uses unregistered intent "${p.intent}"');
      }
    });

    test('every prompt has at least one expected tool', () {
      for (final p in regressionCorpus) {
        expect(p.expectedTools, isNotEmpty,
            reason: 'prompt ${p.id} declares no expected tools — '
                'either add expectations or remove the prompt');
      }
    });

    test('every expected tool has a renderer or is on the JSON-only allowlist',
        () {
      final renderers = _renderersOnDisk();
      // Sanity — make sure parser found a non-trivial number of arms;
      // otherwise the regex broke and we'd false-pass everything.
      expect(renderers.length, greaterThanOrEqualTo(8),
          reason: 'parser returned too few renderers — switch-arm regex broken?');
      for (final p in regressionCorpus) {
        for (final tool in p.expectedTools) {
          final ok = renderers.contains(tool) || jsonOnlyRenderTools.contains(tool);
          expect(ok, isTrue,
              reason: 'prompt ${p.id} expects tool "$tool" but it has neither '
                  'a renderer in tool_invocation_renderers.dart nor a marker '
                  'in jsonOnlyRenderTools (regression_corpus.dart)');
        }
      }
    });

    test(
      "every expected tool is on the prompt intent's preferredReadModels OR "
      'is one of the cross-cutting compute_* / get_holdings tools',
      () {
        // Cross-cutting tools that any intent may legitimately call.
        const ambient = <String>{
          'compute_xirr',
          'compute_net_worth',
          'get_holdings',
          'get_xirr_summary',
        };
        // intent_policy lists read-model names (e.g. 'subscription_changes')
        // while the corpus stores tool names ('get_subscription_changes').
        // Normalise: strip the `get_` prefix when present.
        String stripGet(String name) =>
            name.startsWith('get_') ? name.substring(4) : name;

        for (final p in regressionCorpus) {
          final desc = lookupIntent(p.intent)!;
          final preferredNormalised = desc.preferredReadModels.map(stripGet).toSet();
          for (final tool in p.expectedTools) {
            if (ambient.contains(tool)) continue;
            final isPreferred = preferredNormalised.contains(stripGet(tool));
            expect(isPreferred, isTrue,
                reason: 'prompt ${p.id} expects tool "$tool" (read-model '
                    '"${stripGet(tool)}") but intent_policy '
                    '"${p.intent}".preferredReadModels (normalised) '
                    '= $preferredNormalised does not include it. '
                    'Either widen the intent registry or drop the expectation.');
          }
        }
      },
    );

    test('every registered intent has at least one corpus prompt', () {
      final coveredIntents = {for (final p in regressionCorpus) p.intent};
      for (final desc in intentDescriptors) {
        expect(coveredIntents.contains(desc.name), isTrue,
            reason: 'intent "${desc.name}" is registered but has no '
                'regression corpus entry — add one to '
                'regression_corpus.dart so its prompt template is '
                'exercised by the nightly job');
      }
    });
  });
}
