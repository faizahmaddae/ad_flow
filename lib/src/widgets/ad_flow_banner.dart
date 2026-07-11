import 'package:flutter/widgets.dart';

import '../controllers/banner_ad_controller.dart';
import '../core/ad_load_state.dart';

/// Drop-in banner widget.
///
/// Reserves a fixed height from the first frame (no layout shift — shifting
/// ads trigger accidental-click policy enforcement), triggers the first
/// load with its real layout width, hosts the ad once loaded, and disposes
/// with the element when it owns the controller.
class AdFlowBanner extends StatefulWidget {
  /// Creates a banner widget driven by [controller].
  ///
  /// Set [ownsController] when this widget should dispose [controller] on
  /// unmount (true when the controller was created just for this widget).
  const AdFlowBanner({
    required this.controller,
    this.ownsController = false,
    this.placeholderHeight,
    super.key,
  });

  /// The controller that loads this slot.
  final BannerAdController controller;

  /// Whether unmounting disposes [controller].
  final bool ownsController;

  /// Height reserved before the ad loads. Defaults to the controller's
  /// estimate (exact for fixed sizes, 50px for adaptive).
  final double? placeholderHeight;

  @override
  State<AdFlowBanner> createState() => _AdFlowBannerState();
}

class _AdFlowBannerState extends State<AdFlowBanner> {
  bool _loadRequested = false;

  @override
  void dispose() {
    if (widget.ownsController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_loadRequested && constraints.maxWidth.isFinite) {
          _loadRequested = true;
          // Kick off the first load with the real layout width.
          widget.controller.load(width: constraints.maxWidth.truncate());
        }
        return ValueListenableBuilder(
          valueListenable: widget.controller.state,
          builder: (context, state, _) {
            final handle = widget.controller.handle;
            if (state is AdLoaded && handle != null) {
              return SizedBox(
                width: handle.size.width,
                height: handle.size.height,
                child: handle.buildWidget(),
              );
            }
            return SizedBox(
              width: constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : null,
              height:
                  widget.placeholderHeight ?? widget.controller.reservedHeight,
            );
          },
        );
      },
    );
  }
}
