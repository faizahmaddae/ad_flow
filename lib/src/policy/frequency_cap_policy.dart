import 'dart:async';

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

/// [FrequencyCapPolicy] implementation — **memory-authoritative** (4.0 audit).
///
/// The in-memory state is the single source of truth for every decision:
///
/// - Persisted history/last-impression state is **hydrated once** (bounded —
///   a hanging or corrupt store degrades to session-only capping rather than
///   blocking every full-screen ad).
/// - After hydration, [canShow] and [recordImpression] decide/mutate
///   **synchronously in memory**: an impression recorded by one controller's
///   (un-awaited) dismiss handler binds the very next check from any other
///   controller. Before this, min-gap/hourly state was read back from the
///   store, so a check racing an in-flight write could let two full-screen
///   ads run back to back — the exact thing the global gap exists to prevent.
/// - Persistence is **write-behind and serialized**: each record enqueues a
///   snapshot on a single write chain, so concurrent read-modify-write races
///   (which used to lose impressions on disk) cannot happen, and a throwing
///   store never surfaces or breaks the chain.
///
/// Cap semantics: **session counts** (`maxPerSession`) are per process
/// lifetime and never persisted; **hourly counts** (`maxPerHour`) and
/// **minimum gaps** (`minGap`) survive restarts via [KeyValueStore].
/// Timestamps from a clock that was ahead (dead RTC, user skipping cooldowns)
/// are ignored and pruned — a future-dated stamp must never block ads forever
/// (ADR-037). The clock is injectable for tests.
///
/// Durability note: impressions recorded in the last moments before the
/// process dies may not have persisted (write-behind) — the cost is a
/// slightly loose cap after a crash, never a wrong in-session decision.
class StoredFrequencyCapPolicy implements FrequencyCapPolicy {
  /// Creates a policy.
  ///
  /// [slotCaps] maps slot names (e.g. `'interstitial'`, `'app_open'`) to
  /// their caps; slots without an entry are limited only by [globalCap].
  ///
  /// [globalCapExemptSlots] are slots whose *shows* the [globalCap] may not
  /// block — but whose *impressions* it still records (ADR-039). This is what
  /// separates the two jobs the global cap was doing: pacing **involuntary**
  /// ads (an interstitial or app-open the user never asked for) is its real
  /// purpose; blocking an ad the user explicitly tapped "watch for a reward"
  /// on is not. `AdFlow` exempts the classic rewarded slot (the rewarded
  /// interstitial is NOT exempt — its intro is an app-chosen interruption).
  StoredFrequencyCapPolicy({
    required KeyValueStore store,
    required Map<String, FrequencyCap> slotCaps,
    required FrequencyCap globalCap,
    Set<String> globalCapExemptSlots = const {},
    DateTime Function()? now,
  }) : _store = store,
       _slotCaps = Map.of(slotCaps),
       _globalCap = globalCap,
       _globalCapExemptSlots = Set.of(globalCapExemptSlots),
       _now = now ?? DateTime.now;

  static const _globalSlot = '_global';

  /// Timestamps older than this are pruned from histories.
  static const _historyWindow = Duration(hours: 1);

  /// Bounds hydration: a store whose reads hang (a wedged platform channel)
  /// must degrade to session-only capping, never hang every show decision.
  static const _hydrationTimeout = Duration(seconds: 5);

  final KeyValueStore _store;
  final Map<String, FrequencyCap> _slotCaps;
  final FrequencyCap _globalCap;
  final Set<String> _globalCapExemptSlots;
  final DateTime Function() _now;

  final Map<String, int> _sessionCounts = {};

  // In-memory truth (see class doc). Mutated only after hydration completes,
  // so hydration can write directly without merge logic. Hydration is LAZY
  // (kicked by the first decision/record, in the caller's zone) — a
  // constructor-kicked future would live in the construction zone and could
  // never be driven from a test's fakeAsync zone.
  final Map<String, List<int>> _history = {};
  final Map<String, int> _last = {};
  late final Future<void> _hydrated = _hydrate();
  bool _hydrationDone = false;

  /// The serialized write-behind chain. Every enqueued step snapshots memory
  /// at enqueue time; a failing store breaks neither the chain nor a caller.
  Future<void> _writeQueue = Future<void>.value();

  String _historyKey(String slot) => 'caps.$slot.history';

  String _lastKey(String slot) => 'caps.$slot.last';

  Future<void> _hydrate() async {
    // Only capped slots (and the global slot) are ever READ; uncapped slots
    // still persist their impressions for a future policy that caps them.
    final slots = {..._slotCaps.keys, _globalSlot};
    try {
      await Future.wait(slots.map(_hydrateSlot)).timeout(_hydrationTimeout);
    } catch (_) {
      // Corrupt or hanging persistence degrades to session-only capping;
      // the next impression's write-behind snapshot self-heals the store.
    } finally {
      _hydrationDone = true;
    }
  }

