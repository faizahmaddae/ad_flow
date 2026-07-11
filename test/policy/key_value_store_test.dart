import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('InMemoryKeyValueStore', () {
    late InMemoryKeyValueStore store;
    setUp(() => store = InMemoryKeyValueStore());

    test('ints round-trip; absent reads null', () async {
      expect(await store.getInt('k'), isNull);
      await store.setInt('k', 42);
      expect(await store.getInt('k'), 42);
    });

    test('histories round-trip; absent reads empty', () async {
      expect(await store.getHistory('h'), isEmpty);
      await store.setHistory('h', [1, 2, 3]);
      expect(await store.getHistory('h'), [1, 2, 3]);
    });

    test('returned history is a defensive copy', () async {
      final source = [1, 2];
      await store.setHistory('h', source);
      source.add(3);
      expect(await store.getHistory('h'), [1, 2]);
      expect(() async => (await store.getHistory('h')).add(9), throwsA(anything));
    });
  });

  group('SharedPrefsKeyValueStore', () {
    late SharedPrefsKeyValueStore store;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      store = SharedPrefsKeyValueStore(prefs: SharedPreferencesAsync());
    });

    test('ints round-trip through shared_preferences', () async {
      expect(await store.getInt('k'), isNull);
      await store.setInt('k', 7);
      expect(await store.getInt('k'), 7);
    });

    test('histories round-trip as string lists', () async {
      expect(await store.getHistory('h'), isEmpty);
      await store.setHistory('h', [1700000000001, 1700000000002]);
      expect(await store.getHistory('h'), [1700000000001, 1700000000002]);
    });

    test('keys are namespaced under ad_flow.', () async {
      await store.setInt('k', 1);
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getInt('ad_flow.k'), 1);
      expect(await prefs.getInt('k'), isNull);
    });

    test('corrupt history entries are skipped, not crashed on', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setStringList('ad_flow.h', ['123', 'garbage', '456']);
      expect(await store.getHistory('h'), [123, 456]);
    });
  });
}
