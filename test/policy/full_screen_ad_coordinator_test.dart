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
}
