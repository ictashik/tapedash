import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../location/location_source.dart';
import '../location/location_status.dart';
import '../money/pit_stop_form.dart';
import '../obd/dtc/dtc_descriptions.dart';
import '../obd/session_diagnostics.dart';
import '../platform/native_location_source.dart';
import '../trips/trip.dart';
import '../trips/trip_library.dart';
import '../ui/design/components/backdrop.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/hud/hud_host.dart';
import '../ui/hud/hud_settings.dart';
import '../ui/pages/coach/coach_page.dart';
import '../ui/pages/diagnostics/diagnostics_page.dart';
import '../ui/pages/drive/drive_page.dart';
import '../ui/pages/drive/drive_signals.dart';
import '../ui/pages/garage/garage_page.dart';
import '../ui/pages/history/history_page.dart';
import '../ui/pages/money/money_page.dart';
import '../ui/pages/money/money_signals.dart';
import '../ui/pages/pitstop/pit_stop_page.dart';
import '../ui/pages/review/review_page.dart';
import '../ui/pages/strip/parked_dock.dart';
import '../ui/pages/strip/the_strip.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_info.dart';
import 'app_services.dart';
import 'demo_drive.dart';
import 'demo_location_source.dart';
import 'drive_feed.dart';
import 'drive_services.dart';
import 'live_drive.dart';

/// Which full-screen form is over the Strip.
enum _Form { none, pitStop, price, realPrice, garage, diagnostics }

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
    this.live,
    this.app,
    this.onChangeAdapter,
  });

  final Clock clock;
  final Scheduler scheduler;
  final String scenario;

  /// A demo drive someone else started (and disposes), so that it can be
  /// connecting while the cold open and the choice are on screen: the ignition
  /// then plays the moment the drive appears (DESIGN.md 7.11's "within 1 s").
  /// Null builds and owns one.
  final DemoDrive? demo;

  /// A drive from a real adapter, in place of the demo (someone else starts and
  /// disposes it). When given, the demo is not built at all.
  final LiveDrive? live;

  /// The app's own services (the real trip log and settings). Null uses empty
  /// in-memory ones, for tests.
  final AppServices? app;

  /// Garage's request to choose an adapter (the connect flow is the app's).
  final VoidCallback? onChangeAdapter;

  @override
  State<DriveShell> createState() => _DriveShellState();
}

class _DriveShellState extends State<DriveShell> {
  /// The demo drive, unless this is a drive from a real adapter.
  late final DemoDrive? _demo = widget.live != null
      ? null
      : widget.demo ??
            DemoDrive(
              clock: widget.clock,
              scheduler: widget.scheduler,
              scenario: widget.scenario,
            );

  /// Where the drive screens read from: the adapter's car, or the simulated one.
  late final DriveFeed _feed = widget.live ?? _demo!;
  late final AppServices _app = widget.app ?? AppServices.inMemory();
  late final AppServices _demoApp = AppServices.demo(_app.trips);

