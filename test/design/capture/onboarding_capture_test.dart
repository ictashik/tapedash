// The cold open and the choice (DESIGN.md 7.11). Skipped unless
// TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/onboarding/onboarding_screen.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('cold open and choice', (tester) async {
    setWindow(tester, const Size(720, 360));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: TapeBackdrop(
          child: OnboardingScreen(width: 720, height: 360, onDemo: () {}),
        ),
      ),
    );
    void run(int ms) {
      var left = ms * 1000;
      while (left > 0) {
        motion.tick(16667 / 1e6);
        left -= 16667;
      }
    }

    run(350);
    await tester.pump();
    await capturePng(tester, 'open-350');
    run(400);
    await tester.pump();
    await capturePng(tester, 'open-750');
    run(2000);
    await tester.pump();
    await capturePng(tester, 'choice');
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
