// The HUD (DESIGN.md 8): the three layouts, and the alignment pattern with and
// without the mirror. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';
import 'package:tapedash/ui/hud/hud_view.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('layouts and the alignment pattern', (tester) async {
    setWindow(tester, const Size(720, 360));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final vehicle = VehicleState(clock: clock, scheduler: clock);
    final signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: ObservableValue(ConnectionStatus.connected),
    );
    final settings = HudSettings(active: true, flipHorizontal: false);

    void run(int ms, double rpm) {
      var left = ms * 1000;
      var since = 1000000;
      while (left > 0) {
        motion.tick(16667 / 1e6);
        clock.advance(const Duration(microseconds: 16667));
        left -= 16667;
        since += 16667;
        if (since >= 100000) {
          since = 0;
          final now = clock.monotonic();
          vehicle.ingest(Sensor.speed, 64, at: now, receivedAt: now);
          vehicle.ingest(Sensor.rpm, rpm, at: now, receivedAt: now);
        }
      }
    }

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: HudView(
          signals: signals,
          settings: settings,
          width: 720,
          height: 360,
        ),
      ),
    );
    run(1500, 3200);
    await tester.pump();
    await capturePng(tester, 'hud-drive');

    run(1000, 7200);
    await tester.pump();
    await capturePng(tester, 'hud-drive-redline');

    settings.layout = HudLayout.driveMoney;
    run(200, 3200);
    await tester.pump();
    await capturePng(tester, 'hud-drive-money');

    settings.layout = HudLayout.money;
    settings.color = HudColor.amber;
    run(200, 3200);
    await tester.pump();
    await capturePng(tester, 'hud-money');

    settings
      ..layout = HudLayout.drive
      ..color = HudColor.green
      ..showAlignment = true;
    run(200, 3200);
    await tester.pump();
    await capturePng(tester, 'hud-alignment');

    settings.flipHorizontal = true;
    run(200, 3200);
    await tester.pump();
    await capturePng(tester, 'hud-alignment-mirrored');

    settings.dispose();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
