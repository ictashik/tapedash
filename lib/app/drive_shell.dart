import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../insights/insight_data.dart';
import '../insights/rest_voltage_log.dart';
import '../insights/tank_reading.dart';
import '../location/location_source.dart';
import '../location/location_status.dart';
import '../money/pit_stop_form.dart';
import '../obd/dtc/dtc_descriptions.dart';
import '../obd/session_diagnostics.dart';
import '../platform/image_sharer.dart';
import '../platform/native_location_source.dart';
import '../sound/voice_host.dart';
import '../trips/trip.dart';
import '../trips/trip_library.dart';
import '../ui/design/components/backdrop.dart';
import '../ui/design/motion/motion_clock.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/dev/debug_overlay.dart';
import '../ui/hud/hud_host.dart';
import '../ui/hud/hud_settings.dart';
import '../ui/pages/coach/coach_page.dart';
import '../ui/pages/diagnostics/diagnostics_page.dart';
import '../ui/pages/drive/drive_page.dart';
import '../ui/pages/drive/drive_signals.dart';
import '../ui/pages/garage/garage_page.dart';
import '../ui/pages/history/history_page.dart';
import '../ui/pages/insights/insights_page.dart';
import '../ui/pages/money/money_page.dart';
import '../ui/pages/money/money_signals.dart';
import '../ui/pages/pitstop/pit_stop_page.dart';
import '../ui/pages/review/review_page.dart';
import '../ui/pages/strip/parked_dock.dart';
import '../ui/pages/strip/the_strip.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_info.dart';
import 'app_services.dart';
import 'drive_feed.dart';
import 'drive_services.dart';
import 'drive_sound.dart';
import 'engine_sound_sources.dart';
import 'exchange_coordinator.dart';
import 'live_drive.dart';

/// Which full-screen form is over the Strip.
enum _Form { none, pitStop, price, garage, diagnostics, insights }

/// The app's driving surface: the Strip with its five pages, the parked dock,
/// Pit Stop, and the HUD over all of them, fed by a [DriveFeed]: in the app the
/// car on the user's adapter ([LiveDrive]), in a test a simulated one.
///
/// It owns the service graph: the trip computer and recorder chained on the
/// feed's vehicle ([DriveServices]), the signals the screens read, and the HUD's
/// settings; and lets go of it on dispose. The feed is someone else's to start
/// and dispose. Time is injected, so a test drives the whole thing on a
/// `FakeClock`.
class DriveShell extends StatefulWidget {
  const DriveShell({
    super.key,
    required this.feed,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.location,
    this.app,
    this.onChangeAdapter,
    this.onSurvey,
    this.phoneHot,
    this.phoneTemperature,
    this.debugRows = const [],
    this.onOpenLab,
    this.soundHost,
    this.sharer,
    this.exchange,
  });

  /// Moves the app's data out and in (docs/EXCHANGE.md): Garage's rows. It is told
  /// when the car moves, and tells this screen when an import changed the log.
  final ExchangeCoordinator? exchange;

  /// Makes the engine sound's voice (lib/sound). Null uses the real one, which plays
  /// on the phone's audio output from an isolate of its own; tests give one in
  /// memory.
  final VoiceHost Function()? soundHost;

  /// Hands Year on Tape's picture to the phone's share sheet. Null uses the real
  /// one; tests give one in memory.
  final ImageSharer? sharer;

  final Clock clock;
  final Scheduler scheduler;

  /// Where the readings come from. Someone else starts and disposes it.
  final DriveFeed feed;

  /// The phone's GPS, for the route of a trip and as the distance's sanity
  /// check. Null uses the phone's own; a test gives a simulated one.
  final LocationSource? location;

  /// The app's own services (the real trip log and settings). Null uses empty
  /// in-memory ones, for tests.
  final AppServices? app;

  /// Garage's request to choose an adapter (the connect flow is the app's).
  final VoidCallback? onChangeAdapter;

  /// Garage's request to start a survey drive (the app's: it takes the adapter
  /// over). Null when the drive is not from a real adapter.
  final VoidCallback? onSurvey;

  /// Whether the phone is hot, for the status strip's glyph.
  final ValueListenable<bool>? phoneHot;

  /// The battery temperature, for Garage to say so when it is high.
  final Observable<double?>? phoneTemperature;

  /// What the app knows about the phone, for the debug overlay (its own rows come
  /// after the drive's).
  final List<DebugRow> debugRows;

  /// Opens the Design Lab from the debug overlay.
  final VoidCallback? onOpenLab;

