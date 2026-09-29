// The phase-3b review matrix: every Drive cluster, in Motion and in Parked, at
// 640, 720 and 800 lp wide, inside the real app shell (DriveShell). Skipped
// unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  const clusters = ['apex', 'tape', 'minimal', 'telemetry', 'road'];

  for (final width in [640.0, 720.0, 800.0]) {
    for (final entry in {
      'motion': ('highway_cruise', 75),
      'parked': ('cold_start_idle', 25),
    }.entries) {
      testWidgets('${entry.key} at ${width.toInt()}', (tester) async {
        setWindow(tester, Size(width, 360));
        final kit = TapeRenderKit();
        final motion = ManualMotionClock();
        final clock = FakeClock()..advance(const Duration(seconds: 100));
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            theme: TapeThemeData(livery: Liveries.ion),
            child: DriveShell(
              clock: clock,
              scheduler: clock,
              scenario: entry.value.$1,
            ),
          ),
        );
        Future<void> run(int ms) async {
          for (var t = 0; t < ms; t += 50) {
            motion.tick(0.05);
            clock.advance(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        await run(entry.value.$2 * 1000);
        for (var i = 0; i < clusters.length; i++) {
          await run(1500);
          await capturePng(
            tester,
            'w${width.toInt()}-${entry.key}-$i-${clusters[i]}',
          );
          // An upward hand advances the reel to the next cluster.
          await tester.timedDrag(
            find.byType(DriveShell),
            const Offset(0, -250),
            const Duration(milliseconds: 250),
          );
          await run(1200);
        }
        motion.dispose();
        kit.dispose();
      }, skip: !enabled);
    }
  }
}
