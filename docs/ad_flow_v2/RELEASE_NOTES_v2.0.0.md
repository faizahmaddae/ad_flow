# ad_flow 2.0.0

A ground-up rewrite on **`google_mobile_ads ^9.0.0`** — cleaner, policy-compliant, revenue-optimized, and fully testable. Upgrading from 1.x? See **[MIGRATION.md](MIGRATION.md)**.

## Highlights

- **Non-blocking init.** Your app renders instantly — consent, ATT, and ad loads all resolve in the background. No frozen splash, even on slow networks.
- **Consent-first, always.** UMP gate; nothing loads before consent (and before the request config is applied). Optional, localizable **consent + ATT priming screens** (opt-in) to lift opt-in rates — the presenter-based successor to v1's `initializeWithExplainer`.
- **Every format.** Banner (anchored & inline adaptive + collapsible), interstitial, rewarded, **rewarded interstitial** (with the policy-required intro/skip screen), native (Dart templates + platform factories), and app-open.
- **Policy-safe defaults.** Per-format **and** global frequency caps, app-open warm-start-only with the 4-hour expiry, interstitial action-pacing, and layout-shift-free banners.
- **Revenue-minded plumbing.** One ad always kept warm (load → show → reload on dismiss), exponential backoff + jitter with automatic re-arm, and impression-level revenue via `onPaidEvent`.
- **Testable by design.** Everything runs behind an `AdSdk` seam; `package:ad_flow/ad_flow_testing.dart` ships `FakeAdSdk` so you can unit-test your integration with no device.
- **Experimental Next-Gen SDK** opt-in on Android: build with `--dart-define=USE_NEXT_GEN_SDK=true` (same Dart API, no code changes).

## Fixed vs 1.x

- App-open ads no longer mis-fire on iOS `inactive` (Control Center / permission dialogs / app switcher) — foreground is detected via `AppStateEventNotifier`.
- No two full-screen ads ever overlap; banner/native recover after being disabled or while consent is pending.
- A required GDPR consent form is **never** suppressed by an ATT denial (ATT and GDPR are independent).

## Breaking changes

- Requires **Flutter ≥ 3.38.1, Dart ≥ 3.10, iOS 13, Android minSdk 24 / compileSdk 36**.
- New dependency-injected, presenter-based API; the v1 `Easy*` widgets and managers are replaced. Full field-by-field and symbol-by-symbol mapping in **[MIGRATION.md](MIGRATION.md)**.

---

*Full details in [CHANGELOG.md](CHANGELOG.md). Remember to publish and verify your `app-ads.txt` (required by AdMob since Jan 2025).*
