// The telemetry tile (DESIGN.md 6.6): the sparkline's ring buffer and sampling
// rate, and the brackets tinting live, not just at build time.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/numeral_format.dart';
import 'package:tapedash/ui/design/components/telemetry_tile.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/design/tokens/telemetry_tile.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late SmoothedSignal value;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    value = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.gauge,
    );
  });

  tearDown(() {
    value.dispose();
    motion.dispose();
    kit.dispose();
  });

  void ingest(double v) {
    final now = clock.monotonic();
    value.ingest(Reading(value: v, at: now, receivedAt: now));
  }

  /// Advances both clocks together, real seconds.
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

  Future<TelemetryTileState> show(
    WidgetTester tester, {
    double? cautionBelow,
    double? criticalBelow,
    double? cautionAbove,
    double? criticalAbove,
  }) async {
    setWindow(tester, const Size(300, 200));
    final key = GlobalKey<TelemetryTileState>();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: Center(
          child: TelemetryTile(
            key: key,
            label: 'RPM',
            value: value,
            format: const NumeralFormat(integerDigits: 4),
            cautionBelow: cautionBelow,
            criticalBelow: criticalBelow,
            cautionAbove: cautionAbove,
            criticalAbove: criticalAbove,
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  group('the sparkline (DESIGN.md 6.6)', () {
    testWidgets('samples every 500 ms (2 Hz), oldest first', (tester) async {
      final state = await show(tester);
      ingest(1000);
      await tester.pump();

      for (var i = 0; i < 6; i++) {
        ingest(1000.0 + i * 100);
        run(const Duration(milliseconds: 500));
        await tester.pump();
      }

      final samples = state.samplesOldestFirst();
      expect(samples, isNotEmpty);
      // The signal is a spring (spring.gauge) continuously retargeted every
      // 500 ms, so the last sample trails the just-ingested value rather than
      // hitting it exactly; the rising trend is the thing being checked.
      expect(samples.last, closeTo(1500, 100));
      expect(samples.first, lessThan(samples.last));
    });

    testWidgets('does not sample faster than 500 ms', (tester) async {
      final state = await show(tester);
      ingest(1000);
      await tester.pump();

      run(const Duration(milliseconds: 100));
      final countAt100ms = state.samplesOldestFirst().length;
      run(const Duration(milliseconds: 100));
      final countAt200ms = state.samplesOldestFirst().length;

      expect(countAt100ms, countAt200ms);
    });

    testWidgets('the ring buffer holds at most 120 points (60 s at 2 Hz)', (
      tester,
    ) async {
      final state = await show(tester);
      ingest(1000);
      await tester.pump();

      run(const Duration(seconds: 90));

      expect(
        state.samplesOldestFirst().length,
        TapeTelemetryTile.sparklinePoints,
      );
    });
  });

  group('the brackets (DESIGN.md 6.6)', () {
    Future<Uint32List> pixels(WidgetTester tester) async {
      final image = await renderImage(tester);
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      return Uint32List.fromList([
        for (var i = 0; i < image.width * image.height; i++)
          data.getUint32(i * 4),
      ]);
    }

    int count(Uint32List pixels, int rgba) =>
        pixels.where((p) => p == rgba).length;

    testWidgets('are etch.strong when the value is in range', (tester) async {
      await show(tester, cautionAbove: 5500, criticalAbove: 6500);
      ingest(3000);
      run(const Duration(seconds: 1));
      await tester.pump();

      final p = await pixels(tester);
      expect(count(p, 0xFFB020FF), 0);
      expect(count(p, 0xFF3355FF), 0);
    });

    testWidgets('tint caution above the caution threshold', (tester) async {
      await show(tester, cautionAbove: 5500, criticalAbove: 6500);
      ingest(5800);
      run(const Duration(seconds: 1));
      await tester.pump();

      expect(count(await pixels(tester), 0xFFB020FF), greaterThan(5));
    });

    testWidgets('tint critical above the critical threshold', (tester) async {
      await show(tester, cautionAbove: 5500, criticalAbove: 6500);
      ingest(6800);
      run(const Duration(seconds: 1));
      await tester.pump();

      expect(count(await pixels(tester), 0xFF3355FF), greaterThan(5));
    });

    testWidgets('respond to the value live: a rebuild is not required', (
      tester,
    ) async {
      // A regression test: the zone was originally computed once in build(),
      // so a live value crossing a threshold between rebuilds left the
      // brackets showing a stale zone (DESIGN.md 9.3: widgets never rebuild
      // for live data, so anything that must react to it belongs in the
      // painter, read fresh on every repaint).
      await show(tester, cautionAbove: 5500);
      ingest(3000);
      run(const Duration(seconds: 1));
      await tester.pump();
      expect(count(await pixels(tester), 0xFFB020FF), 0);

      ingest(5800);
      run(const Duration(seconds: 1));
      await tester.pump();

      expect(count(await pixels(tester), 0xFFB020FF), greaterThan(5));
    });

    testWidgets('below-threshold zones work the same way as above', (
      tester,
    ) async {
      await show(tester, cautionBelow: 500, criticalBelow: 200);
      ingest(100);
      run(const Duration(seconds: 1));
      await tester.pump();

      expect(count(await pixels(tester), 0xFF3355FF), greaterThan(5));
    });
  });

  group('cost', () {
    testWidgets('keeps ticking while it has a value', (tester) async {
      await show(tester);
      ingest(3000);
      await tester.pump();

      expect(motion.attachedCount, greaterThan(0));
    });

    testWidgets('with no reading yet, costs the clock nothing', (tester) async {
      await show(tester);

      expect(motion.attachedCount, 0);
    });
  });
}
