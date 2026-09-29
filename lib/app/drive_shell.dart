import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/hud/hud_host.dart';
import '../ui/hud/hud_settings.dart';
import '../ui/pages/drive/drive_page.dart';
import '../ui/pages/drive/drive_signals.dart';
import '../ui/pages/money/money_page.dart';
import '../ui/pages/strip/parked_dock.dart';
import '../ui/pages/strip/placeholder_page.dart';
import '../ui/pages/strip/the_strip.dart';
import 'demo_drive.dart';

/// The app's driving surface: the Strip with its five pages, the parked dock,
/// and the HUD over both, fed by Demo Mode's simulated car (CLAUDE.md 7.6).
///
/// It owns the service graph for now (the demo drive, the signals bound to its
/// vehicle, the HUD's settings) and lets go of it on dispose. A real adapter's
/// session replaces the demo drive here in phase 6, behind the same
/// `VehicleState`. Time is injected, so a test drives the whole thing on a
/// `FakeClock`.
class DriveShell extends StatefulWidget {
  const DriveShell({
    super.key,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.scenario = 'city_stop_go',
    this.demo,
  });

  /// A demo drive someone else started (and disposes), so that it can be
  /// connecting while the cold open and the choice are on screen: the ignition
  /// then plays the moment the drive appears (DESIGN.md 7.11's "within 1 s").
  /// Null builds and owns one.
  final DemoDrive? demo;

  final Clock clock;
  final Scheduler scheduler;
  final String scenario;

  @override
  State<DriveShell> createState() => _DriveShellState();
}

class _DriveShellState extends State<DriveShell> {
  late final DemoDrive _demo =
      widget.demo ??
      DemoDrive(
        clock: widget.clock,
        scheduler: widget.scheduler,
        scenario: widget.scenario,
      );
  final HudSettings _hud = HudSettings();
  DriveSignals? _signals;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The signals need the app's motion clock, which is only in scope here.
    if (_signals == null) {
      _signals = DriveSignals(
        vehicle: _demo.vehicle,
        motion: MotionScope.of(context),
        clock: widget.clock,
        scheduler: widget.scheduler,
        connection: _demo.connection,
        demoMode: true,
      );
      _demo.start(); // a no-op if it is already running
    }
  }

  @override
  void dispose() {
    _hud.dispose();
    _signals?.dispose();
    if (widget.demo == null) _demo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signals = _signals!;
    final motion = MotionScope.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        Widget later(String name, String note) =>
            StripPlaceholder(name: name, note: note, width: w, height: h);
        return HudHost(
          settings: _hud,
          signals: signals,
          width: w,
          height: h,
          child: Stack(
            children: [
              TheStrip(
                width: w,
                height: h,
                motion: motion,
                mode: signals.mode,
                onToggleHud: _hud.toggle,
                pages: [
                  later('REVIEW', 'Arrives with trips.'),
                  MoneyPage(signals: signals, width: w, height: h),
                  DrivePage(
                    signals: signals,
                    motion: motion,
                    width: w,
                    height: h,
                  ),
                  later('COACH', 'Arrives with the coach.'),
                  later('HISTORY', 'Arrives with trips.'),
                ],
              ),
              ParkedDock(
                mode: signals.mode,
                motion: motion,
                width: w,
                height: h,
                onHud: _hud.toggle,
              ),
            ],
          ),
        );
      },
    );
  }
}
