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
}
