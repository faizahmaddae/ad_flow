import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdFlowError', () {
    test('equality covers kind, message, code and domain', () {
      const a = AdFlowError(
        AdFlowErrorKind.loadFailed,
        'no fill',
        code: 3,
        domain: 'com.google.admob',
      );
      const b = AdFlowError(
        AdFlowErrorKind.loadFailed,
        'no fill',
        code: 3,
        domain: 'com.google.admob',
      );
      const c = AdFlowError(AdFlowErrorKind.loadFailed, 'no fill', code: 2);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes kind, message and optional fields', () {
      const e = AdFlowError(AdFlowErrorKind.consent, 'form error', code: 7);
      expect('$e', contains('consent'));
      expect('$e', contains('form error'));
      expect('$e', contains('7'));
    });

    test('is throwable as an Exception', () {
      const e = AdFlowError(AdFlowErrorKind.timeout, 'gave up');
      expect(() => throw e, throwsA(same(e)));
    });
  });

  group('AdLoadState', () {
    test('const states are canonical', () {
      expect(const AdIdle(), same(const AdIdle()));
      expect(const AdLoading(), same(const AdLoading()));
      expect(const AdLoaded(), same(const AdLoaded()));
      expect(const AdShowing(), same(const AdShowing()));
    });

    test('AdFailed equality follows its error', () {
      const e1 = AdFlowError(AdFlowErrorKind.loadFailed, 'no fill');
      const e2 = AdFlowError(AdFlowErrorKind.loadFailed, 'no fill');
      const e3 = AdFlowError(AdFlowErrorKind.showFailed, 'not ready');

      expect(const AdFailed(e1), equals(const AdFailed(e2)));
      expect(const AdFailed(e1), isNot(equals(const AdFailed(e3))));
    });

    test('AdBlocked equality follows its reason (3.0)', () {
      expect(
        const AdBlocked(AdBlockReason.consentNotGranted),
        equals(const AdBlocked(AdBlockReason.consentNotGranted)),
      );
      expect(
        const AdBlocked(AdBlockReason.consentNotGranted),
        isNot(equals(const AdBlocked(AdBlockReason.adsDisabled))),
      );
    });

    test('sealed switch is exhaustive over all states', () {
      String describe(AdLoadState s) => switch (s) {
        AdIdle() => 'idle',
        AdLoading() => 'loading',
        AdLoaded() => 'loaded',
        AdShowing() => 'showing',
        AdBlocked(:final reason) => 'blocked:${reason.name}',
        AdFailed(:final error) => 'failed:${error.kind.name}',
      };

      expect(describe(const AdIdle()), 'idle');
      expect(
        describe(const AdBlocked(AdBlockReason.adsDisabled)),
        'blocked:adsDisabled',
      );
      expect(
        describe(const AdFailed(AdFlowError(AdFlowErrorKind.loadFailed, 'x'))),
        'failed:loadFailed',
      );
    });
  });
}
