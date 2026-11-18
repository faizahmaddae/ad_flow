import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the public surface of `package:ad_flow/ad_flow.dart` (6.0, ADR-084).
///
/// 5.x exported 105 types, internals included, so every internal fix risked a
/// major release (2.0 → 5.0 in six days). 6.0 exports only what app code
/// uses; the seam's handles/events/load specs, the full-screen engine and the
/// policy collaborators live in `ad_flow_testing.dart`. This test makes any
/// change to the main library's surface deliberate: adding or removing a
/// public name fails here until [expected] is updated — and an addition
/// should only land when app code needs it (otherwise export it from
/// `ad_flow_testing.dart`). A removal is a breaking change.
///
/// A plain parse rather than an analyzer dependency — made STRICT so it
/// cannot silently miss a name: `export`s are followed into the exported
/// files (and theirs), `show`/`hide` are applied, and every top-level line of
/// an exported file must be recognised as a declaration or known not to be
/// one. Anything else fails the test, so a new declaration form means
/// extending [_parse], never a silent gap. The parser has its own tests below.
void main() {
  test('ad_flow.dart exports exactly the pinned public API', () {
    expect(
      _exportedNames('lib/ad_flow.dart'),
      expected,
      reason:
          'The public API of package:ad_flow/ad_flow.dart changed. If that '
          'is intended, update `expected` in this test, CHANGELOG.md and — '
          'for a removal or rename — MIGRATION.md. Internals belong in '
          'ad_flow_testing.dart.',
    );
  });

  test('the internals stay out of the main library', () {
    final main = _exportedNames('lib/ad_flow.dart');
    for (final internal in const [
      'AdGate',
      'BannerHandle',
      'BannerHeightMemory',
      'BannerLoadSpec',
      'FakeAdSdk',
      'FullScreenAdControllerBase',
      'FullScreenAdCoordinator',
      'InMemoryKeyValueStore',
      'InterstitialHandle',
      'RetryPolicy',
      'SharedPrefsKeyValueStore',
      'StoredFrequencyCapPolicy',
      'requestConfigFrom',
      'resolveAdUnitId',
      'validateBannerConfig',
      'validateNativeConfig',
    ]) {
      expect(main, isNot(contains(internal)), reason: internal);
    }
  });

  test('the testing library reads cleanly too', () {
    // Not pinned (it follows the seam), but it must parse: a test double an
    // app needs must not hide behind an unreadable line.
    expect(_exportedNames('lib/ad_flow_testing.dart'), contains('FakeAdSdk'));
  });

  group('the parser', () {
    test('recognises every top-level declaration form', () {
      final parsed = _parse(_allForms);
      expect(parsed.unparsed, isEmpty);
      expect(parsed.names, {
        'PlainClass',
        'Iface',
        'FinalClass',
        'Sealed',
        'BaseMixinClass',
        'AnnotatedSameLine',
        'AMixin',
        'AnEnum',
        'NewTypedef',
        'GenericTypedef',
        'OldTypedef',
        'ExtType',
        'ConstExtType',
        'NamedExt',
        'GenericExt',
        'plainFunction',
        'genericReturn',
        'genericFunction',
        'recordReturn',
        'functionReturn',
        'multiLine',
        'externalFunction',
        'aGetter',
        'aSetter',
        'aConst',
        'aFinal',
        'aVar',
        'aLate',
        'typedVariable',
        'typedList',
      });
      expect(
        [for (final e in parsed.exports) '${e.uri} ${e.mode} ${e.listed}'],
        ['a.dart null {}', 'b.dart show {X, Y}', 'c.dart hide {Z}'],
      );
    });

    test('fails on what it cannot read instead of skipping it', () {
      const statement = "print('a top-level statement');";
      expect(_parse('$statement\n').unparsed, [statement]);
      const conditional = "export 'a.dart' if (dart.library.io) 'b.dart';";
      expect(_parse('$conditional\n').unparsed, [conditional]);
      expect(_parse("part 'x.dart';\n").unparsed, ["part 'x.dart';"]);
    });
  });
}

/// Every public name [barrelPath] exposes: its own declarations plus what it
/// exports, followed through nested exports. Fails on anything unreadable.
Set<String> _exportedNames(String barrelPath) {
  final problems = <String>[];
  final names = _publicNamesOf(File(barrelPath), problems, <String>{});
  if (problems.isNotEmpty) {
    fail(
      'public_api_test cannot read these top-level lines — extend _parse so '
      'no public name can slip past the pin:\n${problems.join('\n')}',
    );
  }
  return names;
}

