// REAL Google Maps' turns on the HUD, on an emulator (docs/NAV.md, N6): nothing
// stands in for Maps. Maps navigates in the background (tool/test_nav_maps.sh starts
// it and moves the emulator's position along), the app drives from the simulated car,
// and what Maps' own notification says goes through the app's real listener, channel,
// parser and HUD. It prints what was read, so that it can be set beside what Maps
// shows.
//
//   tool/test_nav_maps.sh
//
// It needs Google Maps on the emulator, navigating, and the app given notification
// access (the script does both). It asserts what is true of any navigation, not of
// any route.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/nav/nav_arrow.dart';
import 'package:tapedash/nav/nav_bend.dart';
import 'package:tapedash/nav/nav_state.dart';
import 'package:tapedash/ui/hud/nav_hud.dart';

import 'sim_connect.dart';

/// What Maps drew for one manoeuvre, and which way the HUD reads it; a picture of
/// an arrow that cannot be read, to see why.
void _describe(NavArrow a, String instruction) {
  final bend = NavBendReader.of(a);
  // ignore: avoid_print
  print(
    'NAV real arrow ${a.id} ${a.width}x${a.height} bend=${bend.name} '
    'for "$instruction"',
  );
  if (bend != NavBend.unknown) return;
  for (var y = 0; y < a.height; y += 6) {
    final row = StringBuffer();
    for (var x = 0; x < a.width; x += 3) {
      row.write(a.alpha[y * a.width + x] > 80 ? '#' : '.');
    }
    // ignore: avoid_print
    print('NAV real   $row');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Google Maps\' turns on the HUD', (tester) async {
    await app.main();
    await connectToSimulator(tester);
    await tester.pump(const Duration(milliseconds: 500));

    final settings = tester
        .widget<DriveShell>(find.byType(DriveShell))
        .app!
        .settings;
    settings.navEnabled.value = true;
    settings.hud.active = true;

    await until(
      tester,
      () => find.byType(NavHud).evaluate().isNotEmpty,
      'the navigation HUD: is Google Maps navigating on this emulator, and has '
      'TapeDash been given notification access (tool/test_nav_maps.sh does both)?',
      seconds: 90,
    );
    // ignore: avoid_print
    print('NAV real: the HUD took over');

    NavService nav() => tester.widget<NavHud>(find.byType(NavHud)).nav;

    final shapes = <NavShape>{};
    final phases = <NavPhase>{};
    final arrows = <String>{};
    final bends = <NavBend>{};
    final distances = <String>{};
    final lines = <String>[];
    var guiding = 0;
    var complete = 0;
    NavState? seen;
    final end = DateTime.now().add(const Duration(seconds: 100));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      final state = nav().tracker.state.value;
      if (identical(state, seen)) continue;
      seen = state;
      phases.add(state.phase);
      if (state.shape != null) shapes.add(state.shape!);
      if (state.phase != NavPhase.guiding) {
        lines.add('${state.phase.name}: ${state.message}');
        continue;
      }
      guiding++;
      final arrow = state.arrow;
      if (arrow != null) {
        if (arrows.add(arrow.id)) _describe(arrow, state.instruction ?? '-');
        bends.add(NavBendReader.of(arrow));
      }
      if (state.distanceText != null) distances.add(state.distanceText!);
      if (arrow != null &&
          state.instruction != null &&
          state.distanceText != null &&
          state.etaText != null) {
        complete++;
      }
      lines.add(
        'guiding: ${state.distanceText ?? '-'} | ${state.instruction ?? '-'} | '
        'arrow=${arrow?.id ?? '-'} bend=${arrow == null ? '-' : NavBendReader.of(arrow).name} | '
        'left=${state.distanceLeftM?.round() ?? '-'} m | '
        'time=${state.timeLeft?.inMinutes ?? '-'} min${state.timeLeftIsDerived ? ' (derived)' : ''} | '
        'eta=${state.etaText ?? '-'} | ${state.shape?.name}',
      );
    }

    // What Maps did, as the HUD read it: each distinct line once, in order.
    final unique = <String>[];
    for (final l in lines) {
      if (unique.isEmpty || unique.last != l) unique.add(l);
    }
    for (final l in unique.take(60)) {
      // ignore: avoid_print
      print('NAV real $l');
    }
    // ignore: avoid_print
    print(
      'NAV real summary: reads=${lines.length} guiding=$guiding complete=$complete '
      'phases=${phases.map((p) => p.name).toList()..sort()} '
      'shapes=${shapes.map((s) => s.name).toList()..sort()} '
      'arrows=${arrows.length} bends=${bends.map((b) => b.name).toList()..sort()} '
      'distances=${distances.length}',
    );

    expect(nav().status.value, isNot(NavLinkStatus.needsAccess));
    expect(guiding, greaterThan(5), reason: 'Maps was guiding');
    expect(
      complete,
      greaterThan(3),
      reason: 'an arrow, an instruction, a distance and an ETA, together',
    );
    expect(
      distances.length,
      greaterThanOrEqualTo(3),
      reason: 'it counted down',
    );
    expect(tester.takeException(), isNull);
  });
}
