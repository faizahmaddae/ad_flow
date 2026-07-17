import '../config/ad_flow_config.dart';
import '../seam/ad_sdk.dart';
import 'full_screen_ad_controller_base.dart';

/// Preloads and shows app open ads, enforcing Google's 4-hour expiry
/// through the base engine's shared `maxAdAge` mechanism (the base
/// timestamps every load and [FullScreenAdControllerBase.show]
/// discards-and-reloads a stale ad instead of showing it).
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
    super.now,
  }) : _config = config,
       super(slot: slotName, maxAdAge: config.expiry);

  /// The gate/cap slot name for app open ads.
  static const slotName = 'app_open';

  final AppOpenConfig _config;

  @override
  Future<FullScreenAdHandle> loadHandle() =>
      sdk.loadAppOpen(adUnitId, _config.request);
}
