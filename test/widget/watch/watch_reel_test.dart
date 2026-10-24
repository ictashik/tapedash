// The watch's reel of faces (DESIGN.md 16.5, 16.6): what the bezel, a swipe and a tap
// do, what Motion locks, the rubber-band and the lock glyph, and the return to
// the speed when the car starts moving.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/watch/page_ticks.dart';
import 'package:tapedash/ui/design/components/watch/watch_face.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/pages/watch/watch_reel.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  const face = WatchFace(225);
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late ValueNotifier<DrivingMode> mode;
  late StreamController<int> bezel;
  late List<int> tapped;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock();
    mode = ValueNotifier(DrivingMode.parked);
    bezel = StreamController<int>.broadcast();
    tapped = [];
  });

  tearDown(() {
    bezel.close();
    motion.dispose();
    kit.dispose();
  });

  void run(Duration d) {
    var left = d.inMicroseconds;
    while (left > 0) {
      final step = left < 16667 ? left : 16667;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  Future<void> boot(WidgetTester tester, {bool tapHook = false}) async {
    setWindow(tester, const Size(225, 225));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: WatchReel(
          key: const ValueKey('reel'),
          face: face,
          motion: motion,
          mode: mode,
          rotary: bezel.stream,
          onTapFace: tapHook
              ? (i) {
                  tapped.add(i);
                  return i == 3;
                }
              : null,
          faces: [
            for (final n in ['drive', 'money', 'where', 'menu'])
              Center(child: Text(n, key: ValueKey(n))),
          ],
        ),
      ),
    );
  }

  WatchReelState reel(WidgetTester tester) =>
      tester.state<WatchReelState>(find.byType(WatchReel));

  Future<void> turn(WidgetTester tester, int detents) async {
    bezel.add(detents);
    await tester.pump();
    run(const Duration(milliseconds: 900));
    await tester.pump();
  }

  Future<void> swipeUp(WidgetTester tester) async {
    await tester.fling(find.byType(WatchReel), const Offset(0, -120), 900);
    await tester.pump();
    run(const Duration(milliseconds: 900));
    await tester.pump();
  }

  group('the reach', () {
    test('Motion reaches Drive and Money and Parked all of them', () {
      expect(WatchReel.reachOf(DrivingMode.motion, 4, 2), (0, 1));
      expect(WatchReel.reachOf(DrivingMode.parked, 4, 2), (0, 3));
      expect(WatchReel.reachOf(DrivingMode.motion, 1, 2), (0, 0));
    });

    test('a drag past a lock gives a little and holds', () {
      const give = TapeMotion.lockedSwipeGive;
      expect(WatchReel.resisted(0.5, 0, 1), 0.5);
      expect(WatchReel.resisted(1.5, 0, 1), closeTo(1 + give * 0.5, 1e-9));
      expect(WatchReel.resisted(9, 0, 1), closeTo(1 + give, 1e-9));
      expect(WatchReel.resisted(-3, 0, 1), closeTo(-give, 1e-9));
    });
  });

  group('parked', () {
    testWidgets('the bezel turns one face a detent, clockwise to the next', (
      tester,
    ) async {
      await boot(tester);
      expect(reel(tester).current, 0);
      await turn(tester, 1);
      expect(reel(tester).current, 1);
      await turn(tester, 1);
      expect(reel(tester).current, 2);
      await turn(tester, -1);
      expect(reel(tester).current, 1);
    });

    testWidgets('the bezel stops at the ends', (tester) async {
      await boot(tester);
      await turn(tester, -1);
      expect(reel(tester).current, 0);
      for (var i = 0; i < 6; i++) {
        await turn(tester, 1);
      }
      expect(reel(tester).current, 3);
    });

    testWidgets('a swipe up goes on and a swipe down comes back', (
      tester,
    ) async {
      await boot(tester);
      await swipeUp(tester);
      expect(reel(tester).current, 1);
      await tester.fling(find.byType(WatchReel), const Offset(0, 120), 900);
      await tester.pump();
      run(const Duration(milliseconds: 900));
      await tester.pump();
      expect(reel(tester).current, 0);
    });

    testWidgets('a tap goes to the next face and round from the last', (
      tester,
    ) async {
      await boot(tester);
      for (final want in [1, 2, 3, 0]) {
        await tester.tap(find.byType(WatchReel));
        await tester.pump();
        run(const Duration(milliseconds: 900));
        await tester.pump();
        expect(reel(tester).current, want);
      }
    });

    testWidgets('a face can take the tap itself, and the reel stays put', (
      tester,
    ) async {
      await boot(tester, tapHook: true);
      reel(tester).goTo(3);
      run(const Duration(milliseconds: 900));
      await tester.pump();
      await tester.tap(find.byType(WatchReel));
      await tester.pump();
      run(const Duration(milliseconds: 900));
      expect(tapped.last, 3);
      expect(reel(tester).current, 3);
    });

    testWidgets('the page ticks follow: four of them parked', (tester) async {
      await boot(tester);
      expect(reel(tester).reachable.value, 4);
      expect(find.byType(PageTicks), findsOneWidget);
    });
  });

  group('Motion', () {
    testWidgets('only Drive and Money, and the tap goes round the two', (
      tester,
    ) async {
      mode.value = DrivingMode.motion;
      await boot(tester);
      expect(reel(tester).reachable.value, 2);
      for (final want in [1, 0, 1]) {
        await tester.tap(find.byType(WatchReel));
        await tester.pump();
        run(const Duration(milliseconds: 900));
        await tester.pump();
        expect(reel(tester).current, want);
      }
    });

    testWidgets('the bezel past Money is refused, with the lock glyph', (
      tester,
    ) async {
      mode.value = DrivingMode.motion;
      await boot(tester);
      await turn(tester, 1);
      expect(reel(tester).current, 1);
      expect(find.byType(TapeIconView), findsNothing);
      await turn(tester, 1);
      // It stays on Money, and says why for a moment.
      expect(reel(tester).current, 1);
      await tester.pump();
      bezel.add(1);
      // One frame to take the turn and one to draw what it set.
      await tester.pump();
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is TapeIconView && w.icon == TapeIcon.lock,
        ),
        findsOneWidget,
      );
      run(TapeMotion.lockGlyph + const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(TapeIconView), findsNothing);
    });

    testWidgets('a swipe past Money springs back and shows the lock', (
      tester,
    ) async {
      mode.value = DrivingMode.motion;
      await boot(tester);
      await swipeUp(tester);
      expect(reel(tester).current, 1);
      await swipeUp(tester);
      expect(reel(tester).current, 1);
      expect(reel(tester).debugPosition, closeTo(1, 0.02));
    });

    testWidgets(
      'a face left on when the car moves goes back to the speed in time',
      (tester) async {
        await boot(tester);
        reel(tester).goTo(3);
        run(const Duration(milliseconds: 900));
        await tester.pump();
        expect(reel(tester).current, 3);
        expect(reel(tester).reachable.value, 4);

        mode.value = DrivingMode.motion;
        await tester.pump();
        expect(reel(tester).reachable.value, 2);
        // Inside the 300 ms the motion return allows (DESIGN.md 7.2).
        run(TapeMotion.motionReturn);
        await tester.pump();
        expect(reel(tester).debugPosition, closeTo(1, 0.1));
        run(const Duration(milliseconds: 600));
        expect(reel(tester).debugPosition, closeTo(1, 0.01));
      },
    );
  });

  testWidgets(
    'a face is only mounted while it is, or is next to, the one shown',
    (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('drive')), findsOneWidget);
      expect(find.byKey(const ValueKey('where')), findsNothing);
      expect(find.byKey(const ValueKey('menu')), findsNothing);
    },
  );

  testWidgets('goTo is held to what the mode reaches', (tester) async {
    mode.value = DrivingMode.motion;
    await boot(tester);
    reel(tester).goTo(3);
    run(const Duration(milliseconds: 900));
    await tester.pump();
    expect(reel(tester).current, 1);
  });
}
