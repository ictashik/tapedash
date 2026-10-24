import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../insights/rest_voltage_log.dart';
import '../location/location_source.dart';
import '../location/location_status.dart';
import '../platform/device_features.dart';
import '../platform/native_location_source.dart';
import '../trips/trip.dart';
import '../ui/design/components/numeral_settle.dart';
import '../ui/design/components/watch/watch_connection_layer.dart';
import '../ui/design/components/watch/watch_crown.dart';
import '../ui/design/components/watch/watch_face.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/pages/drive/drive_signals.dart';
import '../ui/pages/money/money_signals.dart';
import '../ui/pages/watch/watch_drive_face.dart';
import '../ui/pages/watch/watch_money_face.dart';
import '../ui/pages/watch/watch_reel.dart';
import '../ui/pages/watch/watch_sheets.dart';
import '../ui/pages/watch/watch_where_face.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_services.dart';
import 'drive_feed.dart';
import 'drive_services.dart';
import 'exchange_coordinator.dart';
import 'live_drive.dart';
import 'watch_menu.dart';

/// The driving surface on a watch (DESIGN.md 16): the reel of faces, the menu's
/// wheels, and the same service graph as the phone's `DriveShell` under them (the
/// trip computer and recorder on the feed's vehicle), fed by a [DriveFeed].
///
/// It is **not** the phone's screens made small. A watch has no strip of five pages,
/// no HUD, no engine sound and no Review, Coach, History, Insights or Diagnostics
/// (they are the phone's, and what the watch records goes there as a file,
/// docs/EXCHANGE.md); it has the Drive face, the Money face, where it went, and a
/// menu of what is worth changing at the wrist.
class WatchShell extends StatefulWidget {
  const WatchShell({
    super.key,
    required this.feed,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.location,
    this.app,
    this.device,
    this.onChangeAdapter,
    this.phoneHot,
    this.exchange,
  });

  /// Moves the app's data out and in (docs/EXCHANGE.md): the menu's Data row.
  final ExchangeCoordinator? exchange;

  final Clock clock;
  final Scheduler scheduler;

  /// Where the readings come from. Someone else starts and disposes it.
  final DriveFeed feed;

  /// The watch's GPS, for the route of a trip. Null uses its own.
  final LocationSource? location;

  final AppServices? app;

  /// The bezel and the sensors. Null is a watch with neither.
  final DeviceFeatures? device;

  /// The menu's request to choose an adapter (the connect flow is the app's).
  final VoidCallback? onChangeAdapter;

  /// Whether the watch is hot, for the crown's glyph.
  final ValueListenable<bool>? phoneHot;

  @override
  State<WatchShell> createState() => _WatchShellState();
}

class _WatchShellState extends State<WatchShell> with WidgetsBindingObserver {
  late final DriveFeed _feed = widget.feed;
  late final AppServices _app = widget.app ?? AppServices.inMemory();
  final GlobalKey<WatchReelState> _reelKey = GlobalKey();
  LocationSource? _location;
  LocationStatus? _gps;
  ObservableListenable<bool>? _gpsListenable;
  DriveServices? _services;
  MoneySignals? _money;
  DriveSignals? _signals;
  RestVoltageWatcher? _restWatcher;
  final ValueNotifier<bool> _tripRunning = ValueNotifier(false);

  final GlobalKey<WatchMenuState> _menuKey = GlobalKey();

  /// Whether the menu is up, so that the reel lets go of the bezel to it.
  bool _menuOpen = false;

