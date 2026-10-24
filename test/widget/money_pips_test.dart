// The confidence pips sit on the digits' baseline at any size (DESIGN.md 6.8). They
// used to sit at the top of the numerals' box, which is two pitches tall, so at 44 lp
// they floated 50 lp above the digits.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/money.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/money.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  for (final size in [20.0, 32.0, 44.0, 72.0, 110.0]) {
    testWidgets('the pips rest on the digits\' baseline at $size lp', (
      tester,
    ) async {
      setWindow(tester, const Size(400, 400));
      final kit = TapeRenderKit();
      final motion = ManualMotionClock();
      final clock = FakeClock();
      final value = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: Center(
            child: MoneyReadout(
              value: value,
              format: const NumeralFormat(integerDigits: 2),
              confidence: MoneyConfidence.calibrating,
              size: size,
            ),
          ),
        ),
      );
      final pips = tester.getRect(find.byType(ConfidencePips));
      final digits = tester.getRect(find.byType(RollingNumerals));
      final baseline = digits.top + NumeralMetrics(size).baseline;
      expect(pips.bottom, closeTo(baseline, 0.5));
      expect(pips.height, TapeMoney.confidencePipSize);
      // And beside the digits, not over them.
      expect(pips.left, greaterThanOrEqualTo(digits.right));
      motion.dispose();
      kit.dispose();
    });
  }
}