Set<String> _publicNamesOf(File file, List<String> problems, Set<String> seen) {
  if (!seen.add(file.absolute.path)) return const {};
  final parsed = _parse(file.readAsStringSync());
  problems.addAll(parsed.unparsed.map((line) => '${file.path}: $line'));
  final names = {...parsed.names};
  for (final export in parsed.exports) {
    if (export.uri.contains(':')) {
      problems.add('${file.path}: unsupported export URI ${export.uri}');
      continue;
    }
    final target = File.fromUri(file.absolute.uri.resolve(export.uri));
    final exported = _publicNamesOf(target, problems, seen);
    names.addAll(switch (export.mode) {
      'show' => exported.intersection(export.listed),
      'hide' => exported.difference(export.listed),
      _ => exported,
    });
  }
  return names;
}

class _Export {
  _Export(this.uri, this.mode, this.listed);
  final String uri;
  final String? mode;
  final Set<String> listed;
}

class _Parsed {
  _Parsed(this.names, this.exports, this.unparsed);
  final Set<String> names;
  final List<_Export> exports;
  final List<String> unparsed;
}

final _exportDirective = RegExp(
  r'''^export\s+(['"])([^'"]+)\1(?:\s+(show|hide)\s+([^;]+))?;''',
  multiLine: true,
);

/// Declaration patterns, tried in order on a top-level line whose leading
/// annotations were stripped. Each captures the declared name in group 1;
/// an unnamed extension (not importable by name) matches without one.
final _declarations = <RegExp>[
  RegExp(
    r'^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin)\s+(\w+)',
  ),
  RegExp(r'^typedef\s+(\w+)\s*(?:<[^>]*>)?\s*='),
  RegExp(r'^typedef\s+.+?\s(\w+)\s*(?:<[^>]*>)?\s*\('),
  RegExp(r'^extension\s+type\s+(?:const\s+)?(\w+)'),
  RegExp(r'^extension\s+(\w+)\s*(?:<[^>]*>)?\s+on\b'),
  RegExp(r'^extension\s+on\b'),
  RegExp(
    r'^(?:late\s+)?(?:const|final|var)\s+(?:[\w.]+(?:<.*?>)?\??\s+)?'
    r'(\w+)\s*(?:=|;)',
  ),
  RegExp(r'^(?:external\s+)?(?:.+?\s+)?get\s+(\w+)\b'),
  RegExp(r'^(?:external\s+)?set\s+(\w+)\s*\('),
  RegExp(
    r'^(?:external\s+)?(?:[\w.]+(?:<.*?>)?\??|\(.*?\)\??)'
    r'(?:\s+Function\s*(?:<.*?>)?\s*\(.*?\)\??)*\s+(\w+)\s*(?:<.*?>)?\s*\(',
  ),
  RegExp(r'^(?:[\w.]+(?:<.*?>)?\??)\s+(\w+)\s*(?:=|;)'),
];

final _annotation = RegExp(r'^@[\w.]+(?:\([^)]*\))?\s*');
final _notDeclaration = RegExp(
  // A line opening with a closing bracket ends a multi-line construct (a
  // signature's `}) {`); a bare `@Name(` opens a multi-line annotation.
  r'^(?:$|//|/\*|\*|library\b|import\s|[)\]}]|@[\w.]+\($)',
);

/// Reads a Dart library's top level: public declared names, `export`
/// directives, and every top-level line it could not classify.
_Parsed _parse(String source) {
  final names = <String>{};
  final unparsed = <String>[];
  final matches = _exportDirective.allMatches(source).toList();
  final exports = [
    for (final match in matches)
      _Export(
        match.group(2)!,
        match.group(3),
        (match.group(4) ?? '')
            .split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet(),
      ),
  ];
  final exportLines = {
    for (final match in matches) source.substring(match.start).split('\n')[0],
  };
  for (final line in source.split('\n')) {
    // Only column 0 is the top level (`dart format` indents the rest).
    if (line.startsWith(' ') || line.startsWith('\t')) continue;
    if (line.startsWith('export')) {
      if (!exportLines.contains(line)) unparsed.add(line);
      continue;
    }
    var rest = line.trimRight();
    if (_notDeclaration.hasMatch(rest)) continue;
    while (rest.startsWith('@') && _annotation.hasMatch(rest)) {
      final stripped = rest.replaceFirst(_annotation, '');
      if (stripped == rest) break;
      rest = stripped;
    }
    if (_notDeclaration.hasMatch(rest)) continue;
    RegExpMatch? match;
    for (final pattern in _declarations) {
      match = pattern.firstMatch(rest);
      if (match != null) break;
    }
    if (match == null) {
      unparsed.add(line);
      continue;
    }
    final name = match.groupCount >= 1 ? match.group(1) : null;
    if (name != null && !name.startsWith('_')) names.add(name);
  }
  return _Parsed(names, exports, unparsed);
}

