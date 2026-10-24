import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../insights/rest_voltage_log.dart';
import '../location/location_source.dart';
import '../location/location_status.dart';
import '../obd/adapter_config.dart';
import '../platform/device_features.dart';
import '../platform/native_location_source.dart';
import '../trips/trip.dart';
import '../ui/design/components/numeral_settle.dart';
import '../ui/design/components/watch/watch_connection_layer.dart';
import '../ui/design/components/watch/watch_crown.dart';
import '../ui/design/components/watch/watch_face.dart';
import '../ui/design/components/watch/watch_wheel.dart';
import '../ui/design/motion/motion_clock.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/design/tokens/livery.dart';
import '../ui/pages/drive/drive_signals.dart';
import '../ui/pages/money/money_signals.dart';
import '../ui/pages/watch/watch_drive_face.dart';
import '../ui/pages/watch/watch_money_face.dart';
import '../ui/pages/watch/watch_reel.dart';
import '../ui/pages/watch/watch_sheets.dart';
import '../ui/pages/watch/watch_where_face.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_info.dart';
import 'app_services.dart';
import 'drive_feed.dart';
import 'drive_services.dart';
import 'exchange_coordinator.dart';
import 'live_drive.dart';

/// Which screen is over the reel.
enum _Sheet { none, menu, source, price, look, data, message, about }

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

  /// The screens over the reel, innermost last.
  final List<_Sheet> _sheets = [];

  _Sheet get _sheet => _sheets.isEmpty ? _Sheet.none : _sheets.last;

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
    if (_sheets.isNotEmpty) {
      _close();
      return true;
    }
    return false;
  }

  void _open(_Sheet sheet) {
    if (_signals!.mode.value != DrivingMode.parked) return;
    setState(() => _sheets.add(sheet));
  }

  void _close() {
    if (_sheets.isEmpty) return;
    setState(_sheets.removeLast);
  }

  void _closeAll() => setState(_sheets.clear);

  /// Says what an export or an import did, over the Data wheel.
  void _show() {
    if (!mounted) return;
    setState(() => _sheets.add(_Sheet.message));
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
                  rotary: _sheet == _Sheet.none ? _rotary : null,
                  onTapFace: (i) {
                    if (i != _menuFace) return false;
                    _open(_Sheet.menu);
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
                if (_sheet != _Sheet.none)
                  Positioned.fill(
                    child: WatchSheet(
                      face: face,
                      onClose: _close,
                      // Its own key: a wheel opened over a wheel would be the
                      // same widget in the same place, and keep the other's row.
                      child: KeyedSubtree(
                        key: ValueKey(_sheet),
                        child: _sheetBody(face, motion),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetBody(WatchFace face, MotionClock motion) {
    final rotary = _rotary;
    switch (_sheet) {
      case _Sheet.menu:
      case _Sheet.none:
        return ListenableBuilder(
          listenable: Listenable.merge([
            _tripRunning,
            ObservableListenable(_app.adapters.source),
            ObservableListenable(_app.money.price),
            if (widget.exchange != null)
              ObservableListenable(widget.exchange!.status),
          ]),
          builder: (context, _) {
            final source = _app.adapters.source.value;
            final price = _app.money.price.value;
            final items = <(String, String?, VoidCallback)>[
              (
                'Connect',
                _app.adapters.adapter.value?.displayName ?? 'No adapter',
                () {
                  _closeAll();
                  widget.onChangeAdapter?.call();
                },
              ),
              (
                'Speed from',
                source == DriveSource.gps ? 'GPS only' : 'Adapter',
                () => _open(_Sheet.source),
              ),
              if (source != DriveSource.gps)
                (
                  'Price',
                  price == null
                      ? 'Not set'
                      : '₹${price.toStringAsFixed(1)} a litre',
                  () => _open(_Sheet.price),
                ),
              (
                'Look',
                _app.settings.livery.value.name.toUpperCase(),
                () => _open(_Sheet.look),
              ),
              if (widget.exchange != null)
                (
                  'Data',
                  widget.exchange!.status.value.inboxFiles > 0
                      ? '${widget.exchange!.status.value.inboxFiles} waiting'
                      : null,
                  () => _open(_Sheet.data),
                ),
              if (_tripRunning.value)
                (
                  'End trip',
                  null,
                  () {
                    _services?.recorder.endNow();
                    _closeAll();
                  },
                ),
              ('About', appVersion, () => _open(_Sheet.about)),
            ];
            return WatchWheel(
              title: 'Menu',
              itemCount: items.length,
              face: face,
              motion: motion,
              rotary: rotary,
              rowAt: (i) => WheelRow(label: items[i].$1, value: items[i].$2),
              onChoose: (i) => items[i].$3(),
            );
          },
        );
      case _Sheet.source:
        final adapter = _app.adapters.adapter.value != null;
        final gps = _app.adapters.source.value == DriveSource.gps;
        return WatchChoiceWheel(
          title: 'Speed from',
          labels: const ['Adapter', 'GPS only'],
          chosen: gps ? 1 : 0,
          face: face,
          motion: motion,
          rotary: rotary,
          onChoose: (i) {
            if (i == 1) {
              unawaited(_app.adapters.setSource(DriveSource.gps));
            } else if (adapter) {
              unawaited(_app.adapters.setSource(DriveSource.obd));
            } else {
              _closeAll();
              widget.onChangeAdapter?.call();
              return;
            }
            _closeAll();
          },
        );
      case _Sheet.price:
        const first = 60.0;
        const step = 0.1;
        const count = 1001;
        final current = _app.money.price.value ?? 100.0;
        return WatchWheel(
          title: '₹ a litre',
          itemCount: count,
          initial: ((current - first) / step).round().clamp(0, count - 1),
          fastStride: 10,
          face: face,
          motion: motion,
          rotary: rotary,
          rowAt: (i) =>
              WheelRow(label: '₹${(first + i * step).toStringAsFixed(1)}'),
          onChoose: (i) {
            unawaited(
              _app.money.setPrice(
                double.parse((first + i * step).toStringAsFixed(1)),
              ),
            );
            _close();
          },
        );
      case _Sheet.look:
        final now = _app.settings.livery.value;
        return WatchChoiceWheel(
          title: 'Look',
          labels: [for (final l in Liveries.all) l.name],
          chosen: Liveries.all.indexWhere((l) => l.id == now),
          face: face,
          motion: motion,
          rotary: rotary,
          onChoose: (i) {
            _app.settings.livery.value = Liveries.all[i].id;
            _close();
          },
        );
      case _Sheet.data:
        final exchange = widget.exchange;
        if (exchange == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: ObservableListenable(exchange.status),
          builder: (context, _) {
            final s = exchange.status.value;
            final rows = <(String, String?, Future<void> Function())>[
              (
                'Export',
                'to the outbox folder',
                () async {
                  await exchange.exportAll();
                  _show();
                },
              ),
              (
                'Import',
                s.inboxFiles == 0
                    ? 'inbox is empty'
                    : '${s.inboxFiles} file${s.inboxFiles == 1 ? '' : 's'} waiting',
                () async {
                  await exchange.importInbox();
                  _show();
                },
              ),
              if (s.offered.isNotEmpty)
                (
                  'Apply setup',
                  'from the last file',
                  () async {
                    await exchange.applyOffered();
                    _show();
                  },
                ),
            ];
            return WatchWheel(
              title: 'Data',
              itemCount: rows.length,
              face: face,
              motion: motion,
              rotary: rotary,
              rowAt: (i) => WheelRow(label: rows[i].$1, value: rows[i].$2),
              onChoose: (i) => unawaited(rows[i].$3()),
            );
          },
        );
      case _Sheet.message:
        final s = widget.exchange?.status.value;
        return WatchMessage(
          face: face,
          text: s?.sentence ?? '',
          ok: s?.ok ?? true,
          lines: s?.offered ?? const [],
          onClose: _close,
        );
      case _Sheet.about:
        return WatchWheel(
          title: 'About',
          itemCount: 2,
          face: face,
          motion: motion,
          rotary: rotary,
          rowAt: (i) => i == 0
              ? const WheelRow(label: 'TapeDash', value: appVersion)
              : const WheelRow(label: 'Offline', value: 'No account, no cloud'),
          onChoose: (_) => _close(),
        );
    }
  }
}
