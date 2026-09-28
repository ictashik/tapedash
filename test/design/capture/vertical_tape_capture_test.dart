// A first look at the vertical tape. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/numeral_format.dart';
import 'package:tapedash/ui/design/components/vertical_tape.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required double value,
    required double halfWindow,
    required double minorInterval,
    required double majorInterval,
    double? threshold,
    TapeReadoutSide side = TapeReadoutSide.right,
    bool withVelocity = false,
    NumeralFormat format = const NumeralFormat(integerDigits: 3),
  }) async {
    setWindow(tester, const Size(220, 360));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final signal = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.needle,
    );
    signal.ingest(
      Reading(
        value: value,
        at: clock.monotonic(),
        receivedAt: clock.monotonic(),
      ),
    );

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: VerticalTape(
              value: signal,
              halfWindow: halfWindow,
              minorTickInterval: minorInterval,
              majorTickInterval: majorInterval,
              format: format,
              width: 60,
              height: 360,
              readoutSide: side,
              thresholdValue: threshold,
            ),
          ),
        ),
      ),
    );
    motion.advance(const Duration(milliseconds: 400));
    if (withVelocity) {
      // A second, higher ingest shortly after: leaves the spring with real
      // velocity so the trend vector has something to show.
      signal.ingest(
        Reading(
          value: value + 20,
          at: clock.monotonic(),
          receivedAt: clock.monotonic(),
        ),
      );
      motion.advance(const Duration(milliseconds: 80));
    }
    await tester.pump();
    await capturePng(tester, name);
    signal.dispose();
    motion.dispose();
    kit.dispose();
  }

  testWidgets(
    'speed tape, readout on the right (tape on the left of a cluster)',
    (tester) async {
      await shot(
        tester,
        'tape-speed-right',
        value: 62,
        halfWindow: 30,
        minorInterval: 5,
        majorInterval: 10,
        withVelocity: true,
      );
    },
    skip: !enabled,
  );

  testWidgets('RPM tape, readout on the left, near the redline', (
    tester,
  ) async {
    await shot(
      tester,
      'tape-rpm-left',
      value: 6100,
      halfWindow: 2000,
      minorInterval: 250,
      majorInterval: 1000,
      threshold: 6500,
      side: TapeReadoutSide.left,
      format: const NumeralFormat(integerDigits: 4),
    );
  }, skip: !enabled);

  testWidgets('a value near the bottom of its window', (tester) async {
    await shot(
      tester,
      'tape-speed-low',
      value: 8,
      halfWindow: 30,
      minorInterval: 5,
      majorInterval: 10,
    );
  }, skip: !enabled);
}
