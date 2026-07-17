import 'package:flutter/widgets.dart';

import '../config/ad_flow_config.dart';
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
  /// exact size for fixed banners, or a device-aware estimate for
  /// adaptive banners (see [_estimatedHeight]) — pass this explicitly for
  /// adaptive placements if you know the real height in advance (e.g.
  /// from a previous load) to avoid any residual shift (review finding
  /// #8).
  final double? placeholderHeight;

  @override
  State<AdFlowBanner> createState() => _AdFlowBannerState();
}

class _AdFlowBannerState extends State<AdFlowBanner> {
  bool _loadRequested = false;
  int? _requestedWidth;

  @override
  void didUpdateWidget(AdFlowBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If a different controller is passed in on rebuild, adopt it: dispose
    // the old one (if we owned it) and re-arm the first-load path so the new
    // controller loads on the next layout pass. Without this, a caller that
    // (mistakenly) builds a fresh controller inside build() would leak the
    // old controller and never re-request against the new one.
    if (!identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.ownsController) oldWidget.controller.dispose();
      _loadRequested = false;
      _requestedWidth = null;
    }
  }

  @override
  void dispose() {
    if (widget.ownsController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite) {
          final width = constraints.maxWidth.truncate();
          if (!_loadRequested) {
            _loadRequested = true;
            _requestedWidth = width;
            // Kick off the first load with the real layout width.
            widget.controller.load(width: width);
          } else if (width != _requestedWidth) {
            // The placement got wider or narrower — a rotation, an unfolding
            // device, or a resizable/split-screen window. An adaptive banner is
            // requested FOR a width, so the ad we have is now the wrong size:
            // re-request at the new one. Guarded on an ACTUAL width change, so a
            // plain rebuild (or a keyboard opening, which changes height only)
            // never re-requests an ad — that would be an ad-request storm.
            _requestedWidth = width;
            widget.controller.resize(width);
          }
        }
        return ListenableBuilder(
          // Both, not just `state`: a client-side refresh swap (ADR-041) goes
          // AdLoaded → AdLoaded, which does not notify, so a widget listening
          // only to `state` would keep rendering the old, disposed handle.
          listenable: Listenable.merge([
            widget.controller.state,
            widget.controller.revision,
          ]),
          builder: (context, _) {
            final state = widget.controller.state.value;
            final handle = widget.controller.handle;
            if (state is AdLoaded && handle != null) {
              return SizedBox(
                width: handle.size.width,
                height: handle.size.height,
                // Keyed by HANDLE IDENTITY, so a refresh swap (ADR-041)
                // unmounts the old AdWidget element and mounts a fresh one.
                // The plugin's AdWidget has no didUpdateWidget: its platform
                // view captures the ad id at creation and the framework only
                // recreates a platform view when its viewType changes (it
                // never does — one constant per plugin). Without the key, a
                // rebuild with a NEW handle updates the old element in place
                // and the screen keeps hosting the platform view of the
                // just-DISPOSED ad — a permanently dead slot that still
                // requests and pays for fresh ads it never displays
                // (2026-07 audit).
                child: KeyedSubtree(
                  key: ObjectKey(handle),
                  child: handle.buildWidget(),
                ),
              );
            }
            return SizedBox(
              width: constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : null,
              height: widget.placeholderHeight ?? _estimatedHeight(context),
            );
          },
        );
      },
    );
  }

  /// A better placeholder estimate than [BannerAdController.reservedHeight]
  /// for adaptive kinds: Google documents anchored adaptive banners as
  /// 50–90dp, capped at 15% of device height (review finding #8 — there is
  /// no pure-width formula, so this can't be exact). Reserving the upper
  /// end of that range — rather than the 50dp floor — means a same-size-
  /// or-smaller real ad never pushes content below it down when it loads,
  /// which is the direction that risks "Layout Encourages Accidental
  /// Clicks" enforcement; the cost is some unused placeholder whitespace
  /// on devices where the real ad lands shorter. Fixed sizes stay exact.
  double _estimatedHeight(BuildContext context) {
    if (widget.controller.kind == BannerKind.fixed) {
      return widget.controller.reservedHeight;
    }
    final deviceHeight = MediaQuery.sizeOf(context).height;
    return (deviceHeight * 0.15).clamp(50.0, 90.0);
  }
}
