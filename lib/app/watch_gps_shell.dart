import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../location/gps_drive.dart';
import '../platform/device_features.dart';
import '../ui/design/components/numeral_settle.dart';
import '../ui/design/components/watch/watch_crown.dart';
import '../ui/design/components/watch/watch_face.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/pages/drive/gps_signals.dart';
import '../ui/pages/watch/watch_gps_face.dart';
import '../ui/pages/watch/watch_reel.dart';
import '../ui/pages/watch/watch_sheets.dart';
import '../vehicle/vehicle_state.dart' show DrivingMode;
import 'app_services.dart';
import 'exchange_coordinator.dart';
import 'watch_menu.dart';

/// The watch's drive on the GPS alone (DESIGN.md 7.15, 16.5): the speed and what a
/// GPS can honestly add up to, and the menu, in a reel of two faces. It is the
/// small cousin of `WatchShell`, as `GpsShell` is of `DriveShell`: no adapter, no
/// tach, no trips, no money. The Motion and Parked rules are the same: the menu is
/// reachable only when the car has stood still for five seconds.
class WatchGpsShell extends StatefulWidget {
  const WatchGpsShell({
    super.key,
    required this.gps,
    required this.app,
    required this.clock,
    required this.scheduler,
    this.device,
    this.onChangeAdapter,
    this.phoneHot,
    this.exchange,
  });

  /// The GPS drive, started and disposed by whoever made it.
  final GpsDrive gps;
  final AppServices app;
  final Clock clock;
  final Scheduler scheduler;
  final DeviceFeatures? device;
  final VoidCallback? onChangeAdapter;
  final ValueListenable<bool>? phoneHot;
  final ExchangeCoordinator? exchange;

  @override
  State<WatchGpsShell> createState() => _WatchGpsShellState();
}

class _WatchGpsShellState extends State<WatchGpsShell>
    with WidgetsBindingObserver {
  GpsSignals? _signals;
  final GlobalKey<WatchMenuState> _menuKey = GlobalKey();
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
    _signals = GpsSignals(
      gps: widget.gps,
      motion: MotionScope.of(context),
      clock: widget.clock,
      scheduler: widget.scheduler,
      phoneHot: widget.phoneHot,
      reduceMotion: widget.app.settings.reduceMotion.value,
    );
    unawaited(widget.gps.start());
    _signals!.drive.mode.addListener(_syncMoving);
    _syncMoving();
  }

  void _syncMoving() {
    widget.exchange?.moving.value =
        _signals?.drive.mode.value == DrivingMode.motion;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signals?.drive.mode.removeListener(_syncMoving);
    widget.exchange?.moving.value = false;
    _signals?.dispose();
    super.dispose();
  }

  /// The Back button: nothing while moving; a menu screen closes; otherwise Android's.
  @override
  Future<bool> didPopRoute() async {
    final signals = _signals;
    if (signals == null) return false;
    if (signals.drive.mode.value == DrivingMode.motion) return true;
    return _menuKey.currentState?.back() ?? false;
  }

  void _openMenu() {
    if (_signals!.drive.mode.value != DrivingMode.parked) return;
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
                  face: face,
                  motion: motion,
                  mode: signals.drive.mode,
                  // Speed, and the menu's cover: Motion stays on the speed.
                  motionFaces: 1,
                  rotary: _menuOpen ? null : _rotary,
                  onTapFace: (i) {
                    // The speed takes the tap to the next face, as everywhere;
                    // the cover takes it to open the menu.
                    if (i != 1) return false;
                    _openMenu();
                    return true;
                  },
                  faces: [
                    NumeralSettle(
                      share: signals.drive.parkedShare,
                      child: WatchGpsFace(
                        signals: signals,
                        face: face,
                        onAllowLocation: () => unawaited(widget.gps.start()),
                      ),
                    ),
                    WatchMenuCover(face: face),
                  ],
                ),
                WatchCrown(
                  face: face,
                  gpsHasFix: signals.drive.gpsHasFix,
                  hot: signals.drive.phoneHot,
                ),
                Positioned.fill(
                  child: WatchMenu(
                    key: _menuKey,
                    app: widget.app,
                    face: face,
                    motion: motion,
                    rotary: _rotary,
                    exchange: widget.exchange,
                    onChangeAdapter: widget.onChangeAdapter,
                    onResetTrip: widget.gps.resetTrip,
                    gpsOnly: true,
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
