import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Documentation-drift guard (5.1 release gate).
///
/// Derives the package version from `pubspec.yaml` and fails if an `ad_flow`
/// install/migration pin in the user-facing docs silently drifts — the common
/// way docs rot after a version bump. Small and specific on purpose: it is not
/// a general docs framework. Only pins anchored to `ad_flow` are checked
/// (`ad_flow: ^X` / `ad_flow to ^X`), so a `google_mobile_ads: ^9.0.0` on the
/// same line is not mistaken for the package's own version.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(
    r'^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  final major = int.parse(version!.group(1)!);
  final minor = int.parse(version.group(2)!);
  final patch = int.parse(version.group(3)!);
  final full = '$major.$minor.$patch';
  int rank(int a, int b, int c) => (a * 1000 + b) * 1000 + c;
  final currentRank = rank(major, minor, patch);

  // Anchored to the package name so other packages' pins on the same line
  // (e.g. `ad_flow: ^2.0.0 (pulls google_mobile_ads: ^9.0.0)`) are ignored.
  final pin = RegExp(r'ad_flow(?::| to)\s*\^([0-9]+)\.([0-9]+)\.([0-9]+)');

  test('every ad_flow install/migration pin in the README matches the pubspec '
      'major (the current-facing doc must not fall back to an old major)', () {
    // README carries the CURRENT install snippet and the CURRENT migration
    // prompt — every ad_flow pin there must be this major. (MIGRATION.md
    // legitimately keeps HISTORICAL pins like `^2.0.0` for old upgrade paths,
    // so it is checked only for the no-newer-than-current rule below.)
    final text = File('README.md').readAsStringSync();
    final matches = pin.allMatches(text).toList();
    expect(
      matches,
      isNotEmpty,
      reason: 'expected at least one ad_flow install pin in the README',
    );
    for (final m in matches) {
      expect(
        m.group(1),
        '$major',
        reason:
            'README pins "ad_flow ^${m.group(1)}.${m.group(2)}.'
            '${m.group(3)}" but pubspec is $full — stale snippet.',
      );
    }
  });

  test('no doc pins an ad_flow version NEWER than pubspec (typo / future '
      'version guard)', () {
    for (final path in const ['README.md', 'MIGRATION.md']) {
      final text = File(path).readAsStringSync();
      for (final m in pin.allMatches(text)) {
        final r = rank(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
        expect(
          r <= currentRank,
          isTrue,
          reason:
              '$path pins ad_flow '
              '^${m.group(1)}.${m.group(2)}.${m.group(3)} > pubspec $full',
        );
      }
    }
  });

  test('CHANGELOG top entry is the pubspec version', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final top = RegExp(
      r'^##\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(changelog)?.group(1);
    expect(
      top,
      full,
      reason:
          'CHANGELOG top entry ($top) should be the pubspec version ($full)',
    );
  });
}
