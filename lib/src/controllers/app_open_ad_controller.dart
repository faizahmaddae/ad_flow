import '../config/ad_flow_config.dart';
import '../core/ad_block_reason.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';

/// Preloads and shows app open ads, enforcing Google's 4-hour expiry:
/// a loaded ad is timestamped, and [show] discards-and-reloads a stale ad
/// instead of showing it.
///
/// Showing is driven by `AppOpenAdManager` on warm foreground returns —
/// never call [show] from app startup code (policy: no cold-start shows
/// unless routed through a dedicated splash gate).
class AppOpenAdController extends FullScreenAdControllerBase {
  /// Creates the app open controller. [now] is the injectable clock used
  /// for expiry.
  AppOpenAdController({
    required super.sdk,
    required super.gate,
    required super.caps,
    required super.coordinator,
    required AppOpenConfig config,
    required super.adUnitId,
    super.retry,
    super.onPaid,
    super.onBlocked,
    DateTime Function()? now,
  }) : _config = config,
       _now = now ?? DateTime.now,
       super(slot: slotName);

  /// The gate/cap slot name for app open ads.
  static const slotName = 'app_open';

  final AppOpenConfig _config;
  final DateTime Function() _now;
  DateTime? _loadedAt;

  /// Whether the warm ad has outlived [AppOpenConfig.expiry] (4h per
  /// Google) and must not be shown.
  bool get isExpired {
    final loadedAt = _loadedAt;
    if (loadedAt == null) return false;
    return _now().difference(loadedAt) >= _config.expiry;
  }

  @override
  Future<FullScreenAdHandle> loadHandle() =>
      sdk.loadAppOpen(adUnitId, const AdRequestOptions());

  @override
  void onLoaded() => _loadedAt = _now();

  @override
  Future<bool> show({OnUserEarnedReward? onReward}) async {
    if (isReady && isExpired) {
      // Stale inventory: discard, keep a fresh one warm, show nothing.
      noteBlocked(AdBlockReason.expired);
      discardCurrentAd();
      return false;
    }
    return super.show(onReward: onReward);
  }
}
