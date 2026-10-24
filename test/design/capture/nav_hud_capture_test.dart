// The navigation layout of the HUD (DESIGN.md 8, docs/NAV.md): a right turn, a left
// turn, straight on, a distance in miles, a long instruction, rerouting, starting,
// and Maps gone quiet; at the three sizes, and mirrored as the windshield shows it.
// Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/nav/nav_arrow.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/platform/nav_channel.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';
import 'package:tapedash/ui/hud/hud_view.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../support/harness.dart';

NavArrow _real(String id) => NavArrow(
  id: id,
  width: 126,
  height: 126,
  alpha: File('test/fixtures/nav/arrows/$id.alpha').readAsBytesSync(),
);

NavNotification _progress(
  String title, {
  String? distance,
  String arrow = 'e687a80d8d',
  int progress = 1171,
  int max = 6605,
  String sub = 'Arrive 9:25 PM',
}) => NavNotification(
  title: title,
  subText: sub,
  shortCriticalText: distance ?? '',
  progress: progress,
  progressMax: max,
  template: 'android.app.Notification\$ProgressStyle',
  arrow: _real(arrow),
);

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('the navigation layout', (tester) async {
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock(start: DateTime(2026, 10, 24, 20, 58))
      ..advance(const Duration(seconds: 100));
    final vehicle = VehicleState(clock: clock, scheduler: clock);
    final signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: ObservableValue(ConnectionStatus.connected),
    );
    final app = AppSettings(MemoryKeyValueStore());
    await app.load();
    app.navEnabled.value = true;
    final source = FakeNavSource(access: true);
    final nav = NavService(
      settings: app,
      source: source,
      clock: clock,
      scheduler: clock,
      speed: vehicle.motion,
    )..start();
    final hud = HudSettings(active: true, flipHorizontal: false);

    void run(int ms, {double kmh = 54}) {
      var left = ms * 1000;
      var since = 1 << 30;
      while (left > 0) {
        motion.tick(16667 / 1e6);
        clock.advance(const Duration(microseconds: 16667));
        left -= 16667;
        since += 16667;
        if (since >= 100000) {
          since = 0;
          final now = clock.monotonic();
          vehicle.ingest(Sensor.speed, kmh, at: now, receivedAt: now);
        }
      }
    }

    Future<void> maps(NavNotification n) async {
      source.push(NavPosted(n));
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      run(100);
      await tester.pump();
    }

    Future<void> pump(Size size) async {
      setWindow(tester, size);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: HudView(
            signals: signals,
            settings: hud,
            width: size.width,
            height: size.height,
            nav: nav,
          ),
        ),
      );
      run(1500);
      await tester.pump();
    }

    // Each frame, as the glass shows it (mirrored), and as designed.
    Future<void> frame(String name) async {
      hud.flipHorizontal = false;
      await tester.pump();
      await capturePng(tester, 'nav-hud-$name');
      hud.flipHorizontal = true;
      await tester.pump();
      await capturePng(tester, 'nav-hud-$name-glass');
      hud.flipHorizontal = false;
    }

    await pump(const Size(720, 360));
    await maps(
      _progress(
        '650 m · Turn right at Richmond Cir onto Mission Rd',
        distance: '650 m',
      ),
    );
    await frame('right');

    await maps(
      _progress(
        '120 m · Turn left onto Residency Rd',
        distance: '120 m',
        arrow: '5e259b7bb6',
        progress: 1700,
      ),
    );
    await frame('left-near');

    await maps(_progress('Head north', arrow: '5c317d6e0e'));
    await frame('straight-no-distance');

    await maps(
      _progress(
        '1.2 km · Keep left to take the ramp toward Hosur Road/Silk Board Junction and merge onto NH 44',
        distance: '1.2 km',
        arrow: '5e259b7bb6',
        progress: 90,
        max: 126400,
      ),
    );
    await frame('long-instruction');

    await maps(
      NavNotification(
        title: '0.3 mi · Turn right onto Main St',
        shortCriticalText: '0.3 mi',
        subText: 'Arrive 9:25 PM',
        progress: 100,
        progressMax: 20000,
        template: 'android.app.Notification\$ProgressStyle',
        arrow: _real('e687a80d8d'),
      ),
    );
    await frame('miles');

    await maps(
      const NavNotification(title: 'Rerouting...', subText: 'Arrive '),
    );
    await frame('rerouting');

    await maps(const NavNotification(title: 'Starting navigation…'));
    await frame('starting');

    await maps(
      _progress(
        '650 m · Turn right at Richmond Cir onto Mission Rd',
        distance: '650 m',
      ),
    );
    run(20000);
    await tester.pump();
    await frame('stale');

    for (final size in const [Size(640, 360), Size(800, 360)]) {
      await pump(size);
      await maps(
        _progress(
          '650 m · Turn right at Richmond Cir onto Mission Rd',
          distance: '650 m',
        ),
      );
      await frame('right-${size.width.toInt()}');
    }

    nav.dispose();
    hud.dispose();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
