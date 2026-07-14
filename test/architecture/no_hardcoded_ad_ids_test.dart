import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces invariant 6 (SKILL.md §2): the library must never hardcode a
/// production ad-unit ID — production IDs come exclusively from
/// `AdFlowConfig`. Mirrors `seam_boundary_test.dart`: scans `lib/` for
/// every `ca-app-pub-<publisher>` occurrence and asserts the publisher
/// segment is always Google's official sample publisher id
/// (`3940256099942544`, used throughout `TestAdUnitIds`), never a real one
/// (review finding #12; previously only covered by a value-level test in
/// `ad_flow_config_test.dart`, which proves *behavior* but not the absence
/// of a stray literal anywhere else in the tree).
void main() {
  test('every ca-app-pub id in lib/ uses Google\'s sample publisher id '
      '(invariant 6)', () {
    const samplePublisherId = '3940256099942544';
    final adUnitIdPattern = RegExp(r'ca-app-pub-(\d+)');

    final offenders = <String>[];
    for (final entity in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceFirst(RegExp(r'^\.[\\/]'), '');
      final content = entity.readAsStringSync();

      for (final match in adUnitIdPattern.allMatches(content)) {
        final publisherId = match.group(1);
        if (publisherId == samplePublisherId) continue;
        final lineNumber =
            '\n'.allMatches(content.substring(0, match.start)).length + 1;
        offenders.add('$relative:$lineNumber: ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found a ca-app-pub id in lib/ that is not Google\'s sample '
          'publisher id ($samplePublisherId). The library must never '
          'hardcode a production ad-unit ID — production IDs come '
          'exclusively from AdFlowConfig (ADR-012): $offenders',
    );
  });
}
