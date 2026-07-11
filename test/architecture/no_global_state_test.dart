import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces invariant 9 (SKILL.md §2): no global mutable state / static
/// singleton config. `AdFlow._instance` is the ONE sanctioned exception —
/// a convenience pointer backed by an injectable instance (ADR-004) — so
/// this test allow-lists exactly that line instead of banning `static`
/// outright (which would also flag legitimate `static const`/factory
/// constructors).
void main() {
  test('no new mutable static fields outside the sanctioned AdFlow.instance '
      'pointer (invariant 9)', () {
    // Matches a static field declaration that is NOT `static const` and
    // NOT `static final <UpperCamelCase...>` (the pattern used for
    // compile-time-constant-ish constants like TestAdUnitIds' fields,
    // and for effectively-final singleton locals).
    final staticFieldPattern = RegExp(
      r'^\s*static\s+(?!const\b)(?!final\s+[A-Z])\S.*\b\w+\s*(=|;)',
      multiLine: true,
    );
    const allowedFile = 'lib/src/facade/ad_flow.dart';
    const allowedSnippet = 'static AdFlow? _instance';

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
        if (relative == allowedFile && line.contains(allowedSnippet)) {
          continue;
        }
        offenders.add('$relative: $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found mutable static state outside the sanctioned '
          '$allowedFile ($allowedSnippet). ad_flow uses dependency '
          'injection, not static/singleton config (ADR-004) — inject this '
          'instead: $offenders',
    );
  });
}