  Stream<int>? get _rotary => widget.device?.rotary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_signals != null) return;
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
    _restWatcher = RestVoltageWatcher(
      vehicle: _feed.vehicle,
      log: _app.restVoltage,
    );
    _feed.start(); // a no-op if it is already running
    unawaited(_startLocation(location));
    // A trip that ends is laid out as where it went; one that resumes (the
    // engine came back within five minutes) puts the reel back on the speed.
    services.recorder
      ..onTripEnded(_onTripEnded)
      ..onTripResumed(_onTripResumed);
    _app.settings.coachPreset.addListener(_onCoach);
    _app.settings.speedLimitKmh.addListener(_onCoach);
    widget.exchange?.changes.addListener(_onExchanged);
    _signals!.mode.addListener(_syncMoving);
    _syncMoving();
  }

  void _onExchanged() => _money?.refreshFills();

  void _syncMoving() {
    widget.exchange?.moving.value = _signals?.mode.value == DrivingMode.motion;
  }

  void _syncTrip() =>
      _tripRunning.value = _services?.recorder.recording ?? false;

  Future<void> _startLocation(LocationSource location) async {
    try {
      await location.start();
    } on Object catch (error) {
      debugPrint('The GPS did not start: $error');
    }
  }

  void _onCoach() => _services?.setThresholds(_app.settings.thresholds);

  Future<void> _onTripEnded(Trip trip) async {
    await _services!.recorder.idle;
    if (!mounted) return;
    _reelKey.currentState?.goTo(_whereFace);
  }

  void _onTripResumed(Trip trip) => _reelKey.currentState?.goTo(0);

  /// The reel's faces, in order: Drive, Money, Where it went, Menu.
  static const int _whereFace = 2;
  static const int _menuFace = 3;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.exchange?.changes.removeListener(_onExchanged);
    _signals?.mode.removeListener(_syncMoving);
    widget.exchange?.moving.value = false;
    _app.settings.coachPreset.removeListener(_onCoach);
    _app.settings.speedLimitKmh.removeListener(_onCoach);
    _restWatcher?.dispose();
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

  /// The Back button (DESIGN.md 16.6): nothing while moving, so a knock on the
  /// wrist cannot close the dash; a screen over the reel closes; otherwise the
  /// app does what Android does.
  @override
  Future<bool> didPopRoute() async {
    final signals = _signals;
    if (signals == null) return false;
    if (signals.mode.value == DrivingMode.motion) return true;
    return _menuKey.currentState?.back() ?? false;
  }

  void _openMenu() {
    if (_signals!.mode.value != DrivingMode.parked) return;
    _menuKey.currentState?.open();
  }

  @override
  Widget build(BuildContext context) {
    final signals = _signals!;
    final motion = MotionScope.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final face = WatchFace.of(box.maxWidth, box.maxHeight);
        return Center(
          child: SizedBox.square(
            dimension: face.diameter,
            child: Stack(
              children: [
                WatchReel(
                  key: _reelKey,
                  face: face,
                  motion: motion,
                  mode: signals.mode,
                  rotary: _menuOpen ? null : _rotary,
                  onTapFace: (i) {
                    if (i != _menuFace) return false;
                    _openMenu();
                    return true;
                  },
                  overlay: WatchConnectionLayer(
                    presentation: signals.linkPresentation,
                    face: face,
                  ),
                  faces: [
                    // Parked, every figure rests on a whole digit.
                    NumeralSettle(
                      share: signals.parkedShare,
                      child: WatchDriveFace(signals: signals, face: face),
                    ),
                    NumeralSettle(
                      share: signals.parkedShare,
                      child: WatchMoneyFace(signals: signals, face: face),
                    ),
                    NumeralSettle(
                      share: signals.parkedShare,
                      child: WatchWhereFace(signals: signals, face: face),
                    ),
                    WatchMenuCover(face: face),
                  ],
                ),
                WatchCrown(
                  face: face,
                  adapter: signals.adapter,
                  gpsHasFix: signals.gpsHasFix,
                  hot: signals.phoneHot,
                ),
                Positioned.fill(
                  child: WatchMenu(
                    key: _menuKey,
                    app: _app,
                    face: face,
                    motion: motion,
                    rotary: _rotary,
                    exchange: widget.exchange,
                    onChangeAdapter: widget.onChangeAdapter,
                    onEndTrip: () => _services?.recorder.endNow(),
                    tripRunning: _tripRunning,
                    onOpenChanged: (open) => setState(() => _menuOpen = open),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
