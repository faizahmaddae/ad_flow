import 'package:flutter/widgets.dart';

import '../config/ad_flow_config.dart';
import '../controllers/banner_ad_controller.dart';
import '../core/ad_block_reason.dart';
import '../core/ad_load_state.dart';
import '../facade/ad_flow.dart';

/// Drop-in banner widget.
///
/// Reserves a fixed height from the first frame (no layout shift — shifting
/// ads trigger accidental-click policy enforcement), triggers the first
/// load with its real layout width, hosts the ad once loaded, and disposes
/// the controller it owns when unmounted.
///
/// The recommended usage (3.0) creates and owns the controller internally —
/// the "fresh controller minted inside build()" footgun (ADR-029, a
/// permanently blank ad) is unrepresentable this way:
///
/// ```dart
/// AdFlowBanner(adFlow: ads)                       // global banner config
/// AdFlowBanner(adFlow: ads, config: BannerConfig(...)) // per-placement
/// ```
///
/// Advanced: pass your own [controller] instead (with [ownsController] to
/// transfer disposal), e.g. to share state inspection with other widgets.
class AdFlowBanner extends StatefulWidget {
  /// Creates a banner widget.
  ///
  /// Provide exactly one of [adFlow] (the widget creates and owns a
  /// controller — recommended) or [controller] (advanced; set
  /// [ownsController] when this widget should dispose it on unmount).
  /// [config] optionally overrides the global banner config and requires
  /// [adFlow].
  const AdFlowBanner({
    this.adFlow,
    this.config,
    this.controller,
    this.ownsController = false,
    this.placeholderHeight,
    this.backgroundColor,
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

  /// Per-placement override of the global banner config ([adFlow] mode).
  final BannerConfig? config;

  /// An externally created controller (advanced path).
  final BannerAdController? controller;

  /// Whether unmounting disposes [controller] (ignored in [adFlow] mode —
  /// a self-created controller is always owned).
  final bool ownsController;

  /// Height reserved before the ad loads.
  ///
  /// When omitted, the default depends on the banner [kind]
  /// (see [_AdFlowBannerState._placeholderHeight]):
  /// - **fixed** — the slot's exact configured height (no shift when it loads);
  /// - **large anchored adaptive** — the documented 50dp floor, then the exact
  ///   loaded size once the ad arrives (loaded banners always follow the live
  ///   `handle.dimensions`);
  /// - **inline adaptive** — `0`, because its real height is unknown until
  ///   `onAdLoaded`; reserving a speculative height would be wrong more often
  ///   than right.
  ///
  /// Pass an explicit value to reserve a publisher-chosen height for ordinary
  /// non-loaded states (e.g. an inline placement you know the height of in
  /// advance). `placeholderHeight: 0` opts into fully collapsed pre-load
  /// behavior — no reservation until the ad actually loads.
  ///
  /// This is **ignored while ads are disabled** ([AdFlow.disableAds]): a
  /// Remove-Ads banner always collapses to a zero footprint, whatever value is
  /// passed here.
  final double? placeholderHeight;

  /// An opaque colour painted **behind** the slot.
  ///
  /// An adaptive banner slot is anchored to its WIDTH: when AdMob fills it
  /// with a creative smaller than the slot, the SDK centres that creative and
  /// leaves the surround unpainted, so the app's own surface shows through and
  /// the ad reads as a rendering glitch. Google's anchored-adaptive guidance is
  /// to give the ad view an opaque background for exactly this case.
  ///
  /// Pass an opaque colour (typically the surface the banner sits on, e.g.
  /// `Theme.of(context).colorScheme.surface`). A translucent colour defeats the
  /// purpose and is not recommended.
  ///
  /// This paints strictly UNDER the ad — never over it. Occluding, clipping or
  /// scaling a creative is an AdMob policy violation, so there is deliberately
  /// no API for it here.
  ///
  /// Like [placeholderHeight], this is **ignored while ads are disabled**
  /// ([AdFlow.disableAds]): a Remove-Ads banner paints nothing at all.
  final Color? backgroundColor;

  @override
  State<AdFlowBanner> createState() => _AdFlowBannerState();
}

class _AdFlowBannerState extends State<AdFlowBanner> {
  late BannerAdController _controller;
  late bool _ownsController;
  bool _loadRequested = false;
  int? _requestedWidth;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  void _adopt() {
    final adFlow = widget.adFlow;
    if (adFlow != null) {
      _controller = adFlow.banner(widget.config);
      _ownsController = true;
    } else {
      _controller = widget.controller!;
      _ownsController = widget.ownsController;
    }
    _loadRequested = false;
    _requestedWidth = null;
  }

  @override
  void didUpdateWidget(AdFlowBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt a changed source: a different external controller (dispose the
    // old one if we owned it — the ADR-029 safety net for controllers
    // mistakenly built inside build()), or a different AdFlow/config in the
    // self-owned mode. A stable source hits the identical fast-path.
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
    // In widget-first mode, listen to the facade's Remove-Ads notifier so the
    // banner collapses SYNCHRONOUSLY the instant disableAds() flips it — before
    // the asynchronous controller recheckGate() has run. In advanced
    // controller mode there is no notifier to reach, so we fall back to the
    // AdBlocked(adsDisabled) state the recheck lands on (below).
    final adsEnabled = widget.adFlow?.adsEnabled;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A slot with no usable width must never request an ad. A zero-width
        // (or unbounded) placement still resolves to a VALID adaptive AdSize
        // natively — `AdSize(0, 100)`, not `AdSize.INVALID` — so nothing
        // downstream refuses it: the request goes out, a real ad loads, and it
        // renders in a zero-width box. That is a billable impression the user
        // can never see, the exact thing the seam's inline-adaptive
        // zero-height branch already refuses. Unbounded width folds into the
        // same guard (and `double.infinity.truncate()` would throw anyway).
        // A slot that later gains a width loads then, because `_loadRequested`
        // is still false; one that shrinks to zero keeps its ad and its last
        // requested width, so growing back does not re-request.
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.truncate()
            : 0;
        if (width > 0) {
          if (!_loadRequested) {
            _loadRequested = true;
            _requestedWidth = width;
            // Kick off the first load with the real layout width.
            _controller.load(width: width);
          } else if (width != _requestedWidth) {
            // The placement got wider or narrower — a rotation, an unfolding
            // device, or a resizable/split-screen window. An adaptive banner is
            // requested FOR a width, so the ad we have is now the wrong size:
            // re-request at the new one. Guarded on an ACTUAL width change, so a
            // plain rebuild (or a keyboard opening, which changes height only)
            // never re-requests an ad — that would be an ad-request storm.
            _requestedWidth = width;
            _controller.resize(width);
          }
        }
        return ListenableBuilder(
          // Both state and revision, not just `state`: a client-side refresh
          // swap (ADR-041) goes AdLoaded → AdLoaded, which does not notify, so
          // a widget listening only to `state` would keep rendering the old,
          // disposed handle. Plus adsEnabled (widget-first mode) so Remove-Ads
          // collapses the box on the same frame it is toggled.
          // Listenable.merge tolerates a null entry, so adsEnabled (absent in
          // advanced controller mode) is passed straight through.
          listenable: Listenable.merge([
            _controller.state,
            _controller.revision,
            adsEnabled,
          ]),
          builder: (context, _) {
            final state = _controller.state.value;
            // Remove-Ads must reclaim ALL layout space: a disabled banner has a
            // zero footprint, overriding any explicit placeholderHeight. This
            // is checked before the loaded/placeholder branches so it wins in
            // every state. Two independent signals, either sufficient: the
            // facade's adsEnabled notifier (widget-first mode — synchronous, on
            // the very frame disableAds() is called) and the
            // AdBlocked(adsDisabled) state the controller's recheckGate lands on
            // (the only signal available in advanced controller mode).
            final adsDisabled =
                (adsEnabled != null && !adsEnabled.value) ||
                (state is AdBlocked &&
                    state.reason == AdBlockReason.adsDisabled);
            if (adsDisabled) return const SizedBox.shrink();
            final handle = _controller.handle;
            if (state is AdLoaded && handle != null) {
              // The box follows `handle.dimensions`, not a one-shot size
              // read: AdMob's server-side auto-refresh can resolve a
              // DIFFERENT inline adaptive height for the SAME handle, and
              // without a subscription the new creative would render in the
              // old box (2026-07 audit). ValueListenableBuilder re-subscribes
              // whenever the handle (and so the listenable) changes.
              return ValueListenableBuilder(
                valueListenable: handle.dimensions,
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
                // backgroundColor paints UNDER the ad, inside the same box: an
                // adaptive slot is anchored to its WIDTH, so a creative smaller
                // than the slot is centred by the SDK and the surround is left
                // unpainted (the app's own surface shows through). Deliberately
                // a ColoredBox BEHIND the child, never a Stack on top of it —
                // occluding a creative is a policy violation.
                child: _paint(
                  KeyedSubtree(
                    key: ObjectKey(handle),
                    child: handle.buildWidget(),
                  ),
                ),
                builder: (context, size, child) => SizedBox(
                  width: size.width,
                  height: size.height,
                  child: child,
                ),
              );
            }
            return _paint(
              SizedBox(
                width: constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : null,
                height: widget.placeholderHeight ?? _placeholderHeight,
              ),
            );
          },
        );
      },
    );
  }

  /// Paints [AdFlowBanner.backgroundColor] behind [child].
  ///
  /// Deliberately an UNCONDITIONAL `DecoratedBox`, not a conditional
  /// `ColoredBox`, for two independent reasons:
  ///
  /// 1. **The tree shape must not change with the colour.** Wrapping only when
  ///    a colour is set means a null↔non-null flip (a theme change, a settings
  ///    toggle, a nullable colour source) changes the child's position in the
  ///    tree, and an `ObjectKey` is a LOCAL key — it cannot reparent, so the
  ///    whole subtree is re-inflated. Flutter builds the replacement BEFORE
  ///    unmounting the old one (verified: `initState` of the new child runs
  ///    ahead of `dispose` of the old), so the plugin's `AdWidget` would see
  ///    its ad id still registered as mounted, set `_adIdAlreadyMounted`, and
  ///    throw *"This AdWidget is already in the Widget tree"* — a permanently
  ///    dead, still-billing slot. A constant widget TYPE updates in place and
  ///    only repaints.
  /// 2. **`ColoredBox` is `HitTestBehavior.opaque`** (`_RenderColoredBox`), so
  ///    it would silently swallow gestures aimed at whatever sits under the
  ///    reserved placeholder. `RenderDecoratedBox` is a plain `RenderProxyBox`
  ///    and changes no hit testing.
  ///
  /// A `BoxDecoration` with a null colour paints nothing
  /// (`_paintBackgroundColor` is a no-op), so the default costs one proxy box
  /// and no pixels.
  Widget _paint(Widget child) => DecoratedBox(
    decoration: BoxDecoration(color: widget.backgroundColor),
    child: child,
  );

  /// The default height reserved for an ordinary (enabled, not-yet-loaded)
  /// banner — used when no explicit [AdFlowBanner.placeholderHeight] is given.
  ///
  /// Deliberately simple and deterministic (no device-height guessing):
  /// - **fixed** — the slot's exact configured height, so loading causes no
  ///   shift at all;
  /// - **large anchored adaptive** — the documented 50dp floor. Google's large
  ///   anchored adaptive banners have a documented 50dp minimum, and the
  ///   height the SDK actually renders is not knowable client-side (ADR-073);
  ///   reserving the floor (not a
  ///   speculative upper estimate) keeps the pre-load reservation minimal, and
  ///   a loaded ad simply grows the box to its exact `handle.dimensions` (60,
  ///   90, 100, 150…);
  /// - **inline adaptive** — `0`, because the real height is unknown until
  ///   `onAdLoaded` (the plugin resolves it from `getPlatformAdSize`), so any
  ///   pre-load reservation would be a guess; pass an explicit
  ///   `placeholderHeight` to reserve a known height instead.
  double get _placeholderHeight => switch (_controller.kind) {
    BannerKind.fixed => _controller.reservedHeight,
    BannerKind.anchoredAdaptive => _controller.reservedHeight,
    BannerKind.inlineAdaptive => 0,
  };
}
