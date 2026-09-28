// The road view (DESIGN.md 6.11): truthful dash motion, body pitch/roll,
// the brake threshold, streak density, and the road's own cost discipline
// (it keeps ticking at 0 km/h, unlike an intermittent effect).
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/road_view.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/design/tokens/road_view.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  group(
    'RoadViewPainter.pitchDegreesFor / rollDegreesFor (DESIGN.md 6.11)',
    () {
      test('0 accel is 0 degrees', () {
        expect(RoadViewPainter.pitchDegreesFor(0), 0);
        expect(RoadViewPainter.rollDegreesFor(0), 0);
      });

      test('is linear up to 1g, then clamps', () {
        const g = 9.81;
        expect(
          RoadViewPainter.pitchDegreesFor(g / 2),
          closeTo(TapeRoadView.pitchMaxDegrees / 2, 1e-9),
        );
        expect(
          RoadViewPainter.pitchDegreesFor(g),
          TapeRoadView.pitchMaxDegrees,
        );
        expect(
          RoadViewPainter.pitchDegreesFor(g * 3),
          TapeRoadView.pitchMaxDegrees,
        );
        expect(
          RoadViewPainter.pitchDegreesFor(-g * 3),
          -TapeRoadView.pitchMaxDegrees,
        );
      });

      test('roll uses its own, different maximum', () {
        const g = 9.81;
        expect(RoadViewPainter.rollDegreesFor(g), TapeRoadView.rollMaxDegrees);
        expect(
          TapeRoadView.rollMaxDegrees,
          isNot(TapeRoadView.pitchMaxDegrees),
        );
      });
    },
  );

  group('RoadViewPainter.isBraking (DESIGN.md 6.11)', () {
    test('is false at and below the threshold', () {
      expect(RoadViewPainter.isBraking(0), isFalse);
      expect(RoadViewPainter.isBraking(-TapeRoadView.brakeThreshold), isFalse);
      // accelerating, not decelerating, however hard.
      expect(RoadViewPainter.isBraking(8), isFalse);
    });

    test('is true once deceleration passes the threshold', () {
      expect(
        RoadViewPainter.isBraking(-TapeRoadView.brakeThreshold - 0.1),
        isTrue,
      );
      expect(RoadViewPainter.isBraking(-6), isTrue);
    });
  });

  group('RoadViewPainter.streakCountFor (DESIGN.md 6.11)', () {
    test('is 0 at and below the threshold speed', () {
      expect(RoadViewPainter.streakCountFor(0, 40), 0);
      expect(
        RoadViewPainter.streakCountFor(TapeRoadView.streakThresholdKmh, 40),
        0,
      );
    });

    test(
      'rises to maxStreaks at the full-density speed, and clamps beyond it',
      () {
        expect(
          RoadViewPainter.streakCountFor(TapeRoadView.streakFullDensityKmh, 40),
          40,
        );
        expect(RoadViewPainter.streakCountFor(300, 40), 40);
      },
    );

    test('scales with the tier\'s own cap: 0 for Lite (maxStreaks 0)', () {
      expect(RoadViewPainter.streakCountFor(120, 0), 0);
    });

    test('is proportional in between', () {
      final mid =
          (TapeRoadView.streakThresholdKmh +
              TapeRoadView.streakFullDensityKmh) /
          2;
      expect(RoadViewPainter.streakCountFor(mid, 40), closeTo(20, 1));
    });
  });

  group('drawing', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;
    late FakeClock clock;
    late SmoothedSignal speed;
    late SmoothedSignal rpm;
    late SmoothedSignal longAccel;
    late SmoothedSignal latAccel;

    setUp(() {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
      clock = FakeClock()..advance(const Duration(seconds: 100));
      speed = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      rpm = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      longAccel = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.needle,
      );
      latAccel = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.needle,
      );
    });

    tearDown(() {
      speed.dispose();
      rpm.dispose();
      longAccel.dispose();
      latAccel.dispose();
      motion.dispose();
      kit.dispose();
    });

    void ingest(SmoothedSignal s, double v) {
      final now = clock.monotonic();
      s.ingest(Reading(value: v, at: now, receivedAt: now));
    }

    void run(Duration duration) {
      var left = duration.inMicroseconds;
      const frame = 16667;
      while (left > 0) {
        final step = left < frame ? left : frame;
        motion.tick(step / 1e6);
        clock.advance(Duration(microseconds: step));
        left -= step;
      }
    }

    Future<RoadViewState> show(WidgetTester tester) async {
      setWindow(tester, const Size(400, 200));
      final key = GlobalKey<RoadViewState>();
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: RoadView(
            key: key,
            speed: speed,
            rpm: rpm,
            maxRpm: 6500,
            longitudinalAcceleration: longAccel,
            lateralAcceleration: latAccel,
            width: 400,
            height: 200,
          ),
        ),
      );
      return key.currentState!;
    }

    group('truthful motion (DESIGN.md 6.11)', () {
      testWidgets('the road is perfectly still at 0 km/h', (tester) async {
        final state = await show(tester);
        ingest(speed, 0);
        run(const Duration(seconds: 5));
        await tester.pump();
        expect(state.dashPhase, 0);
      });

      testWidgets(
        'once settled, phase advances by exactly the distance travelled',
        (tester) async {
          final state = await show(tester);
          ingest(speed, 36); // 36 km/h = 10 m/s exactly.
          // spring.gauge (no overshoot, stiffness 380) settles to within
          // 1% in well under a second; 3 s is comfortably enough that the
          // speed is constant for everything that follows.
          run(const Duration(seconds: 3));
          final before = state.dashPhase;

          run(const Duration(seconds: 2)); // 20 m at a now-constant 10 m/s.
          final after = state.dashPhase;

          final expectedDelta =
              (20 / TapeRoadView.dashPeriodMetres) % 1.0; // 20/6 m, wrapped.
          final actualDelta = (after - before) % 1.0;
          expect(actualDelta, closeTo(expectedDelta, 0.01));
        },
      );
    });

    group('cost', () {
      testWidgets('attaches once speed has a value', (tester) async {
        await show(tester);
        expect(motion.attachedCount, 0);
        ingest(speed, 10);
        await tester.pump();
        expect(motion.attachedCount, greaterThan(0));
      });

      testWidgets(
        'unlike a search pulse or an alert, stays attached at 0 km/h: '
        'the scene, not an intermittent effect, is what Motion mode shows',
        (tester) async {
          await show(tester);
          ingest(speed, 10);
          await tester.pump();
          final attachedWhileMoving = motion.attachedCount;

          ingest(speed, 0);
          run(const Duration(seconds: 2));
          await tester.pump();
          expect(motion.attachedCount, attachedWhileMoving);
        },
      );
    });

    group('drawing', () {
      Future<Uint32List> pixels(WidgetTester tester) async {
        final image = await renderImage(tester);
        late ByteData data;
        await tester.runAsync(() async => data = (await image.toByteData())!);
        return Uint32List.fromList([
          for (var i = 0; i < image.width * image.height; i++)
            data.getUint32(i * 4),
        ]);
      }

      testWidgets('tail lights are critical while braking hard', (
        tester,
      ) async {
        await show(tester);
        ingest(speed, 40);
        ingest(longAccel, -4); // past TapeRoadView.brakeThreshold.
        run(const Duration(seconds: 1));
        await tester.pump();

        expect(
          (await pixels(tester)).where((v) => v == 0xFF3355FF).length,
          greaterThan(0),
        );
      });

      testWidgets('tail lights are not critical while merely cruising', (
        tester,
      ) async {
        await show(tester);
        ingest(speed, 40);
        ingest(longAccel, 0);
        run(const Duration(seconds: 1));
        await tester.pump();

        expect((await pixels(tester)).where((v) => v == 0xFF3355FF).length, 0);
      });

      testWidgets('responds to a live value with no rebuild needed', (
        tester,
      ) async {
        await show(tester);
        ingest(speed, 40);
        ingest(longAccel, 0);
        run(const Duration(seconds: 1));
        await tester.pump();
        expect((await pixels(tester)).where((v) => v == 0xFF3355FF).length, 0);

        ingest(longAccel, -5);
        run(const Duration(seconds: 1));
        await tester.pump();
        expect(
          (await pixels(tester)).where((v) => v == 0xFF3355FF).length,
          greaterThan(0),
        );
      });
    });
  });
}
