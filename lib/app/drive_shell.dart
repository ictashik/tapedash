import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../money/pit_stop_form.dart';
import '../ui/design/components/backdrop.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/hud/hud_host.dart';
import '../ui/hud/hud_settings.dart';
import '../ui/pages/drive/drive_page.dart';
import '../ui/pages/drive/drive_signals.dart';
import '../ui/pages/money/money_page.dart';
import '../ui/pages/money/money_signals.dart';
import '../ui/pages/pitstop/pit_stop_page.dart';
import '../ui/pages/strip/parked_dock.dart';
import '../ui/pages/strip/placeholder_page.dart';
import '../ui/pages/strip/the_strip.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_services.dart';
import 'demo_drive.dart';
import 'drive_services.dart';

/// Which full-screen form is over the Strip.
enum _Form { none, pitStop, price }

/// The app's driving surface: the Strip with its five pages, the parked dock,
/// Pit Stop, and the HUD over all of them, fed by Demo Mode's simulated car
/// (CLAUDE.md 7.6).
///
/// It owns the service graph for now: the demo drive, the trip computer and
/// recorder chained on its vehicle ([DriveServices]), the signals the screens
/// read, and the HUD's settings; and lets go of it on dispose. A real adapter's
/// session replaces the demo drive here in phase 6, behind the same
/// `VehicleState`. Time is injected, so a test drives the whole thing on a
/// `FakeClock`.
///
/// **The demo has its own money:** its price, fill-ups and calibration are in
/// memory and start from an example price, and only its trips reach the real trip
/// log, flagged as demo (CLAUDE.md 7.6).
class DriveShell extends StatefulWidget {
  const DriveShell({
    super.key,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.scenario = 'city_stop_go',
    this.demo,
    this.app,
  });

  final Clock clock;
  final Scheduler scheduler;
  final String scenario;

  /// A demo drive someone else started (and disposes), so that it can be
  /// connecting while the cold open and the choice are on screen: the ignition
  /// then plays the moment the drive appears (DESIGN.md 7.11's "within 1 s").
  /// Null builds and owns one.
  final DemoDrive? demo;

  /// The app's own services (the real trip log and settings). Null uses empty
  /// in-memory ones, for tests.
  final AppServices? app;

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
  late final AppServices _app = widget.app ?? AppServices.inMemory();
  late final AppServices _demoApp = AppServices.demo(_app.trips);
  final HudSettings _hud = HudSettings();
  DriveServices? _services;
  MoneySignals? _money;
  DriveSignals? _signals;
  _Form _form = _Form.none;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The signals need the app's motion clock, which is only in scope here.
    if (_signals == null) {
      final motion = MotionScope.of(context);
      final services = DriveServices(
        vehicle: _demo.vehicle,
        connection: _demo.connection,
        app: _demoApp,
        clock: widget.clock,
        scheduler: widget.scheduler,
        sessions: _demo.sessions,
        isDemo: true,
      );
      _services = services;
      _money = MoneySignals(
        trip: services.computer,
        settings: _demoApp.money,
        ledger: _demoApp.ledger,
        motion: motion,
        clock: widget.clock,
        recorder: services.recorder,
      );
      _signals = DriveSignals(
        vehicle: _demo.vehicle,
        motion: motion,
        clock: widget.clock,
        scheduler: widget.scheduler,
        connection: _demo.connection,
        demoMode: true,
        money: _money,
      );
      _demo.start(); // a no-op if it is already running
    }
  }

  @override
  void dispose() {
    _hud.dispose();
    _signals?.dispose();
    _money?.dispose();
    _services?.close();
    if (widget.demo == null) _demo.dispose();
    super.dispose();
  }

  /// Opens a form, parked only (DESIGN.md 7.9).
  void _open(_Form form) {
    if (_signals!.mode.value != DrivingMode.parked) return;
    setState(() => _form = form);
  }

  void _close() => setState(() => _form = _Form.none);

  Future<void> _save(PitStopForm f) async {
    if (f.priceOnly) {
      await _demoApp.money.setPrice(f.pricePerLitre);
    } else {
      await _demoApp.saveFillUp(
        at: widget.clock.now(),
        litres: f.litres!,
        amount: f.amount!,
        fullTank: f.fullTank,
      );
    }
    await _money!.refreshFills();
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
          money: _money,
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
                  MoneyPage(
                    signals: signals,
                    width: w,
                    height: h,
                    onPitStop: () => _open(_Form.pitStop),
                    onSetPrice: () => _open(_Form.price),
                  ),
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
                onPitStop: () => _open(_Form.pitStop),
              ),
              if (_form != _Form.none)
                Positioned.fill(
                  child: TapeBackdrop(
                    child: PitStopPage(
                      key: ValueKey(_form),
                      width: w,
                      height: h,
                      mode: signals.mode,
                      priceOnly: _form == _Form.price,
                      tankLitres: _demoApp.setup.value.tankLitres,
                      currentPrice: _demoApp.money.price.value,
                      onSave: _save,
                      onClose: _close,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
