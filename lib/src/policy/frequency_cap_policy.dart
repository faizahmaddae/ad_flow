import '../config/ad_flow_config.dart';
import 'key_value_store.dart';

/// Decides whether a full-screen slot may show another impression, and
/// records impressions (per-slot caps + a global cross-format cap, ADR-009).
abstract interface class FrequencyCapPolicy {
  /// Whether [slot] may show now (its own cap AND the global cap).
  Future<bool> canShow(String slot);

  /// Records an impression for [slot] (and globally).
  Future<void> recordImpression(String slot);
}

/// [FrequencyCapPolicy] implementation:
///
/// - **Session counts** (`maxPerSession`) live in memory — a session is one
///   process lifetime.
/// - **Hourly counts** (`maxPerHour`) and **minimum gaps** (`minGap`) use
///   impression timestamps persisted through [KeyValueStore], so they
///   survive restarts.
///
/// The clock is injectable for tests.
class StoredFrequencyCapPolicy implements FrequencyCapPolicy {
  /// Creates a policy.
  ///
  /// [slotCaps] maps slot names (e.g. `'interstitial'`, `'app_open'`) to
  /// their caps; slots without an entry are limited only by [globalCap].
  StoredFrequencyCapPolicy({
    required KeyValueStore store,
    required Map<String, FrequencyCap> slotCaps,
    required FrequencyCap globalCap,
    DateTime Function()? now,
  }) : _store = store,
       _slotCaps = Map.of(slotCaps),
       _globalCap = globalCap,
       _now = now ?? DateTime.now;

  static const _globalSlot = '_global';

  /// Timestamps older than this are pruned from persisted histories.
  static const _historyWindow = Duration(hours: 1);

  final KeyValueStore _store;
  final Map<String, FrequencyCap> _slotCaps;
  final FrequencyCap _globalCap;
  final DateTime Function() _now;

  final Map<String, int> _sessionCounts = {};

  String _historyKey(String slot) => 'caps.$slot.history';

  String _lastKey(String slot) => 'caps.$slot.last';

  @override
  Future<bool> canShow(String slot) async {
    final cap = _slotCaps[slot];
    if (cap != null && !await _allows(slot, cap)) return false;
    return _allows(_globalSlot, _globalCap);
  }

  @override
  Future<void> recordImpression(String slot) async {
    final ts = _now().millisecondsSinceEpoch;
    _sessionCounts[slot] = (_sessionCounts[slot] ?? 0) + 1;
    _sessionCounts[_globalSlot] = (_sessionCounts[_globalSlot] ?? 0) + 1;
    await _push(slot, ts);
    await _push(_globalSlot, ts);
  }

  Future<bool> _allows(String slot, FrequencyCap cap) async {
    final maxPerSession = cap.maxPerSession;
    if (maxPerSession != null && (_sessionCounts[slot] ?? 0) >= maxPerSession) {
      return false;
    }

    if (cap.maxPerHour == null && cap.minGap == Duration.zero) return true;

    final nowMillis = _now().millisecondsSinceEpoch;

    final maxPerHour = cap.maxPerHour;
    if (maxPerHour != null) {
      final history = await _store.getHistory(_historyKey(slot));
      final hourAgo = nowMillis - Duration.millisecondsPerHour;
      final lastHour = history
          .where((ts) => ts > hourAgo && !_isFuture(ts, nowMillis))
          .length;
      if (lastHour >= maxPerHour) return false;
    }

    if (cap.minGap > Duration.zero) {
      // The last-impression timestamp is stored separately (not in the
      // pruned hourly history) so gaps longer than the history window work.
      final last = await _store.getInt(_lastKey(slot));
      if (last != null &&
          !_isFuture(last, nowMillis) &&
          nowMillis - last < cap.minGap.inMilliseconds) {
        return false;
      }
    }

    return true;
  }

  /// Whether [ts] is in the future relative to [now] — i.e. garbage written by
  /// a device whose clock was ahead (a dead RTC before NTP lands; a user who
  /// set the clock forward to skip an in-app cooldown).
  ///
  /// Such a timestamp must be IGNORED, never treated as a recent impression:
  /// `now - last` is negative, which is always `< minGap`, so a single
  /// future-dated stamp used to block that slot — and, via the global cap,
  /// EVERY full-screen format — permanently, across restarts, with no recovery
  /// short of clearing app data. Both read paths above filter it out and
  /// [_push] prunes it, so the bad value self-heals on the next impression.
  static bool _isFuture(int ts, int now) => ts > now;

  Future<void> _push(String slot, int ts) async {
    final cutoff = ts - _historyWindow.inMilliseconds;
    final history = await _store.getHistory(_historyKey(slot));
    final pruned = [
      for (final entry in history)
        if (entry > cutoff && !_isFuture(entry, ts)) entry,
      ts,
    ];
    await _store.setHistory(_historyKey(slot), pruned);
    await _store.setInt(_lastKey(slot), ts);
  }
}
