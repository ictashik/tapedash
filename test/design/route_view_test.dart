// Where the route panel looks (DESIGN.md 6.12): a scale and an offset, always
// covering the panel, zooming about the point under the fingers.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/route_view.dart';

import 'support/motion_rig.dart';

void main() {
  late MotionRig rig;
  late RouteViewController view;

  setUp(() {
    rig = MotionRig();
    view = RouteViewController(clock: rig.motion)..size = const Size(400, 200);
  });

  tearDown(() {
    view.dispose();
    rig.dispose();
  });

  void settle() => rig.run(const Duration(seconds: 2));

  test('it starts on the whole route', () {
    expect(view.scale, 1);
    expect(view.offset, Offset.zero);
    expect(view.isZoomed, isFalse);
  });

  test(
    'a pinch zooms about the point under the fingers: it stays under them',
    () {
      const focal = Offset(300, 120);
      final before = view.toRoute(focal);

      view.zoomAt(focal, 3);

      expect(view.scale, closeTo(3, 1e-9));
      expect(view.toScreen(before).dx, closeTo(focal.dx, 1e-9));
      expect(view.toScreen(before).dy, closeTo(focal.dy, 1e-9));
    },
  );

  test('zoom is between 1 and 24', () {
    view.zoomAt(const Offset(200, 100), 1000);
    expect(view.scale, RouteViewController.maxScale);

    view.zoomAt(const Offset(200, 100), 0.0001);
    expect(view.scale, 1);
    expect(view.offset, Offset.zero);
  });

  test('the route always covers the panel: it cannot be dragged off', () {
    view.zoomAt(const Offset(0, 0), 4);

    view.panBy(const Offset(500, 500));
    expect(view.offset, Offset.zero, reason: 'against the top left');

    view.panBy(const Offset(-5000, -5000));
    // The far edge of the route sits at the panel's far edge: 400 * (1 - 4).
    expect(view.offset.dx, -1200);
    expect(view.offset.dy, -600);
  });

  test('zooming out at an edge does not leave a gap', () {
    view.zoomAt(const Offset(400, 200), 4);
    view.panBy(const Offset(-5000, -5000));

    view.zoomAt(const Offset(400, 200), 0.5);

    expect(view.scale, closeTo(2, 1e-9));
    expect(view.offset.dx, greaterThanOrEqualTo(400 * (1 - 2) - 1e-9));
    expect(view.offset.dx, lessThanOrEqualTo(0));
  });

  test('the buttons and a double-tap move on a spring, and arrive', () {
    view.zoomIn();
    expect(view.scale, 1, reason: 'not at once');
    settle();
    expect(view.scale, closeTo(2, 1e-3));

    view.zoomIn();
    settle();
    expect(view.scale, closeTo(4, 1e-3));

    view.zoomOut();
    settle();
    expect(view.scale, closeTo(2, 1e-3));

    view.reset();
    settle();
    expect(view.scale, closeTo(1, 1e-3));
    expect(view.offset.dx.abs(), lessThan(1e-3));
  });

  test('the spring never leaves the route short of the panel on its way', () {
    view.animateZoomAt(const Offset(390, 190), 6);
    for (var i = 0; i < 90; i++) {
      rig.run(const Duration(milliseconds: 16));
      final o = view.offset;
      final s = view.scale;
      expect(o.dx, lessThanOrEqualTo(1e-6));
      expect(
        o.dx + 400 * s,
        greaterThanOrEqualTo(400 - 1e-3),
        reason: 'frame $i',
      );
      expect(
        o.dy + 200 * s,
        greaterThanOrEqualTo(200 - 1e-3),
        reason: 'frame $i',
      );
    }
  });

  test('a double-tap goes in by 2.5, and back out when already well in', () {
    view.doubleTap(const Offset(100, 100));
    settle();
    expect(view.scale, closeTo(2.5, 1e-3));

    view.doubleTap(const Offset(100, 100));
    settle();
    expect(view.scale, closeTo(6.25, 1e-2));

    view.doubleTap(const Offset(100, 100));
    settle();
    expect(view.scale, closeTo(1, 1e-3), reason: 'well in: back to the route');
  });

  test(
    'follow brings an off-screen point to the middle, and leaves a near one',
    () {
      view.zoomAt(const Offset(0, 0), 5);
      // The route point (350, 180) is far off to the lower right.
      view.follow(const Offset(350, 180));
      settle();

      final p = view.toScreen(const Offset(350, 180));
      expect(p.dx, greaterThan(400 * 0.15));
      expect(p.dx, lessThan(400 * 0.85));
      expect(p.dy, greaterThan(200 * 0.15));
      expect(p.dy, lessThan(200 * 0.85));

      final before = view.offset;
      view.follow(view.toRoute(const Offset(200, 100)));
      settle();
      expect(view.offset, before, reason: 'already in view');
    },
  );

  test('follow does nothing when the whole route is showing', () {
    view.follow(const Offset(390, 190));
    settle();

    expect(view.offset, Offset.zero);
  });

  test('a new panel size keeps the view valid', () {
    view.zoomAt(const Offset(400, 200), 3);
    view.panBy(const Offset(-5000, -5000));

    view.size = const Size(200, 100);

    expect(view.offset.dx, greaterThanOrEqualTo(200 * (1 - 3) - 1e-9));
    expect(view.offset.dy, greaterThanOrEqualTo(100 * (1 - 3) - 1e-9));
  });

  test('resetNow is at once', () {
    view.zoomAt(const Offset(100, 100), 5);

    view.resetNow();

    expect(view.scale, 1);
    expect(view.offset, Offset.zero);
  });
}
