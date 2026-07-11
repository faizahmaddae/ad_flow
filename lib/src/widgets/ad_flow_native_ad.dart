import 'package:flutter/widgets.dart';

import '../controllers/native_ad_controller.dart';
import '../core/ad_load_state.dart';

/// Drop-in native ad widget.
///
/// Reserves a fixed height from the first frame (no layout shift), triggers
/// the load, hosts the ad once loaded, and disposes with the element when
/// it owns the controller.
class AdFlowNativeAd extends StatefulWidget {
  /// Creates a native ad widget driven by [controller].
  ///
  /// Set [ownsController] when this widget should dispose [controller] on
  /// unmount (true when the controller was created just for this widget).
  const AdFlowNativeAd({
    required this.controller,
    this.ownsController = false,
    this.placeholderHeight,
    super.key,
  });

  /// The controller that loads this slot.
  final NativeAdController controller;

  /// Whether unmounting disposes [controller].
  final bool ownsController;

  /// Height reserved for the ad. Defaults to the controller's estimate
  /// (template minimums, 100 for factory rendering).
  final double? placeholderHeight;

  @override
  State<AdFlowNativeAd> createState() => _AdFlowNativeAdState();
}

class _AdFlowNativeAdState extends State<AdFlowNativeAd> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    if (widget.ownsController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.placeholderHeight ?? widget.controller.reservedHeight;
    return ValueListenableBuilder(
      valueListenable: widget.controller.state,
      builder: (context, state, _) {
        final handle = widget.controller.handle;
        return SizedBox(
          height: height,
          child: state is AdLoaded && handle != null
              ? handle.buildWidget()
              : null,
        );
      },
    );
  }
}