  /// The money of this drive: the real one for a real car, the demo's own for
  /// the demo (CLAUDE.md 7.6).
  late final AppServices _driveApp = _feed.isDemo ? _demoApp : _app;
  late final HudSettings _hud = _app.settings.hud;
  final GlobalKey<DrivePageState> _driveKey = GlobalKey();
  SessionDiagnostics? _diagnostics;
  DtcDescriptions _descriptions = DtcDescriptions.empty;
  late final TripLibrary _library = TripLibrary(_app.trips);
  final DebriefRequest _debrief = DebriefRequest();
  final GlobalKey<TheStripState> _stripKey = GlobalKey();
  LocationSource? _location;
  LocationStatus? _gps;
  ObservableListenable<bool>? _gpsListenable;
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
      // The demo's GPS follows the demo car, so a demo trip has a route; a real
      // drive has the phone's own.
      final LocationSource location = _feed.isDemo
          ? DemoLocationSource(
              demo: _demo!,
              scheduler: widget.scheduler,
              clock: widget.clock,
            )
          : NativeLocationSource();
      _location = location;
      _gps = LocationStatus(source: location, scheduler: widget.scheduler);
      _gpsListenable = ObservableListenable(_gps!.hasFix);
      final services = DriveServices(
        vehicle: _feed.vehicle,
        connection: _feed.connection,
        app: _driveApp,
        clock: widget.clock,
        scheduler: widget.scheduler,
        sessions: _feed.sessions,
        isDemo: _feed.isDemo,
        location: location,
        thresholds: _app.settings.thresholds,
      );
      _services = services;
      _money = MoneySignals(
        trip: services.computer,
        settings: _driveApp.money,
        ledger: _driveApp.ledger,
        motion: motion,
        clock: widget.clock,
        recorder: services.recorder,
      );
      _signals = DriveSignals(
        vehicle: _feed.vehicle,
        motion: motion,
        clock: widget.clock,
        scheduler: widget.scheduler,
        connection: _feed.connection,
        demoMode: _feed.isDemo,
        money: _money,
        gpsHasFix: _gpsListenable,
        ignitionMode: _app.settings.ignition.value,
        reduceMotion: _app.settings.reduceMotion.value,
      );
      _diagnostics = SessionDiagnostics(
        sessions: _feed.sessions,
        estimator: services.estimator,
        vehicle: _feed.vehicle,
      );
      _feed.start(); // a no-op if it is already running
      unawaited(_startLocation(location));
      _library.refresh();
      // A trip that ends is laid out in Review, and the Debrief plays; one that
      // resumes (the engine came back within five minutes) puts it away.
      services.recorder
        ..onTripEnded(_onTripEnded)
        ..onTripResumed(_onTripResumed);
      // The demo drive starting over is the engine going off.
      _demo?.loops.addListener(_onDemoLoop);
      final settings = _app.settings;
      settings.coachPreset.addListener(_onCoach);
      settings.speedLimitKmh.addListener(_onCoach);
      settings.cluster.addListener(_onCluster);
      _loadDescriptions();
    }
  }

  Future<void> _onTripEnded(Trip trip) async {
    await _services!.recorder.idle;
    await _library.refresh();
    if (!mounted) return;
    _debrief.request();
    _stripKey.currentState?.goTo(0);
  }

  void _onTripResumed(Trip trip) {
    _debrief.clear();
    _stripKey.currentState?.goTo(TheStrip.homePage);
    _library.refresh();
  }

  void _onDemoLoop() => _services?.recorder.endNow();

  /// Starts the GPS. A phone that will not give it (no permission, no receiver, a
  /// test with no platform) only means no route and the GPS glyph saying no fix:
  /// the drive goes on.
  Future<void> _startLocation(LocationSource location) async {
    try {
      await location.start();
    } on Object catch (error) {
      debugPrint('The GPS did not start: $error');
    }
  }

  // Garage's coach settings reach the detectors from the next sample.
  void _onCoach() => _services?.setThresholds(_app.settings.thresholds);

  // Garage's layout choice moves the reel now.
  void _onCluster() {
    final page = _driveKey.currentState;
    final want = _app.settings.cluster.value;
    if (page != null && page.reel.round() != want) page.showCluster(want);
  }

  Future<void> _loadDescriptions() async {
    try {
      final json = await rootBundle.loadString('assets/dtc/dtc.json');
      if (mounted) setState(() => _descriptions = DtcDescriptions.parse(json));
    } on Object catch (error) {
      // No descriptions is not a reason to show nothing: each code is then
      // described by its system.
      debugPrint('Could not load the fault code descriptions: $error');
    }
  }

  @override
  void dispose() {
    _demo?.loops.removeListener(_onDemoLoop);
    final settings = _app.settings;
    settings.coachPreset.removeListener(_onCoach);
    settings.speedLimitKmh.removeListener(_onCoach);
    settings.cluster.removeListener(_onCluster);
    _debrief.dispose();
    _diagnostics?.dispose();
    _signals?.dispose();
    _money?.dispose();
    _services?.close();
    _gpsListenable?.dispose();
    _gps?.dispose();
    final location = _location;
    if (location is DemoLocationSource) {
      location.dispose();
    } else {
      unawaited(location?.stop());
    }
    if (widget.demo == null && _demo != null) _demo.dispose();
    super.dispose();
  }

  /// Opens a form, parked only (DESIGN.md 7.9).
  void _open(_Form form) {
    if (_signals!.mode.value != DrivingMode.parked) return;
    setState(() => _form = form);
  }

  void _close() => setState(() => _form = _Form.none);

  Future<void> _save(PitStopForm f) async {
    if (_form == _Form.realPrice) {
      await _app.money.setPrice(f.pricePerLitre);
      return;
    }
    if (f.priceOnly) {
      await _driveApp.money.setPrice(f.pricePerLitre);
    } else {
      await _driveApp.saveFillUp(
        at: widget.clock.now(),
        litres: f.litres!,
        amount: f.amount!,
        fullTank: f.fullTank,
      );
    }
    await _money!.refreshFills();
  }

  Widget _overlay(DriveSignals signals, double w, double h) {
    switch (_form) {
      case _Form.garage:
        return GaragePage(
          settings: _app.settings,
          services: _app,
          library: _library,
          mode: signals.mode,
          width: w,
          height: h,
          onClose: _close,
          onSetPrice: () => setState(() => _form = _Form.realPrice),
          demo: _demo,
          adapters: _app.adapters,
          onChangeAdapter: widget.onChangeAdapter,
          onEndTrip: () => _services?.recorder.endNow(),
          onAlignment: () => _hud.showAlignment = true,
          version: appVersion,
        );
      case _Form.diagnostics:
        return DiagnosticsPage(
          source: _diagnostics!,
          mode: signals.mode,
          width: w,
          height: h,
          onClose: _close,
          descriptions: _descriptions,
        );
      case _Form.none:
      case _Form.pitStop:
      case _Form.price:
      case _Form.realPrice:
        // The price of the car's own fuel is the real one; a demo's Pit Stop is
        // the demo's.
        final target = _form == _Form.realPrice ? _app : _driveApp;
        return PitStopPage(
          key: ValueKey(_form),
          width: w,
          height: h,
          mode: signals.mode,
          priceOnly: _form == _Form.price || _form == _Form.realPrice,
          tankLitres: target.setup.value.tankLitres,
          currentPrice: target.money.price.value,
          onSave: _save,
          onClose: _close,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signals = _signals!;
    final motion = MotionScope.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return HudHost(
          settings: _hud,
          signals: signals,
          money: _money,
          width: w,
          height: h,
          child: Stack(
            children: [
              TheStrip(
                key: _stripKey,
                width: w,
                height: h,
                motion: motion,
                mode: signals.mode,
                onToggleHud: _hud.toggle,
                pages: [
                  ReviewPage(
                    debrief: _debrief,
                    library: _library,
                    mode: signals.mode,
                    width: w,
                    height: h,
                  ),
                  MoneyPage(
                    signals: signals,
                    width: w,
                    height: h,
                    onPitStop: () => _open(_Form.pitStop),
                    onSetPrice: () => _open(_Form.price),
                  ),
                  DrivePage(
                    key: _driveKey,
                    signals: signals,
                    motion: motion,
                    width: w,
                    height: h,
                    initialCluster: _app.settings.cluster.value,
                    onClusterSettled: (i) => _app.settings.cluster.value = i,
                  ),
                  CoachPage(
                    library: _library,
                    clock: widget.clock,
                    mode: signals.mode,
                    width: w,
                    height: h,
                  ),
                  HistoryPage(
                    library: _library,
                    clock: widget.clock,
                    width: w,
                    height: h,
                    onOpen: (_) => _stripKey.currentState?.goTo(0),
                  ),
                ],
              ),
              ParkedDock(
                mode: signals.mode,
                motion: motion,
                width: w,
                height: h,
                onHud: _hud.toggle,
                onPitStop: () => _open(_Form.pitStop),
                onGarage: () => _open(_Form.garage),
                onDiagnostics: () => _open(_Form.diagnostics),
              ),
              if (_form != _Form.none)
                Positioned.fill(
                  child: TapeBackdrop(child: _overlay(signals, w, h)),
                ),
            ],
          ),
        );
      },
    );
  }
}
