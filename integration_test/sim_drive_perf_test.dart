// A demo drive on a real device or emulator, with frame timings per cluster
// (CLAUDE.md 10, layer 5; DESIGN.md 9.4). Real time: about two minutes.
//
//   flutter test integration_test/demo_drive_perf_test.dart -d <device>
//
// It prints `PERF` lines (p50, p90 and p99 of the frame cost, the longer of
// the build and the raster time) for each cluster and for the HUD, and the
// fidelity tier the cold open chose. On an emulator with software GL the
// numbers say nothing about a real low-end phone; see the review package.
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/fidelity/frame_probe.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/onboarding/onboarding_screen.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';

double _percentile(List<double> sorted, double p) => sorted.isEmpty
    ? double.nan
    : sorted[math.min(sorted.length - 1, (sorted.length * p).floor())];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a demo drive through every cluster and the HUD', (tester) async {
    await app.main();
    final costs = <double>[];
    void onTimings(List<FrameTiming> t) =>
        costs.addAll(t.map(FrameProbe.costOf));
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    // The cold open, then the choice, then the demo.
    var waited = 0;
    while (find.byType(DrivePage).evaluate().isEmpty && waited < 30) {
      await tester.pump(const Duration(milliseconds: 500));
      waited++;
      if (tester
              .stateList<OnboardingScreenState>(find.byType(OnboardingScreen))
              .any((s) => s.choiceReady) &&
          find.text('TRY A DEMO DRIVE').evaluate().isNotEmpty) {
        break;
      }
    }
    final coldOpen = List.of(costs);
    costs.clear();
    await tester.tap(find.text('TRY A DEMO DRIVE'));
    await tester.pump(const Duration(milliseconds: 500));

    void report(String name, List<double> c) {
      final s = List.of(c)..sort();
      // ignore: avoid_print
      print(
        'PERF $name n=${s.length} '
        'p50=${_percentile(s, 0.5).toStringAsFixed(1)} '
        'p90=${_percentile(s, 0.9).toStringAsFixed(1)} '
        'p99=${_percentile(s, 0.99).toStringAsFixed(1)} ms',
      );
    }

    final tier = TapeTheme.of(
      tester.element(find.byType(TapeBackdrop).first),
    ).tier;
    // ignore: avoid_print
    print('PERF tier chosen by the cold open: ${tier.label}');
    report('cold-open', coldOpen);

    Future<void> watch(String name, int seconds) async {
      costs.clear();
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      report(name, costs);
    }

    await watch('apex', 25);
    for (final name in ['tape', 'minimal', 'telemetry', 'road']) {
      await tester.fling(find.byType(DrivePage), const Offset(0, -300), 1200);
      await tester.pump(const Duration(seconds: 1));
      await watch(name, 20);
    }
    // The HUD, by a double-tap.
    await tester.tapAt(const Offset(300, 200));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(300, 200));
    await tester.pump(const Duration(seconds: 1));
    await watch('hud', 15);

    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    expect(tester.takeException(), isNull);
  });
}
