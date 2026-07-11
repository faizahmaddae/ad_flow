import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces invariant 8 (SKILL.md §2): the `AdSdk` seam is the only door
/// to `google_mobile_ads`. A plain grep-in-a-test rather than a lint rule,
/// so a future contributor adding a plugin import outside the seam gets a
/// clear failure instead of a silent architecture drift.
void main() {
  test('only the seam imports package:google_mobile_ads (invariant 8)', () {
    const allowed = 'lib/src/seam/gma_ad_sdk.dart';
    final offenders = <String>[];

    for (final entity in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceFirst(RegExp(r'^\.[\\/]'), '');
      if (relative == allowed) continue;

      final content = entity.readAsStringSync();
      final importsPlugin = RegExp(
        r'''^\s*(import|export)\s+['"]package:google_mobile_ads''',
        multiLine: true,
      ).hasMatch(content);
      if (importsPlugin) offenders.add(relative);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Only $allowed may import google_mobile_ads. Route the new call '
          'through the AdSdk seam instead (see ARCHITECTURE.md, invariant '
          '8) — found imports in: $offenders',
    );
  });
}
