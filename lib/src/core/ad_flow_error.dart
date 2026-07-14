/// Classifies where in the ad pipeline an [AdFlowError] originated.
enum AdFlowErrorKind {
  /// An ad failed to load (maps to the SDK's `onAdFailedToLoad`).
  loadFailed,

  /// A loaded full-screen ad failed to show
  /// (maps to `onAdFailedToShowFullScreenContent`).
  showFailed,

  /// A UMP consent operation failed (maps to a UMP `FormError`).
  consent,

  /// An internal ad_flow timeout elapsed.
  timeout,

  /// The supplied configuration is invalid or incomplete for the operation.
  invalidConfig,

  /// Anything that does not fit the categories above.
  unknown,
}

/// A typed error surfaced by ad_flow.
///
/// Implements [Exception] so the SDK seam and controllers can throw it
/// directly; it is also carried inside the `AdFailed` load state.
class AdFlowError implements Exception {
  /// Creates an error of the given [kind] with a human-readable [message].
  const AdFlowError(this.kind, this.message, {this.code, this.domain});

  /// What part of the pipeline produced this error.
  final AdFlowErrorKind kind;

  /// Human-readable description (safe to log).
  final String message;

  /// Underlying SDK error code, when one exists
  /// (e.g. `LoadAdError.code` or `FormError.errorCode`).
  final int? code;

  /// Underlying SDK error domain, when one exists (e.g. `LoadAdError.domain`).
  final String? domain;

  @override
  bool operator ==(Object other) =>
      other is AdFlowError &&
      other.kind == kind &&
      other.message == message &&
      other.code == code &&
      other.domain == domain;

  @override
  int get hashCode => Object.hash(kind, message, code, domain);

  @override
  String toString() =>
      'AdFlowError(${kind.name}, $message'
      '${code != null ? ', code: $code' : ''}'
      '${domain != null ? ', domain: $domain' : ''})';
}

/// Normalizes any thrown object into an [AdFlowError] of [fallbackKind].
///
/// The seam's documented contract is that it only ever throws [AdFlowError],
/// but a platform channel does not honour contracts: `MissingPluginException`,
/// `PlatformException` and plain `StateError`s all reach us from the plugin in
/// the wild. Every layer that must DEGRADE rather than wedge (controller loads
/// and shows, the consent flow) funnels its catches through this, so an
/// unexpected type becomes a normal `AdFailed`/`lastError` instead of an
/// escaping async error that leaves a slot pinned forever.
AdFlowError asAdFlowError(Object error, AdFlowErrorKind fallbackKind) =>
    error is AdFlowError ? error : AdFlowError(fallbackKind, '$error');