  Future<void> _hydrateSlot(String slot) async {
    final history = await _store.getHistory(_historyKey(slot));
    final last = await _store.getInt(_lastKey(slot));
    if (_hydrationDone) {
      // This read RESUMED after the bounded hydration already finalized (a
      // store that hung past _hydrationTimeout, then answered). Memory is now
      // authoritative and may already hold impressions recorded this session,
      // so this stale read must NEVER overwrite it — that used to roll a
      // fresh impression's last-stamp back to an old persisted one, letting
      // two full-screen ads fire back to back (4.1 audit). MERGE instead:
      // union the persisted history and keep the MORE RECENT last-stamp, so a
      // merely-slow store still recovers cross-session capping without ever
      // undoing an in-session decision.
      _mergeHydrated(slot, history, last);
      return;
    }
    _history[slot] = List.of(history);
    if (last != null) _last[slot] = last;
  }

  /// Folds a late/stale persisted read into authoritative memory without ever
  /// rolling it back (see [_hydrateSlot]).
  void _mergeHydrated(String slot, List<int> history, int? last) {
    final now = _now().millisecondsSinceEpoch;
    final cutoff = now - _historyWindow.inMilliseconds;
    final merged = <int>{
      ...?_history[slot],
      ...history,
    }.where((ts) => ts > cutoff && !_isFuture(ts, now)).toList()..sort();
    _history[slot] = merged;
    final candidates = <int>[
      ?_last[slot],
      ?last,
    ].where((ts) => !_isFuture(ts, now));
    if (candidates.isNotEmpty) {
      _last[slot] = candidates.reduce((a, b) => a > b ? a : b);
    }
  }

  @override
  Future<bool> canShow(String slot) async {
    if (!_hydrationDone) await _hydrated;
    final cap = _slotCaps[slot];
    if (cap != null && !_allows(slot, cap)) return false;
    // The slot's OWN cap always applies. The global cap only gates involuntary
    // formats (ADR-039) — a user who tapped "watch an ad for a reward" must
    // never be silently refused because an interstitial happened to fire a few
    // seconds earlier; they would get no ad AND no reward, with no explanation.
    if (_globalCapExemptSlots.contains(slot)) return true;
    return _allows(_globalSlot, _globalCap);
  }

  @override
  Future<void> recordImpression(String slot) async {
    if (!_hydrationDone) await _hydrated;
    final ts = _now().millisecondsSinceEpoch;
    _apply(slot, ts);
    _apply(_globalSlot, ts);
    _enqueuePersist(slot);
    _enqueuePersist(_globalSlot);
    // The returned future resolves once THIS record has persisted (callers
    // fire it un-awaited in production; awaiting it means durability). The
    // decision itself was committed synchronously above.
    return _writeQueue;
  }

  /// Applies one impression to the in-memory truth, synchronously — from
  /// this statement on, every decision sees it.
  void _apply(String slot, int ts) {
    _sessionCounts[slot] = (_sessionCounts[slot] ?? 0) + 1;
    final cutoff = ts - _historyWindow.inMilliseconds;
    _history[slot] = [
      for (final entry in _history[slot] ?? const <int>[])
        if (entry > cutoff && !_isFuture(entry, ts)) entry,
      ts,
    ];
    // The last-impression stamp is kept separate from the pruned hourly
    // history so minGap values longer than the 1h window still work.
    _last[slot] = ts;
  }

  /// Snapshots [slot]'s memory state onto the serialized write chain.
  void _enqueuePersist(String slot) {
    final history = List<int>.of(_history[slot] ?? const []);
    final last = _last[slot];
    _writeQueue = _writeQueue
        .then((_) async {
          await _store.setHistory(_historyKey(slot), history);
          if (last != null) await _store.setInt(_lastKey(slot), last);
        })
        .catchError((Object _) {
          // A throwing store loses this snapshot's durability, nothing else —
          // memory stays authoritative and the chain stays alive.
        });
  }

  bool _allows(String slot, FrequencyCap cap) {
    final maxPerSession = cap.maxPerSession;
    if (maxPerSession != null && (_sessionCounts[slot] ?? 0) >= maxPerSession) {
      return false;
    }

    if (cap.maxPerHour == null && cap.minGap == Duration.zero) return true;

    final nowMillis = _now().millisecondsSinceEpoch;

    final maxPerHour = cap.maxPerHour;
    if (maxPerHour != null) {
      final hourAgo = nowMillis - Duration.millisecondsPerHour;
      final lastHour = (_history[slot] ?? const <int>[])
          .where((ts) => ts > hourAgo && !_isFuture(ts, nowMillis))
          .length;
      if (lastHour >= maxPerHour) return false;
    }

    if (cap.minGap > Duration.zero) {
      final last = _last[slot];
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
  /// short of clearing app data. The read paths filter it out and [_apply]
  /// prunes it, so the bad value self-heals on the next impression (ADR-037).
  static bool _isFuture(int ts, int now) => ts > now;
}