/// One of each declaration form the parser must read (its own test).
const _allForms = r"""
library;

import 'dart:async';
export 'a.dart';
export "b.dart" show X, Y;
export 'c.dart'
    hide
        Z;

/// Doc.
@immutable
class PlainClass {}
abstract interface class Iface {}
final class FinalClass {}
sealed class Sealed {}
base mixin class BaseMixinClass {}
@immutable class AnnotatedSameLine {}
mixin AMixin {}
enum AnEnum { a, b }
typedef NewTypedef = void Function();
typedef GenericTypedef<T> = List<T>;
typedef void OldTypedef(int a);
extension type ExtType(int value) {}
extension type const ConstExtType(int value) {}
extension NamedExt on Object {}
extension GenericExt<T> on List<T> {}
extension on String {}
void plainFunction() {}
Future<Map<String, int>?> genericReturn() async => null;
T genericFunction<T>(T a) => a;
(int, String) recordReturn() => (1, 'a');
void Function() functionReturn() => () {};
String? multiLine({
  required int a,
}) => null;
external int externalFunction();
int get aGetter => 1;
set aSetter(int value) {}
const aConst = 1;
final aFinal = <int>[];
var aVar = 2;
late final int aLate;
int typedVariable = 3;
List<String> typedList = [];
void _private() {}
class _PrivateClass {}
@Deprecated(
  'old',
)
}
);
""";

/// The pinned public API of `package:ad_flow/ad_flow.dart`: 68 types and
/// 4 helper functions (6.0.0).
const expected = <String>{
  'AdBlockReason',
  'AdBlocked',
  'AdConsentStatus',
  'AdController',
  'AdFailed',
  'AdFlow',
  'AdFlowBanner',
  'AdFlowConfig',
  'AdFlowError',
  'AdFlowErrorKind',
  'AdFlowNativeAd',
  'AdIdle',
  'AdInspectorResult',
  'AdLoadState',
  'AdLoaded',
  'AdLoading',
  'AdPaidEvent',
  'AdPlatform',
  'AdRequestOptions',
  'AdResponseSummary',
  'AdRevenuePrecision',
  'AdSdk',
  'AdShowResult',
  'AdShowing',
  'AnchoredBannerSize',
  'AppOpenAdController',
  'AppOpenAdManager',
  'AppOpenConfig',
  'AttExplainerContent',
  'AttExplainerPresenter',
  'AttExplainerScreen',
  'AttStatus',
  'BannerAdController',
  'BannerConfig',
  'BannerKind',
  'CollapsiblePlacement',
  'ConsentDebugGeography',
  'ConsentDebugOptions',
  'ConsentGateway',
  'FixedBannerSize',
  'FrequencyCap',
  'FullScreenAdController',
  'InterstitialAdController',
  'InterstitialConfig',
  'KeyValueStore',
  'MaxContentRating',
  'MediationNetworkExtras',
  'NativeAdController',
  'NativeConfig',
  'NativeTemplateKind',
  'OnUserEarnedReward',
  'PlatformAdUnitId',
  'PrivacyOptionsButton',
  'PrivacyOptionsRequirement',
  'RetryConfig',
  'RewardEarned',
  'RewardIntroContent',
  'RewardedAdController',
  'RewardedConfig',
  'RewardedInterstitialAdController',
  'RewardedInterstitialConfig',
  'RewardedIntroPresenter',
  'RewardedIntroScreen',
  'ServerSideVerification',
  'TcfConsent',
  'TcfConsentReader',
  'TestAdUnitIds',
  'UmpConsentGateway',
  'adPlatformOf',
  'asAdFlowError',
  'currentAdPlatform',
  'readDeviceTcfConsent',
};
