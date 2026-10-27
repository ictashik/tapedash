import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../nav/nav_tracker.dart';
import '../platform/nav_channel.dart';
import '../vehicle/vehicle_state.dart';
import 'app_settings.dart';

/// What Garage says about the navigation link (docs/NAV.md).
enum NavLinkStatus {
  /// The switch is off. Nothing is read.
  off,

  /// The switch is on and Google Maps is not on the phone.
  noMaps,

  /// The switch is on and Android has not granted TapeDash Notification access.
  needsAccess,

  /// Everything is in place and Maps is not navigating.
  waiting,

  /// Maps is navigating, and has said so lately.
  guiding,

  /// Maps was navigating and has gone quiet: what the HUD shows is not live.
  stale,
}

/// The navigation HUD's feed: follows the Garage switch, listens to the phone's
/// notification listener while it is on, and keeps a [NavTracker] of what Google
/// Maps says (docs/NAV.md). It sends Google Maps nothing, and it keeps nothing it
/// reads (CLAUDE.md 4, "Navigation notification").
///
/// With the switch off the service does not listen, and the native side then does
/// not open a notification at all. The car's speed, if given, is passed on to the
/// tracker for the distance that counts down between Maps' posts.
class NavService with WidgetsBindingObserver {
  NavService({
    required this.settings,
    required this.source,
    required Clock clock,
    required Scheduler scheduler,
    this.speed,
  }) : tracker = NavTracker(clock: clock, scheduler: scheduler);

  final AppSettings settings;
  final NavSource source;

  /// The car's speed, from the OBD adapter or the phone's GPS.
  final Observable<MotionSample?>? speed;

  final NavTracker tracker;

  /// Where the link is, for Garage to say.
  final ValueNotifier<NavLinkStatus> status = ValueNotifier(NavLinkStatus.off);

  /// Whether Android has granted Notification access: null until asked.
  final ValueNotifier<bool?> access = ValueNotifier(null);

  /// The version of Google Maps on the phone, once known; null if it is not there
  /// or not yet known ([mapsChecked] says which).
  final ValueNotifier<String?> mapsVersion = ValueNotifier(null);
  bool _mapsChecked = false;

  bool get mapsChecked => _mapsChecked;

  StreamSubscription<NavEvent>? _events;
  bool _started = false;
  bool _disposed = false;

  /// Starts following the switch and the screen. Call it once.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    settings.navEnabled.addListener(_apply);
    tracker.state.addListener(_recompute);
    tracker.freshness.addListener(_recompute);
    speed?.addListener(_onSpeed);
    _apply();
  }

  void _apply() {
    if (_disposed) return;
    if (settings.navEnabled.value) {
      _events ??= source.events().listen(_onEvent, onError: (Object _) {});
      unawaited(refresh());
    } else {
      final events = _events;
      _events = null;
      if (events != null) unawaited(events.cancel());
      tracker.onRemoved();
    }
    _recompute();
  }

  void _onEvent(NavEvent event) {
    switch (event) {
      case NavPosted(:final notification):
        tracker.onNotification(notification);
      case NavRemoved():
        tracker.onRemoved();
      case NavLink(:final connected):
        access.value = connected;
        if (!connected) tracker.onRemoved();
    }
    _recompute();
  }

  void _onSpeed() {
    final sample = speed?.value;
    if (sample != null) tracker.onSpeed(sample.speedMs);
  }

  /// Asks Android again whether access is granted and whether Maps is there. It is
  /// called when the switch goes on and when the app comes back to the screen (the
  /// person may have been to Android's settings).
  Future<void> refresh() async {
    final granted = await source.hasAccess();
    final maps = await source.mapsVersion();
    if (_disposed) return;
    access.value = granted;
    mapsVersion.value = maps;
    _mapsChecked = true;
    _recompute();
  }

  /// Opens Android's Notification access screen.
  Future<bool> openAccessSettings() => source.openAccessSettings();

  /// Opens Android's screen for Google Maps' notifications.
  Future<bool> openMapsNotificationSettings() =>
      source.openMapsNotificationSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && settings.navEnabled.value) {
      unawaited(refresh());
    }
  }

  void _recompute() {
    if (_disposed) return;
    status.value = _status();
  }

  NavLinkStatus _status() {
    if (!settings.navEnabled.value) return NavLinkStatus.off;
    // What is arriving comes first: if Maps is being heard, it is there, and the access
    // is granted, whatever a look for its package or for the access said. (An emulator
    // with no Maps and a stand-in is the case that showed it.) The warnings are for
    // when nothing arrives.
    switch (tracker.freshness.value) {
      case NavFreshness.fresh:
        return NavLinkStatus.guiding;
      case NavFreshness.stale:
        return NavLinkStatus.stale;
      case NavFreshness.none:
        break;
    }
    if (_mapsChecked && mapsVersion.value == null) return NavLinkStatus.noMaps;
    if (access.value == false) return NavLinkStatus.needsAccess;
    return NavLinkStatus.waiting;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      settings.navEnabled.removeListener(_apply);
      speed?.removeListener(_onSpeed);
    }
    unawaited(_events?.cancel());
    tracker.dispose();
    status.dispose();
    access.dispose();
    mapsVersion.dispose();
  }
}
