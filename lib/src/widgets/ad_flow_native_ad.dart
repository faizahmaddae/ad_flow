import 'package:flutter/widgets.dart';

import '../config/ad_flow_config.dart';
import '../controllers/native_ad_controller.dart';
import '../core/ad_load_state.dart';
import '../facade/ad_flow.dart';

/// Drop-in native ad widget.
///
/// Reserves a fixed height from the first frame (no layout shift), triggers
/// the load, hosts the ad once loaded, and disposes the controller it owns
/// when unmounted.
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

  /// Height reserved for the ad. Defaults to the controller's estimate
  /// (template minimums, 100 for factory rendering).
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
    final height = widget.placeholderHeight ?? _controller.reservedHeight;
    return ValueListenableBuilder(
      valueListenable: _controller.state,
      builder: (context, state, _) {
        final handle = _controller.handle;
        return SizedBox(
          height: height,
          // Keyed by handle identity so a handle replacement (reload, adopted
          // controller) remounts the plugin's AdWidget instead of updating it
          // in place — see AdFlowBanner for the full mechanism (the plugin's
          // AdWidget cannot re-point its platform view at a new ad).
          child: state is AdLoaded && handle != null
              ? KeyedSubtree(
                  key: ObjectKey(handle),
                  child: handle.buildWidget(),
                )
              : null,
        );
      },
    );
  }
}