  @override
  State<DriveShell> createState() => _DriveShellState();
}

class _DriveShellState extends State<DriveShell> {
  /// Where the drive screens read from.
  late final DriveFeed _feed = widget.feed;
  late final AppServices _app = widget.app ?? AppServices.inMemory();
  late final ImageSharer _sharer = widget.sharer ?? NativeImageSharer();
  late final HudSettings _hud = _app.settings.hud;
  final GlobalKey<DrivePageState> _driveKey = GlobalKey();
  SessionDiagnostics? _diagnostics;
  RestVoltageWatcher? _restWatcher;
  DtcDescriptions _descriptions = DtcDescriptions.empty;
  late final TripLibrary _library = TripLibrary(_app.trips);
  final DebriefRequest _debrief = DebriefRequest();
  final GlobalKey<TheStripState> _stripKey = GlobalKey();
  LocationSource? _location;
  LocationStatus? _gps;
  ObservableListenable<bool>? _gpsListenable;
  DriveServices? _services;

  /// Whether a trip is being recorded, for the dock's End trip button.
  final ValueNotifier<bool> _tripRunning = ValueNotifier(false);
  MoneySignals? _money;
  DriveSignals? _signals;

  /// The engine sound: off until it is turned on in Garage.
  DriveSound? _sound;
  _Form _form = _Form.none;

