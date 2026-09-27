// Fidelity tier detection and the runtime governor (DESIGN.md 9.1 and 9.2).
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/fidelity/frame_probe.dart';
import 'package:tapedash/ui/design/fidelity/governor.dart';
import 'package:tapedash/ui/design/fidelity/tier_detector.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

/// [count] frames that each cost [ms].
List<double> _frames(double ms, [int count = 60]) => List.filled(count, ms);

void main() {
  group('percentile', () {
    test('is the nearest rank', () {
      final values = [for (var i = 1; i <= 10; i++) i.toDouble()];

      expect(percentile(values, 0.9), 9);
      expect(percentile(values, 0.5), 5);
      expect(percentile(values, 1), 10);
      expect(percentile(values, 0.01), 1);
    });

    test('does not need its input sorted, and does not sort it', () {
      final values = [5.0, 1.0, 9.0, 3.0];

      expect(percentile(values, 0.5), 3);
      expect(values, [5.0, 1.0, 9.0, 3.0]);
    });

    test('is null for nothing, and the value itself for one', () {
      expect(percentile([], 0.9), isNull);
      expect(percentile([7], 0.9), 7);
    });

    test('a few slow frames among many fast ones do not move the 90th', () {
      final values = [..._frames(5, 95), ..._frames(50, 5)];

      expect(percentile(values, 0.9), 5);
    });
  });

  group('TierDetector (DESIGN.md 9.2)', () {
    const detector = TierDetector();

    test('a fast phone gets Full, on the display\'s own rate', () {
      final decision = detector.decide(frameMilliseconds: _frames(4));

      expect(decision.tier, FidelityTier.full);
      expect(decision.fpsCap, isNull);
    });

    test('a middling phone gets Balanced at 60', () {
      final decision = detector.decide(frameMilliseconds: _frames(8));

      expect(decision.tier, FidelityTier.balanced);
      expect(decision.fpsCap, 60);
    });

    test('a slow phone gets Lite at 60', () {
      final decision = detector.decide(frameMilliseconds: _frames(14));

      expect(decision.tier, FidelityTier.lite);
      expect(decision.fpsCap, 60);
    });

    test('a phone too slow even for Lite gets Lite at 30 fps', () {
      final decision = detector.decide(frameMilliseconds: _frames(30));

      expect(decision.tier, FidelityTier.lite);
      expect(decision.fpsCap, 30);
    });

    test('the 90th percentile decides, so a few hitches do not', () {
      final frames = [..._frames(8, 3), ..._frames(12, 50)];
      // 12 ms on Balanced is 15 ms with headroom: it fits.
      expect(
        detector.decide(frameMilliseconds: frames).tier,
        FidelityTier.balanced,
      );

      final worse = [..._frames(8, 30), ..._frames(30, 30)];
      expect(detector.decide(frameMilliseconds: worse).tier, FidelityTier.lite);
    });

    test('a 120 Hz display asks more of Full, since its budget is 8.3 ms', () {
      expect(
        detector.decide(frameMilliseconds: _frames(3), displayHz: 120).tier,
        FidelityTier.full,
      );
      // 4 ms is fine for Balanced and too much for Full at 120 Hz.
      expect(
        detector.decide(frameMilliseconds: _frames(4), displayHz: 120).tier,
        FidelityTier.balanced,
      );
      expect(
        detector.decide(frameMilliseconds: _frames(4), displayHz: 60).tier,
        FidelityTier.full,
      );
    });

    test('needs 25% headroom, exactly', () {
      // Balanced at 13.3 ms is 16.7 with headroom: on the budget, so it fits.
      final onTheLine = detector.decide(frameMilliseconds: _frames(13.33));
      expect(onTheLine.tier, FidelityTier.balanced);

      final over = detector.decide(frameMilliseconds: _frames(13.5));
      expect(over.tier, FidelityTier.lite);
    });

    test('too few frames to judge give the middle tier', () {
      expect(
        detector.decide(frameMilliseconds: _frames(4, 5)).tier,
        FidelityTier.balanced,
      );
      expect(
        detector.decide(frameMilliseconds: const []).tier,
        FidelityTier.balanced,
      );
    });

    test('a cold open drawn at Lite is read against what Lite costs', () {
      const liteBenchmark = TierDetector(benchmarkTier: FidelityTier.lite);

      // 6 ms at Lite is 10 ms at Balanced, and 17 ms at Full: Balanced fits, Full does not.
      expect(
        liteBenchmark.decide(frameMilliseconds: _frames(6)).tier,
        FidelityTier.balanced,
      );
      expect(
        liteBenchmark.decide(frameMilliseconds: _frames(3)).tier,
        FidelityTier.full,
      );
    });

    test('the decision says what it saw', () {
      final decision = detector.decide(frameMilliseconds: _frames(8));

      expect(decision.p90Milliseconds, 8);
      expect(decision, detector.decide(frameMilliseconds: _frames(8)));
      expect(decision.toString(), contains('BALANCED'));
    });

    test(
      'the costs run Lite, Balanced, Full, and budgets follow the tier\'s rate',
      () {
        expect(
          TierDetector.relativeCost(FidelityTier.lite),
          lessThan(TierDetector.relativeCost(FidelityTier.balanced)),
        );
        expect(
          TierDetector.relativeCost(FidelityTier.balanced),
          lessThan(TierDetector.relativeCost(FidelityTier.full)),
        );
        expect(
          TierDetector.budgetMilliseconds(FidelityTier.balanced, 120),
          closeTo(16.67, 0.01),
        );
        expect(
          TierDetector.budgetMilliseconds(FidelityTier.full, 120),
          closeTo(8.33, 0.01),
        );
        expect(
          TierDetector.budgetMilliseconds(FidelityTier.full, 30),
          closeTo(16.67, 0.01),
        );
      },
    );
  });

  group('TierGovernor (DESIGN.md 9.2)', () {
    late FakeClock clock;

    setUp(() => clock = FakeClock());

    TierGovernor governor(
      FidelityTier tier, {
      int? fps = 60,
      GovernorConfig? config,
    }) {
      final g = TierGovernor(
        clock: clock,
        initial: TierDecision(tier: tier, fpsCap: fps, p90Milliseconds: 5),
        config: config ?? const GovernorConfig(),
      );
      addTearDown(g.dispose);
      return g;
    }

    /// Feeds [ms] frames, 60 a second, for [seconds].
    void run(TierGovernor g, double ms, int seconds) {
      for (var s = 0; s < seconds; s++) {
        g.onFrames(_frames(ms));
        clock.advance(const Duration(seconds: 1));
      }
    }

    test('starts at the detected tier', () {
      final g = governor(FidelityTier.balanced);

      expect(
        g.state.value,
        const TierState(
          tier: FidelityTier.balanced,
          fpsCap: 60,
          reason: TierReason.detected,
        ),
      );
    });

    test('frames within the budget change nothing, however long', () {
      final g = governor(FidelityTier.full, fps: null);

      run(g, 10, 60);

      expect(g.state.value.tier, FidelityTier.full);
    });

    test('steps down one tier after 5 s over budget', () {
      final g = governor(FidelityTier.full, fps: null);

      run(g, 25, 4);
      expect(g.state.value.tier, FidelityTier.full, reason: 'not yet');
      run(g, 25, 3);

      expect(g.state.value.tier, FidelityTier.balanced);
      expect(g.state.value.reason, TierReason.governor);
    });

    test('and again after another 5 s: Balanced to Lite', () {
      final g = governor(FidelityTier.balanced);

      run(g, 25, 8);

      expect(g.state.value.tier, FidelityTier.lite);
      expect(g.state.value.fpsCap, 60);
    });

    test(
      'at Lite, over budget for 5 s more, it falls back to 30 fps, once',
      () {
        final g = governor(FidelityTier.lite);

        run(g, 25, 20);

        expect(
          g.state.value,
          const TierState(
            tier: FidelityTier.lite,
            fpsCap: 30,
            reason: TierReason.governor,
          ),
        );
        final seen = <TierState>[];
        g.state.addListener(() => seen.add(g.state.value));
        run(g, 40, 20);
        expect(seen, isEmpty, reason: 'there is nothing lower to fall to');
      },
    );

    test('at 30 fps the budget is 33 ms, so 25 ms frames are fine', () {
      final g = governor(FidelityTier.lite, fps: 30);

      run(g, 25, 30);

      expect(g.state.value.fpsCap, 30);
      expect(g.state.value.reason, TierReason.detected);
    });

    test('a good stretch resets the count', () {
      final g = governor(FidelityTier.balanced);

      run(g, 25, 4);
      run(g, 8, 4);
      run(g, 25, 4);

      expect(g.state.value.tier, FidelityTier.balanced);
    });

    test('never steps up, however good the frames get', () {
      final g = governor(FidelityTier.balanced);
      run(g, 25, 8);
      expect(g.state.value.tier, FidelityTier.lite);

      run(g, 2, 120);

      expect(g.state.value.tier, FidelityTier.lite);
    });

    test('needs enough frames in the window to act on', () {
      final g = governor(FidelityTier.balanced);

      for (var s = 0; s < 30; s++) {
        g.onFrames(
          _frames(40, 5),
        ); // five slow frames a second: too few to judge
        clock.advance(const Duration(seconds: 1));
      }

      expect(g.state.value.tier, FidelityTier.balanced);
    });

    test('old frames age out of the window', () {
      final g = governor(FidelityTier.balanced);
      run(g, 25, 3);
      clock.advance(const Duration(seconds: 30));
      run(g, 8, 10);

      expect(g.state.value.tier, FidelityTier.balanced);
    });

    test('announces a change once, and never a non-change', () {
      final g = governor(FidelityTier.balanced);
      final seen = <TierState>[];
      g.state.addListener(() => seen.add(g.state.value));

      run(g, 8, 30);
      expect(seen, isEmpty);

      run(g, 25, 7);
      expect(seen, hasLength(1));
    });

    group('a chosen tier', () {
      test('is held: the governor does not step it down', () {
        final g = governor(FidelityTier.balanced);

        g.pin(FidelityTier.full);
        run(g, 40, 30);

        expect(
          g.state.value,
          const TierState(
            tier: FidelityTier.full,
            fpsCap: null,
            reason: TierReason.user,
          ),
        );
        expect(g.pinnedTier, FidelityTier.full);
      });

      test(
        'automatic again lets the governor work, from the tier it is at',
        () {
          final g = governor(FidelityTier.balanced);
          g.pin(FidelityTier.full);

          g.pin(null);
          run(g, 25, 7);

          expect(g.state.value.tier, FidelityTier.balanced);
          expect(g.pinnedTier, isNull);
        },
      );
    });

    group('a hot phone (DESIGN.md 9.2)', () {
      test('goes to Lite at 30 fps above 50 C', () {
        final g = governor(FidelityTier.full, fps: null);

        g.onBatteryTemperature(51);

        expect(
          g.state.value,
          const TierState(
            tier: FidelityTier.lite,
            fpsCap: 30,
            reason: TierReason.thermal,
          ),
        );
      });

      test('50 C itself is not hot, and neither is no reading', () {
        final g = governor(FidelityTier.full, fps: null);

        g.onBatteryTemperature(50);
        g.onBatteryTemperature(null);
        g.onBatteryTemperature(35);

        expect(g.state.value.tier, FidelityTier.full);
      });

      test(
        'stays there when it cools: the tier does not step up during a trip',
        () {
          final g = governor(FidelityTier.full, fps: null);
          g.onBatteryTemperature(52);

          g.onBatteryTemperature(40);
          run(g, 3, 60);

          expect(g.state.value.tier, FidelityTier.lite);
          expect(g.state.value.reason, TierReason.thermal);
        },
      );

      test('overrides a chosen tier', () {
        final g = governor(FidelityTier.balanced);
        g.pin(FidelityTier.full);

        g.onBatteryTemperature(55);
        g.pin(FidelityTier.full);

        expect(g.state.value.tier, FidelityTier.lite);
      });
    });

    test('the crossfade of a step is 400 ms', () {
      expect(
        const GovernorConfig().crossfade,
        const Duration(milliseconds: 400),
      );
      expect(const GovernorConfig().overBudgetFor, const Duration(seconds: 5));
      expect(TapeMotion.tierCrossfade, const Duration(milliseconds: 400));
    });
  });

  group('FrameProbe', () {
    FrameTiming timing({required int buildMicros, required int rasterMicros}) =>
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: buildMicros,
          rasterStart: buildMicros,
          rasterFinish: buildMicros + rasterMicros,
          rasterFinishWallTime: buildMicros + rasterMicros,
          frameNumber: 1,
        );

    test('a frame costs the longer of its build and its raster time', () {
      expect(
        FrameProbe.costOf(timing(buildMicros: 3000, rasterMicros: 9000)),
        9,
      );
      expect(
        FrameProbe.costOf(timing(buildMicros: 12000, rasterMicros: 4000)),
        12,
      );
    });

    testWidgets(
      'hands the frames of the engine to its callback, and stops when told',
      (tester) async {
        final seen = <double>[];
        final probe = FrameProbe(
          seen.addAll,
          binding: SchedulerBinding.instance,
        )..start();
        addTearDown(probe.stop);

        SchedulerBinding.instance.platformDispatcher.onReportTimings?.call([
          timing(buildMicros: 2000, rasterMicros: 6000),
          timing(buildMicros: 7000, rasterMicros: 1000),
        ]);
        probe.stop();
        SchedulerBinding.instance.platformDispatcher.onReportTimings?.call([
          timing(buildMicros: 9000, rasterMicros: 9000),
        ]);

        expect(seen, [6, 7]);
      },
    );
  });

  group('the fps cap', () {
    test('a manual clock keeps the cap it is given', () {
      final clock = ManualMotionClock();
      addTearDown(clock.dispose);
      expect(clock.maxFps, isNull);

      clock.maxFps = 30;

      expect(clock.maxFps, 30);
    });

    testWidgets(
      'a vsync clock at 30 fps steps about half as often, and time still runs true',
      (tester) async {
        final clock = VsyncMotionClock();
        addTearDown(clock.dispose);
        final counter = _Steps();
        clock.attach(counter);

        await tester.pump();
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(microseconds: 16667));
        }
        final full = counter.steps;
        final fullTime = clock.now;

        clock.detach(counter);
        final capped = VsyncMotionClock()..maxFps = 30;
        addTearDown(capped.dispose);
        final slow = _Steps();
        capped.attach(slow);
        await tester.pump();
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(microseconds: 16667));
        }

        expect(full, closeTo(60, 3));
        expect(slow.steps, closeTo(30, 4));
        expect(
          capped.now.inMilliseconds,
          closeTo(fullTime.inMilliseconds, 60),
          reason: 'motion is not slowed, only coarser',
        );
        capped.detach(slow);
      },
    );
  });
}

class _Steps implements MotionDriven {
  int steps = 0;

  @override
  bool advance(double dt, Duration time) {
    steps++;
    return true;
  }
}
