// Google Maps' turns on the HUD, end to end on a real Android (docs/NAV.md, N6):
// the app drives from the simulated car over the real WiFi transport, and Maps'
// notification, played by the debug build's stand-in from the same simulated car,
// goes through the real listener, channel, parser and HUD.
//
//   adb shell pm clear io.github.ictashik.tapedash        # a first launch
//   tool/nav_spike.sh enable                              # notification access
//   dart run tool/sim_server.dart --port 35000 --scenario city_stop_go --nav-adb
//   flutter test integration_test/nav_hud_e2e_test.dart -d <device>
//
// or all of it: tool/test_nav_e2e.sh. It prints `NAV` lines: what was seen and how
// closely the distance counted down on the car's own speed agreed with Maps'.
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/nav/nav_bend.dart';
import 'package:tapedash/nav/nav_state.dart';
import 'package:tapedash/nav/nav_tracker.dart';
import 'package:tapedash/ui/design/fidelity/frame_probe.dart';
import 'package:tapedash/ui/hud/nav_hud.dart';

import 'sim_connect.dart';

double _percentile(List<double> sorted, double p) => sorted.isEmpty
    ? double.nan
    : sorted[math.min(sorted.length - 1, (sorted.length * p).floor())];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Maps\' turns on the HUD, from a simulated drive', (
    tester,
  ) async {
    await app.main();
    await connectToSimulator(tester);
    await tester.pump(const Duration(milliseconds: 500));

    // The app's own settings: the switch for Maps' turns, and the HUD up.
    final settings = tester
        .widget<DriveShell>(find.byType(DriveShell))
        .app!
        .settings;
    expect(settings.navEnabled.value, isFalse, reason: 'off to begin with');
    settings.navEnabled.value = true;
    settings.hud.active = true;

    await until(
      tester,
      () => find.byType(NavHud).evaluate().isNotEmpty,
      'the navigation HUD: is tool/sim_server.dart running with --nav-adb, '
      'and has TapeDash been given notification access '
      '(tool/nav_spike.sh enable)?',
      seconds: 60,
    );
    // ignore: avoid_print
    print('NAV the HUD took over');

    NavService nav() => tester.widget<NavHud>(find.byType(NavHud)).nav;

    // Watch the drive. What is judged: that the HUD stays on Maps through the whole
    // run (no stale, even through the stops at signals), that the arrows and the
    // instructions change as the car turns, and how closely the distance counted
    // down by the car's own speed agrees with the figure Maps then gives.
    final frames = <double>[];
    void onTimings(List<FrameTiming> t) =>
        frames.addAll(t.map(FrameProbe.costOf));
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    final arrows = <String>{};
    final bends = <NavBend>{};
    final instructions = <String>{};
    final errors = <double>[];
    var posts = 0;
    var stale = 0;
    NavState? seen;
    double? estimateBefore;
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      final service = nav();
      final state = service.tracker.state.value;
      if (service.tracker.freshness.value == NavFreshness.stale) stale++;
      if (!identical(state, seen)) {
        posts++;
        final sameTurn = seen != null && seen.instruction == state.instruction;
        if (sameTurn &&
            estimateBefore != null &&
            state.distanceToTurnM != null) {
          errors.add((estimateBefore - state.distanceToTurnM!).abs());
        }
        seen = state;
        if (state.arrow != null) {
          arrows.add(state.arrow!.id);
          bends.add(NavBendReader.of(state.arrow!));
        }
        if (state.instruction != null) instructions.add(state.instruction!);
      }
      estimateBefore = service.tracker.distanceToTurnEstimateM.value;
    }
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    errors.sort();
    frames.sort();
    // ignore: avoid_print
    print(
      'NAV posts=$posts arrows=${arrows.length} bends=${bends.map((b) => b.name).toList()..sort()} '
      'instructions=${instructions.length} stale-samples=$stale',
    );
    // ignore: avoid_print
    print(
      'NAV countdown-vs-maps n=${errors.length} '
      'p50=${_percentile(errors, 0.5).toStringAsFixed(1)} '
      'p90=${_percentile(errors, 0.9).toStringAsFixed(1)} '
      'max=${errors.isEmpty ? double.nan : errors.last.toStringAsFixed(1)} m',
    );
    // ignore: avoid_print
    print(
      'PERF nav-hud n=${frames.length} '
      'p50=${_percentile(frames, 0.5).toStringAsFixed(1)} '
      'p90=${_percentile(frames, 0.9).toStringAsFixed(1)} '
      'p99=${_percentile(frames, 0.99).toStringAsFixed(1)} ms',
    );

    expect(posts, greaterThan(10), reason: 'Maps posted through the drive');
    expect(arrows.length, greaterThanOrEqualTo(2), reason: 'left and right');
    // The arrows were drawn on the device by Android, and read by the HUD's own
    // reader: a left and a right.
    expect(bends, containsAll([NavBend.left, NavBend.right]));
    expect(instructions.length, greaterThanOrEqualTo(3));
    // Only the stand-in spoke: a real Google Maps still navigating on the phone
    // would add its own streets and spoil the measure.
    expect(
      instructions.every(
        (i) => i.contains('Cross Rd') || i.contains('destination'),
      ),
      isTrue,
      reason: 'something other than the stand-in posted: $instructions',
    );
    expect(stale, 0, reason: 'Maps never went quiet on the HUD');
    expect(errors.length, greaterThan(5));
    expect(_percentile(errors, 0.5), lessThan(35), reason: 'metres');
    expect(tester.takeException(), isNull);
  });
}
