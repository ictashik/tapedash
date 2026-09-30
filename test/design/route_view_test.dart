// Where the route panel looks (DESIGN.md 6.12): a scale and an offset, always
// covering the panel, zooming about the point under the fingers.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/route_view.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

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

  group('the chase camera', () {
    const car = Offset(120, 60);

    test(
      'it keeps the car in the middle of the panel, while the zoom arrives',
      () {
        view.chaseTo(car, scale: 40);

        for (var i = 0; i < 120; i++) {
          rig.motion.tick();
          final at = view.toScreen(car);
          expect(at.dx, closeTo(200, 1e-6), reason: 'frame $i');
          expect(at.dy, closeTo(100, 1e-6), reason: 'frame $i');
        }
        settle();
        expect(view.scale, closeTo(40, 0.05));
      },
    );

    test('it goes further in than a pinch does', () {
      view.chaseTo(car, scale: 300);
      rig.run(const Duration(seconds: 8));

      expect(view.scale, greaterThan(RouteViewController.maxScale));
      expect(view.scale, closeTo(300, 1));
    });

    test('the zoom is held to what a replay allows', () {
      view.chaseTo(car, scale: 99999);
      rig.run(const Duration(seconds: 30));

      expect(view.scale, closeTo(TapeReplay.chaseMaxScale, 1));
    });

    test('heading up turns the map, and a point ahead of the car is up', () {
      // The car heads east (0 rad on the panel): up is -90 degrees from that.
      view.chaseTo(car, scale: 10, rotation: -1.5707963267948966);
      rig.run(const Duration(seconds: 6));

      final ahead = view.toScreen(car + const Offset(5, 0));
      expect(ahead.dx, closeTo(200, 1e-3), reason: 'straight up from the car');
      expect(ahead.dy, lessThan(100));
    });

    test('toRoute undoes toScreen at any turn', () {
      view.chaseTo(car, scale: 10, rotation: 0.7);
      rig.run(const Duration(seconds: 6));

      for (final p in const [Offset(0, 0), Offset(300, 40), Offset(120, 60)]) {
        final back = view.toRoute(view.toScreen(p));
        expect(back.dx, closeTo(p.dx, 1e-6));
        expect(back.dy, closeTo(p.dy, 1e-6));
      }
    });

    test('it turns the short way round: from 170 to -170 degrees is 20', () {
      view.chaseTo(car, scale: 10, rotation: 2.96);
      rig.run(const Duration(seconds: 6));
      view.chaseTo(car, scale: 10, rotation: -2.96);
      var widest = 0.0;
      for (var i = 0; i < 360; i++) {
        rig.motion.tick();
        widest = widest < (view.rotation - 2.96).abs()
            ? (view.rotation - 2.96).abs()
            : widest;
      }

      // It passes through pi, never through 0.
      expect(widest, lessThan(1.0));
    });

    test('a pinch changes how close the camera sits, and keeps the car', () {
      view.chaseTo(car, scale: 20);
      rig.run(const Duration(seconds: 6));

      view.zoomAt(const Offset(50, 50), 2);
      view.chaseTo(car, scale: 20);
      rig.run(const Duration(seconds: 6));

      expect(view.chaseBias, 2);
      expect(view.scale, closeTo(40, 0.1));
      expect(view.isChasing, isTrue);
      expect(view.toScreen(car).dx, closeTo(200, 1e-6));
    });

    test('the bias is held between its limits, and a double-tap resets it', () {
      view.chaseTo(car, scale: 20);
      view.zoomAt(Offset.zero, 1000);
      expect(view.chaseBias, TapeReplay.biasMax);
      view.zoomAt(Offset.zero, 1e-6);
      expect(view.chaseBias, TapeReplay.biasMin);

      view.doubleTap(Offset.zero);
      expect(view.chaseBias, 1);
    });

    test('the zoom buttons bring the camera closer and further', () {
      view.chaseTo(car, scale: 20);

      view.zoomIn();
      expect(view.chaseBias, closeTo(TapeReplay.biasStep, 1e-9));
      view.zoomOut();
      view.zoomOut();
      expect(view.chaseBias, closeTo(1 / TapeReplay.biasStep, 1e-9));
    });

    test('one finger dragging lets go of the car: north up, where it was', () {
      view.chaseTo(car, scale: 20, rotation: 1.0);
      rig.run(const Duration(seconds: 6));

      view.panBy(const Offset(10, 0));
      rig.run(const Duration(seconds: 4));

      expect(view.isChasing, isFalse);
      expect(view.rotation, closeTo(0, 1e-3));
      expect(view.scale, closeTo(20, 0.1));
    });

    test('once let go, the view is held to the route\'s panel again', () {
      view.chaseTo(const Offset(390, 190), scale: 20);
      rig.run(const Duration(seconds: 6));
      view.endChase();
      rig.run(const Duration(seconds: 4));

      expect(view.offset.dx, lessThanOrEqualTo(1e-6));
      expect(view.offset.dx, greaterThanOrEqualTo(400 * (1 - 20) - 1e-6));
      // A pinch from here does not snap the zoom back to the pinch's limit.
      view.zoomAt(const Offset(200, 100), 1.1);
      expect(view.scale, greaterThan(20));
    });

    test('fit lets go of the car and shows the whole route, north up', () {
      view.chaseTo(car, scale: 20, rotation: 1.0);
      rig.run(const Duration(seconds: 6));

      view.reset();
      rig.run(const Duration(seconds: 4));

      expect(view.isChasing, isFalse);
      expect(view.scale, closeTo(1, 1e-3));
      expect(view.rotation, closeTo(0, 1e-3));
      expect(view.offset.dx, closeTo(0, 1e-3));
    });

    test('it stops asking for frames once it has arrived', () {
      view.chaseTo(car, scale: 20, rotation: 0.5);
      rig.run(const Duration(seconds: 20));

      expect(rig.motion.attachedCount, 0);
    });

    test('the buttons\' flags change only when a button\'s state does', () {
      var changes = 0;
      view.flags.addListener(() => changes++);

      view.chaseTo(car, scale: 20);
      final start = changes;
      rig.run(const Duration(seconds: 3));

      expect(changes, start, reason: 'frames of a move are not changes');
      expect(view.flags.value & 4, isNot(0), reason: 'chasing');
    });
  });

  group('the route\'s car', () {
    test('it is placed in place, and says so', () {
      final car = RouteCar();
      var n = 0;
      car.addListener(() => n++);

      expect(car.visible, isFalse);
      car.place(3.5, 10, 20, 0.5);
      expect(car.visible, isTrue);
      expect(car.x, 10);
      expect(car.heading, 0.5);
      car.hide();
      expect(car.visible, isFalse);
      car.hide();
      expect(n, 2, reason: 'hiding twice says nothing the second time');
    });
  });
}
