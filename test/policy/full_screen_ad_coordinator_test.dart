import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FullScreenAdCoordinator coordinator;

  setUp(() => coordinator = FullScreenAdCoordinator());
  tearDown(() => coordinator.dispose());

  test('starts not visible', () {
    expect(coordinator.isFullScreenAdVisible, isFalse);
    expect(coordinator.visible.value, isFalse);
  });

  test('enter/exit toggles visibility and notifies listeners', () {
    final seen = <bool>[];
    coordinator.visible.addListener(() => seen.add(coordinator.visible.value));

    coordinator.enter();
    expect(coordinator.isFullScreenAdVisible, isTrue);
    coordinator.exit();
    expect(coordinator.isFullScreenAdVisible, isFalse);
    expect(seen, [true, false]);
  });

  test('unbalanced exit clamps at zero and never wedges', () {
    coordinator.exit();
    coordinator.exit();
    expect(coordinator.isFullScreenAdVisible, isFalse);

    coordinator.enter();
    expect(coordinator.isFullScreenAdVisible, isTrue);
    coordinator.exit();
    expect(coordinator.isFullScreenAdVisible, isFalse);
  });

  test('nested enters stay visible until fully exited (defensive)', () {
    coordinator.enter();
    coordinator.enter();
    coordinator.exit();
    expect(coordinator.isFullScreenAdVisible, isTrue);
    coordinator.exit();
    expect(coordinator.isFullScreenAdVisible, isFalse);
  });

  group('tryEnter (atomic check-and-claim)', () {
    test('claims and returns true when nothing is showing', () {
      expect(coordinator.tryEnter(), isTrue);
      expect(coordinator.isFullScreenAdVisible, isTrue);
    });

    test('refuses and does not enter when already visible', () {
      coordinator.enter();
      expect(coordinator.tryEnter(), isFalse);
      coordinator.exit();
      // A refused tryEnter must not have incremented depth — one exit is
      // enough to clear the original enter().
      expect(coordinator.isFullScreenAdVisible, isFalse);
    });

    test('two synchronous tryEnter calls: only the first wins', () {
      // Simulates two independently-gated controllers racing for the
      // coordinator in the same synchronous turn.
      final first = coordinator.tryEnter();
      final second = coordinator.tryEnter();
      expect(first, isTrue);
      expect(second, isFalse);
    });
  });

  group('view-ad click latch (ADR-042 + 2026-07 audit grace window)', () {
    late DateTime now;
    late FullScreenAdCoordinator clocked;

    setUp(() {
      now = DateTime(2026, 7, 17, 12);
      clocked = FullScreenAdCoordinator(now: () => now);
    });
    tearDown(() => clocked.dispose());

    test('open then foreground (no close event): suppressed, one-shot', () {
      clocked.noteViewAdOpened();
      expect(clocked.consumeViewAdOpened(), isTrue);
      expect(
        clocked.consumeViewAdOpened(),
        isFalse,
        reason: 'exactly one foreground event is suppressed',
      );
    });

    test('open → close → foreground moments later (Android external-browser '
        'return: onAdClosed and the foreground event both fire at resume, '
        'in either order): still suppressed', () {
      clocked.noteViewAdOpened();
      clocked.noteViewAdClosed();
      now = now.add(const Duration(milliseconds: 500));
      expect(
        clocked.consumeViewAdOpened(),
        isTrue,
        reason:
            'a close arriving just before the resume-driven foreground '
            'event is the SAME return-from-ad — clearing the latch here '
            'would show an app-open ad right behind the ad the user just '
            'left (the exact ADR-042 violation)',
      );
    });

    test('open → close → much later foreground (iOS in-app overlay: the app '
        'never backgrounded): NOT suppressed', () {
      clocked.noteViewAdOpened();
      clocked.noteViewAdClosed();
      now = now.add(const Duration(minutes: 5));
      expect(
        clocked.consumeViewAdOpened(),
        isFalse,
        reason:
            'an in-app overlay click never produces a foreground event, so '
            'a stranded latch would silently eat the NEXT genuine warm '
            'return — one lost app-open impression per banner click',
      );
    });

    test('a close without a prior open is ignored', () {
      clocked.noteViewAdClosed();
      expect(clocked.consumeViewAdOpened(), isFalse);
    });

    test('re-open after a close re-arms cleanly', () {
      clocked.noteViewAdOpened();
      clocked.noteViewAdClosed();
      now = now.add(const Duration(minutes: 5));
      expect(clocked.consumeViewAdOpened(), isFalse);

      clocked.noteViewAdOpened();
      expect(clocked.consumeViewAdOpened(), isTrue);
    });
  });
}