  /// The debug overlay (CLAUDE.md 9), opened by a long-press.
  bool _debug = false;
  final List<ChangeNotifier> _debugSources = [];
  List<DebugRow> _rows = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The signals need the app's motion clock, which is only in scope here.
    if (_signals == null) {
      final motion = MotionScope.of(context);
      final LocationSource location = widget.location ?? NativeLocationSource();
      _location = location;
      _gps = LocationStatus(source: location, scheduler: widget.scheduler);
      _gpsListenable = ObservableListenable(_gps!.hasFix);
      final services = DriveServices(
        vehicle: _feed.vehicle,
        connection: _feed.connection,
        app: _app,
        clock: widget.clock,
        scheduler: widget.scheduler,
        sessions: _feed.sessions,
        location: location,
        note: _feed is LiveDrive ? _feed.note : null,
        thresholds: _app.settings.thresholds,
      );
      _services = services;
      services.recorder.phase.addListener(_syncTrip);
      _syncTrip();
      _money = MoneySignals(
        trip: services.computer,
        settings: _app.money,
        ledger: _app.ledger,
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
        money: _money,
        gpsHasFix: _gpsListenable,
        phoneHot: widget.phoneHot,
        ignitionMode: _app.settings.ignition.value,
        reduceMotion: _app.settings.reduceMotion.value,
      );
      _sound = DriveSound(
        settings: _app.settings,
        live: LiveSoundSource(_signals!),
        scheduler: widget.scheduler,
        clock: widget.clock,
        hostFactory: widget.soundHost,
        note: _feed is LiveDrive ? _feed.note : null,
      )..start();
      _diagnostics = SessionDiagnostics(
        sessions: _feed.sessions,
        estimator: services.estimator,
        vehicle: _feed.vehicle,
      );
      _restWatcher = RestVoltageWatcher(
        vehicle: _feed.vehicle,
        log: _app.restVoltage,
      );
      _feed.start(); // a no-op if it is already running
      unawaited(_startLocation(location));
      _library.refresh();
      // A trip that ends is laid out in Review, and the Debrief plays; one that
      // resumes (the engine came back within five minutes) puts it away.
      services.recorder
        ..onTripEnded(_onTripEnded)
        ..onTripResumed(_onTripResumed);
      final settings = _app.settings;
      settings.coachPreset.addListener(_onCoach);
      settings.speedLimitKmh.addListener(_onCoach);
      settings.cluster.addListener(_onCluster);
      widget.exchange?.changes.addListener(_onExchanged);
      _signals!.mode.addListener(_syncMoving);
      _syncMoving();
      _loadDescriptions();
      _buildDebugRows(services);
    }
  }

  /// An import changed the trips or the fill-ups: read them again.
  void _onExchanged() {
    _library.refresh();
    _money?.refreshFills();
  }

  void _syncMoving() {
    widget.exchange?.moving.value = _signals?.mode.value == DrivingMode.motion;
  }

  void _buildDebugRows(DriveServices services) {
    ObservableListenable<T> watch<T>(Observable<T> o) {
      final l = ObservableListenable<T>(o);
      _debugSources.add(l);
      return l;
    }

    DebugRow row(
      String label,
      List<Listenable> sources,
      String Function() text,
    ) {
      final c = ComputedText(sources, text);
      _debugSources.add(c);
      return DebugRow(label, c);
    }

    final poll = watch(_feed.pollRate);
    final link = watch(_feed.connection);
    final description = watch(_feed.description);
    final source = watch(services.estimator.source);
    _rows = [
      row('Source', [description], () => _feed.description.value),
      row('Link', [link], () => _feed.connection.value.name),
      row('Poll rate', [
        poll,
      ], () => '${_feed.pollRate.value.toStringAsFixed(1)} /s'),
      row('Fuel from', [source], () => services.estimator.source.value.label),
      if (_sound != null)
        row('Engine sound', [_sound!.status], () => _sound!.status.value.name),
      ...widget.debugRows,
    ];
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

  void _syncTrip() =>
      _tripRunning.value = _services?.recorder.recording ?? false;

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
    widget.exchange?.changes.removeListener(_onExchanged);
    _signals?.mode.removeListener(_syncMoving);
    widget.exchange?.moving.value = false;
    final settings = _app.settings;
    settings.coachPreset.removeListener(_onCoach);
    settings.speedLimitKmh.removeListener(_onCoach);
    settings.cluster.removeListener(_onCluster);
    _debrief.dispose();
    _diagnostics?.dispose();
    _restWatcher?.dispose();
    for (final source in _debugSources) {
      source.dispose();
    }
    _sound?.dispose();
    _signals?.dispose();
    _money?.dispose();
    _services?.recorder.phase.removeListener(_syncTrip);
    _services?.close();
    _tripRunning.dispose();
    _gpsListenable?.dispose();
    _gps?.dispose();
    unawaited(_location?.stop());
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
      await _app.money.setPrice(f.pricePerLitre);
    } else {
      await _app.saveFillUp(
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
          onSetPrice: () => setState(() => _form = _Form.price),
          adapters: _app.adapters,
          onChangeAdapter: widget.onChangeAdapter,
          onSurvey: widget.onSurvey,
          diary: _app.linkDiary,
          phoneTemperature: widget.phoneTemperature,
          onAlignment: () => _hud.showAlignment = true,
          sound: _sound,
          version: appVersion,
          exchange: widget.exchange,
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
      case _Form.insights:
        return InsightsPage(
          load: () => InsightData.load(
            _app.trips,
            fallbackPrice: _app.money.price.value,
          ),
          tank: (trips) => TankReading.of(
            ledger: _app.ledger,
            tankLitres: _app.setup.value.tankLitres,
            trips: trips,
          ),
          selected: () => _library.selected.value,
          rest: () => _app.restVoltage.readings,
          sharer: _sharer,
          now: widget.clock.now,
          mode: signals.mode,
          width: w,
          height: h,
          onClose: _close,
        );
      case _Form.none:
      case _Form.pitStop:
      case _Form.price:
        return PitStopPage(
          key: ValueKey(_form),
          width: w,
          height: h,
          mode: signals.mode,
          priceOnly: _form == _Form.price,
          tankLitres: _app.setup.value.tankLitres,
          currentPrice: _app.money.price.value,
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
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                // A long-press opens the debug overlay: for the person testing in a
                // car, never shown by itself.
                behavior: HitTestBehavior.translucent,
                // Nothing to announce: it is a tool, and a gesture node over the
                // whole screen upsets the semantics tree of what is under it.
                excludeFromSemantics: true,
                onLongPress: () => setState(() => _debug = true),
                child: _driving(signals, motion, w, h),
              ),
            ),
            if (_debug)
              Positioned(
                left: 0,
                top: 0,
                // A tool for the person testing, not something to read out.
                child: ExcludeSemantics(
                  child: DebugOverlay(
                    rows: _rows,
                    onClose: () => setState(() => _debug = false),
                    onOpenLab: widget.onOpenLab == null
                        ? null
                        : () {
                            setState(() => _debug = false);
                            widget.onOpenLab!();
                          },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _driving(
    DriveSignals signals,
    MotionClock motion,
    double w,
    double h,
  ) {
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
                replaySound: _sound,
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
            onInsights: () => _open(_Form.insights),
            onEndTrip: () => _services?.recorder.endNow(),
            endTripAvailable: _tripRunning,
          ),
          if (_form != _Form.none)
            Positioned.fill(
              child: TapeBackdrop(child: _overlay(signals, w, h)),
            ),
        ],
      ),
    );
  }
}
