// A first look at the money readout and the Money Tape. Skipped unless
// TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/money.dart';
import 'package:tapedash/ui/design/components/numeral_format.dart';
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

  testWidgets('the readout: calibrated, calibrating, uncalibrated, approx', (
    tester,
  ) async {
    setWindow(tester, const Size(360, 300));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    SmoothedSignal sig(double v) {
      final s = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      s.ingest(
        Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
      );
      return s;
    }

    final a = sig(342);
    final b = sig(342);
    final c = sig(342);
    final d = sig(6.4);

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyReadout(
                  value: a,
                  format: const NumeralFormat(integerDigits: 4),
                  confidence: MoneyConfidence.calibrated,
                ),
                const SizedBox(height: 12),
                MoneyReadout(
                  value: b,
                  format: const NumeralFormat(integerDigits: 4),
                  confidence: MoneyConfidence.calibrating,
                ),
                const SizedBox(height: 12),
                MoneyReadout(
                  value: c,
                  format: const NumeralFormat(integerDigits: 4),
                  confidence: MoneyConfidence.uncalibrated,
                  approximate: true,
                ),
                const SizedBox(height: 12),
                MoneyReadout(
                  value: d,
                  format: const NumeralFormat(integerDigits: 2, decimals: 1),
                  confidence: MoneyConfidence.calibrated,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, 'money-readout');
    for (final s in [a, b, c, d]) {
      s.dispose();
    }
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);

  testWidgets('the tape: vertical, all four buckets, freshly grown', (
    tester,
  ) async {
    setWindow(tester, const Size(120, 300));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    var blocks = const <MoneyBlock>[
      MoneyBlock(MoneyBucket.normal),
      MoneyBlock(MoneyBucket.idling),
      MoneyBlock(MoneyBucket.hardAcceleration),
      MoneyBlock(MoneyBucket.highSpeed),
      MoneyBlock(MoneyBucket.normal),
      MoneyBlock(MoneyBucket.normal),
    ];
    final key = GlobalKey();

    Widget build() => tapeHarness(
      kit: kit,
      motion: motion,
      theme: TapeThemeData(livery: Liveries.ion),
      child: TapeBackdrop(
        child: Center(
          child: MoneyTape(key: key, blocks: blocks, length: 260),
        ),
      ),
    );

    await tester.pumpWidget(build());
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, 'money-tape-vertical');

    // Append one more block: the newest should be flashing and the stack
    // should be mid-settle right after.
    blocks = [...blocks, const MoneyBlock(MoneyBucket.hardAcceleration)];
    await tester.pumpWidget(build());
    await tester.pump();
    await capturePng(tester, 'money-tape-fresh-block');

    motion.dispose();
    kit.dispose();
  }, skip: !enabled);

  testWidgets('the tape: horizontal, Drive-floor variant', (tester) async {
    setWindow(tester, const Size(320, 80));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    const blocks = <MoneyBlock>[
      MoneyBlock(MoneyBucket.normal),
      MoneyBlock(MoneyBucket.normal),
      MoneyBlock(MoneyBucket.idling),
      MoneyBlock(MoneyBucket.idling),
      MoneyBlock(MoneyBucket.hardAcceleration),
      MoneyBlock(MoneyBucket.highSpeed),
      MoneyBlock(MoneyBucket.normal),
    ];

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: MoneyTape(blocks: blocks, length: 280, vertical: false),
          ),
        ),
      ),
    );
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, 'money-tape-horizontal');
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
