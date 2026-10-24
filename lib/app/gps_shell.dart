import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../location/gps_drive.dart';
import '../platform/nav_channel.dart';
import '../trips/trip_library.dart';
import '../ui/design/components/backdrop.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/dev/debug_overlay.dart';
import '../ui/hud/hud_host.dart';
import '../ui/hud/hud_settings.dart';
import '../ui/pages/drive/gps_cluster.dart';
import '../ui/pages/drive/gps_signals.dart';
import '../ui/pages/garage/garage_page.dart';
import '../ui/pages/strip/parked_dock.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_info.dart';
import 'app_services.dart';
import 'exchange_coordinator.dart';
import 'nav_service.dart';

/// The driving surface for a drive on the phone's GPS alone: the speed and what a
/// GPS can add up to ([GpsCluster]), the parked dock with Garage, the HUD and
/// Reset trip, and the HUD over all of it.
///
/// It is a small cousin of `DriveShell` and has none of its parts: there is no
/// adapter, no tach, no trip log, no money, no coach and no engine sound, because
/// none has anything to read. The Motion and Parked rules are the same
/// (settings are reachable only when the car has stood still for five seconds),
/// and so are the HUD, the look and Garage's display settings.
class GpsShell extends StatefulWidget {
  const GpsShell({
    super.key,
    required this.gps,
    required this.app,
    required this.clock,
    required this.scheduler,
    this.onChangeAdapter,
    this.phoneHot,
    this.phoneTemperature,
    this.debugRows = const [],
    this.onOpenLab,
    this.exchange,
    this.navSource,
  });

  /// Moves the app's data out and in (docs/EXCHANGE.md).
  final ExchangeCoordinator? exchange;

  /// Where Google Maps' navigation notification comes from (docs/NAV.md). Null uses
  /// the phone's own listener; tests give one in memory.
  final NavSource? navSource;

  /// The GPS drive, started and disposed by whoever made it.
  final GpsDrive gps;
  final AppServices app;
  final Clock clock;
  final Scheduler scheduler;

  /// Garage's request to choose an adapter (the connect flow is the app's).
  final VoidCallback? onChangeAdapter;

  final ValueListenable<bool>? phoneHot;
  final Observable<double?>? phoneTemperature;

  /// What the app knows of the phone, for the debug overlay.
  final List<DebugRow> debugRows;
  final VoidCallback? onOpenLab;

  @override
  State<GpsShell> createState() => _GpsShellState();
}

class _GpsShellState extends State<GpsShell> {
  GpsSignals? _signals;
  late final HudSettings _hud = widget.app.settings.hud;
  late final TripLibrary _library = TripLibrary(widget.app.trips);
  NavService? _nav;
  bool _garage = false;
  bool _debug = false;
  final List<ChangeNotifier> _debugSources = [];
  List<DebugRow> _rows = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_signals != null) return;
    _signals = GpsSignals(
      gps: widget.gps,
      motion: MotionScope.of(context),
      clock: widget.clock,
      scheduler: widget.scheduler,
      phoneHot: widget.phoneHot,
      reduceMotion: widget.app.settings.reduceMotion.value,
    );
    _nav = NavService(
      settings: widget.app.settings,
      source: widget.navSource ?? NativeNavSource(),
      clock: widget.clock,
      scheduler: widget.scheduler,
      speed: widget.gps.vehicle.motion,
    )..start();
    unawaited(widget.gps.start());
    widget.exchange?.changes.addListener(_onExchanged);
    _signals!.drive.mode.addListener(_syncMoving);
    _syncMoving();
    _buildDebugRows();
  }

  void _onExchanged() => _library.refresh();

  void _syncMoving() {
    widget.exchange?.moving.value =
        _signals?.drive.mode.value == DrivingMode.motion;
  }

  void _buildDebugRows() {
    ComputedText row(List<Listenable> sources, String Function() text) {
      final c = ComputedText(sources, text);
      _debugSources.add(c);
      return c;
    }

    final gps = widget.gps;
    final phase = ObservableListenable(gps.phase);
    final fix = ObservableListenable(gps.status.last);
    _debugSources
      ..add(phase)
      ..add(fix);
    _rows = [
      DebugRow('Source', row(const [], () => 'GPS only')),
      DebugRow('GPS', row([phase], () => gps.phase.value.name)),
      DebugRow(
        'Accuracy',
        row([fix], () {
          final f = gps.status.last.value;
          return f == null ? '—' : '±${f.accuracyM.toStringAsFixed(0)} m';
        }),
      ),
      // The state of the link only, never what Maps said (CLAUDE.md 4).
      if (_nav != null)
        DebugRow(
          'Navigation',
          row([_nav!.status], () => _nav!.status.value.name),
        ),
      ...widget.debugRows,
    ];
  }

  @override
  void dispose() {
    widget.exchange?.changes.removeListener(_onExchanged);
    _signals?.drive.mode.removeListener(_syncMoving);
    widget.exchange?.moving.value = false;
    for (final s in _debugSources) {
      s.dispose();
    }
    _nav?.dispose();
    _signals?.dispose();
    super.dispose();
  }

  void _openGarage() {
    if (_signals!.drive.mode.value != DrivingMode.parked) return;
    setState(() => _garage = true);
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
                behavior: HitTestBehavior.translucent,
                excludeFromSemantics: true,
                onLongPress: () => setState(() => _debug = true),
                child: HudHost(
                  settings: _hud,
                  signals: signals.drive,
                  width: w,
                  height: h,
                  // Only the speed can go on the glass: no tach, no money.
                  layout: HudLayout.drive,
                  showRpm: false,
                  nav: _nav,
                  child: Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        excludeFromSemantics: true,
                        onDoubleTap: _hud.toggle,
                        child: GpsCluster(
                          signals: signals,
                          width: w,
                          height: h,
                          onAllowLocation: () => unawaited(widget.gps.start()),
                        ),
                      ),
                      ParkedDock(
                        mode: signals.drive.mode,
                        motion: motion,
                        width: w,
                        height: h,
                        carButtons: false,
                        onGarage: _openGarage,
                        onHud: _hud.toggle,
                        onReset: widget.gps.resetTrip,
                      ),
                      if (_garage)
                        Positioned.fill(
                          child: TapeBackdrop(
                            child: GaragePage(
                              settings: widget.app.settings,
                              services: widget.app,
                              library: _library,
                              mode: signals.drive.mode,
                              width: w,
                              height: h,
                              onClose: () => setState(() => _garage = false),
                              adapters: widget.app.adapters,
                              onChangeAdapter: widget.onChangeAdapter,
                              phoneTemperature: widget.phoneTemperature,
                              gpsOnly: true,
                              onAlignment: () => _hud.showAlignment = true,
                              nav: _nav,
                              version: appVersion,
                              exchange: widget.exchange,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_debug)
              Positioned(
                left: 0,
                top: 0,
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
}
