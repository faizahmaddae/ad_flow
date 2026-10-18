import 'package:flutter/widgets.dart';

import '../config/ad_flow_config.dart';
import '../controllers/native_ad_controller.dart';
import '../core/ad_block_reason.dart';
import '../core/ad_load_state.dart';
import '../facade/ad_flow.dart';

/// Drop-in native ad widget.
///
/// Reserves its slot from the first frame — the full width it is given, at a
/// fixed height — and hosts the loaded ad in that same box, so the ad's
/// arrival shifts nothing. Triggers the load and disposes the controller it
/// owns when unmounted.
///
/// Give it a bounded width. Under an unbounded one (a `Row` child without
/// `Expanded`, a horizontal list) there is no width to fill, so the slot lays
/// out zero wide instead of throwing; wrap it in a `SizedBox` with a width, or
/// an `Expanded`, there.
///
/// The recommended usage (3.0) creates and owns the controller internally —
/// the "fresh controller minted inside build()" footgun (ADR-029, a
/// permanently blank ad) is unrepresentable this way:
///
/// ```dart
/// AdFlowNativeAd(adFlow: ads)
/// AdFlowNativeAd(adFlow: ads, config: NativeConfig(...))
/// ```
class AdFlowNativeAd extends StatefulWidget {
  /// Creates a native ad widget.
  ///
  /// Provide exactly one of [adFlow] (the widget creates and owns a
  /// controller — recommended) or [controller] (advanced; set
  /// [ownsController] when this widget should dispose it on unmount).
  /// [config] optionally overrides the global native config and requires
  /// [adFlow].
  const AdFlowNativeAd({
    this.adFlow,
    this.config,
    this.controller,
    this.ownsController = false,
    this.placeholderHeight,
    super.key,
  }) : assert(
         (controller != null) ^ (adFlow != null),
         'Provide exactly one of adFlow or controller.',
       ),
       assert(
         config == null || adFlow != null,
         'config is only used with adFlow.',
       );

  /// The facade to mint this placement's controller from (recommended path).
  final AdFlow? adFlow;

  /// Per-placement override of the global native config ([adFlow] mode).
  final NativeConfig? config;

  /// An externally created controller (advanced path).
  final NativeAdController? controller;

  /// Whether unmounting disposes [controller] (ignored in [adFlow] mode —
  /// a self-created controller is always owned).
  final bool ownsController;

  /// Height of the slot: reserved from the first frame and kept once the ad
  /// is in. Defaults to the controller's estimate (template minimums, 100 for
  /// factory rendering). The width is always the full width the widget is
  /// given.
  ///
  /// Ignored while ads are disabled ([AdFlow.disableAds]): a Remove-Ads native
  /// ad always collapses to a zero footprint.
  final double? placeholderHeight;

  @override
  State<AdFlowNativeAd> createState() => _AdFlowNativeAdState();
}

class _AdFlowNativeAdState extends State<AdFlowNativeAd> {
  late NativeAdController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  void _adopt() {
    final adFlow = widget.adFlow;
    if (adFlow != null) {
      _controller = adFlow.native(widget.config);
      _ownsController = true;
    } else {
      _controller = widget.controller!;
      _ownsController = widget.ownsController;
    }
    _controller.load();
  }

  @override
  void didUpdateWidget(AdFlowNativeAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt a changed source — the ADR-029 safety net: dispose the old
    // controller if we owned it and start the new one's load ([initState]
    // only ran for the very first source). A stable source is a no-op.
    final sourceChanged = widget.adFlow != null
        ? !identical(oldWidget.adFlow, widget.adFlow) ||
              oldWidget.config != widget.config
        : !identical(oldWidget.controller, widget.controller);
    if (sourceChanged) {
      if (_ownsController) _controller.dispose();
      _adopt();
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Widget-first mode: listen to the facade's Remove-Ads notifier so the ad
    // collapses SYNCHRONOUSLY the instant disableAds() flips it, without waiting
    // for the asynchronous recheckGate(). Advanced controller mode has no
    // notifier, so it relies on the AdBlocked(adsDisabled) state instead.
    final adsEnabled = widget.adFlow?.adsEnabled;
    final height = widget.placeholderHeight ?? _controller.reservedHeight;
    // Listenable.merge tolerates a null entry, so adsEnabled (absent in
    // advanced controller mode) is passed straight through.
    return ListenableBuilder(
      listenable: Listenable.merge([_controller.state, adsEnabled]),
      builder: (context, _) {
        final state = _controller.state.value;
        // Remove-Ads must reclaim ALL layout space, overriding any explicit
        // placeholderHeight: a disabled native ad has a zero footprint. Either
        // the facade's adsEnabled notifier (widget-first, synchronous) or the
        // AdBlocked(adsDisabled) state (advanced controller mode) triggers it.
        final adsDisabled =
            (adsEnabled != null && !adsEnabled.value) ||
            (state is AdBlocked && state.reason == AdBlockReason.adsDisabled);
        if (adsDisabled) return const SizedBox.shrink();
        final handle = _controller.handle;
        // ONE box in every state: the full width the slot is given, at the
        // reserved height. The loaded ad is a platform view, which takes the
        // biggest size its constraints allow, so a placeholder with no width
        // of its own was 0 wide under a loose parent (Center, Align, a centred
        // Column, a padded card) and the slot jumped to full width when the ad
        // came.
        //
        // A LimitedBox around an infinite width, deliberately not a
        // LayoutBuilder:
        // - bounded width: the SizedBox fills it, before and after the load;
        // - unbounded width (a Row child without Expanded, a horizontal list):
        //   LimitedBox caps it, so the box takes the least width it is allowed
        //   instead of throwing on an infinite one, as AdFlowBanner's
        //   placeholder does;
        // - intrinsic sizing keeps working: a LayoutBuilder cannot report
        //   intrinsic dimensions and throws under IntrinsicWidth, which is
        //   what AlertDialog wraps its content in (a native ad in an exit
        //   dialog).
        return LimitedBox(
          maxWidth: 0,
          child: SizedBox(
            width: double.infinity,
            height: height,
            // Keyed by handle identity so a handle replacement (reload,
            // adopted controller) remounts the plugin's AdWidget instead of
            // updating it in place — see AdFlowBanner for the full mechanism
            // (the plugin's AdWidget cannot re-point its platform view at a
            // new ad).
            child: state is AdLoaded && handle != null
                ? KeyedSubtree(
                    key: ObjectKey(handle),
                    child: handle.buildWidget(),
                  )
                : null,
          ),
        );
      },
    );
  }
}
