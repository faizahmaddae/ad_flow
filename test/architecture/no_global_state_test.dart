import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces invariant 9 (SKILL.md §2): no global mutable state / static
/// singleton config. Two sanctioned exceptions, each a single process-scoped
/// latch that CANNOT be expressed as injected instance state and each backed by
/// an injectable override for tests, so this test allow-lists exactly those
/// lines instead of banning `static` outright (which would also flag legitimate
/// `static const`/factory constructors):
///
/// - `AdFlow._instance` — the convenience pointer to the last-initialized
///   instance (ADR-004).
/// - `AppOpenAdManager._launchOpportunityConsumed` — the one-shot cold-launch
///   latch that must survive `AdFlow` reinitialization within a process, so a
///   second `initialize()` cannot mint a second launch app-open show (ADR-067).
///   Private; reset for tests via `AppOpenAdManager.resetLaunchOpportunity`.
///
/// Only `static const` is exempt — `const` is the one Dart-enforced
/// guarantee of deep immutability. An earlier version of this test also
/// exempted `static final <UpperCamelCase...>`, reasoning that upper-case
/// types read as "constant-ish" (matching `TestAdUnitIds`' fields) — but
/// that carve-out would just as happily wave through
/// `static final ValueNotifier<int> _shared = ValueNotifier(0);` or
/// `static final List<String> _log = [];`, the most realistic shape
/// invariant 9 actually guards against (review finding #11). `static
/// final` is flagged like anything else now; there are no legitimate uses
/// of it in `lib/` today, so this costs nothing.
void main() {
  test('no new mutable static fields outside the sanctioned AdFlow.instance '
      'pointer (invariant 9)', () {
    // Matches any static field declaration that is NOT `static const`.
    final staticFieldPattern = RegExp(
      r'^\s*static\s+(?!const\b)\S.*\b\w+\s*(=|;)',
      multiLine: true,
    );
    const allowed = <(String, String)>[
      ('lib/src/facade/ad_flow.dart', 'static AdFlow? _instance'),
      (
        'lib/src/lifecycle/app_open_ad_manager.dart',
        'static bool _launchOpportunityConsumed',
      ),
    ];

    final offenders = <String>[];
    for (final entity in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceFirst(RegExp(r'^\.[\\/]'), '');
      final content = entity.readAsStringSync();

      for (final match in staticFieldPattern.allMatches(content)) {
        final line = match.group(0)!.trim();
        // Skip static methods/getters/constructors — the pattern above
        // only targets bare field declarations, but double-check here to
        // avoid false positives on e.g. `static Future<AdFlow> initialize(`.
        if (line.contains('(')) continue;
        if (allowed.any((a) => relative == a.$1 && line.contains(a.$2))) {
          continue;
        }
        offenders.add('$relative: $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found mutable static state outside the sanctioned exceptions '
          '($allowed). ad_flow uses dependency injection, not static/singleton '
          'config (ADR-004) — inject this instead: $offenders',
    );
  });
}
