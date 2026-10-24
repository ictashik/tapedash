// Drives the debug build's stand-in for Google Maps' notification from a simulated
// drive (docs/NAV.md): the navigation half of `tool/sim_server.dart --nav-adb`.
//
// It follows the simulated car along a route, asks NavSimulator what Maps would
// post, and sends it to the phone or emulator with adb. The stand-in
// (NavStandInReceiver.kt, in the debug build only) posts it as a notification,
// which the app's own listener reads exactly as it would Google Maps'.
import 'dart:async';
import 'dart:io';

import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/nav/nav_simulator.dart';
import 'package:tapedash/nav/nav_state.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// Sends what the simulated Maps does to the stand-in, with adb.
class NavStandIn {
  NavStandIn({
    this.serial,
    this.package = 'io.github.ictashik.tapedash',
    this.log = _ignore,
  });

  final String? serial;
  final String package;
  final void Function(String message) log;

  static void _ignore(String message) {}

  // adb takes a few hundred milliseconds a call, so calls queue and a backlog is
  // not allowed to build up.
  Future<void> _last = Future<void>.value();
  int _queued = 0;

  /// Posts [n], or updates the notification with it.
  Future<void> post(NavNotification n) {
    final parts = ['am', 'broadcast', '-n', '$package/.NavStandInReceiver'];
    void es(String key, String? value) {
      if (value != null) parts.addAll(['--es', key, _quote(value)]);
    }

    es('title', n.title);
    es('text', n.text);
    es('sub', n.subText);
    es('short', n.shortCriticalText);
    if ((n.progressMax ?? 0) > 0) {
      parts.addAll([
        '--ei',
        'progress',
        '${n.progress ?? 0}',
        '--ei',
        'max',
        '${n.progressMax}',
      ]);
    }
    parts.addAll(['--es', 'arrow', _kind(n)]);
    return _send(parts.join(' '));
  }

  /// Takes the notification away, as Maps does when the route ends.
  Future<void> remove() =>
      _send('am broadcast -n $package/.NavStandInReceiver --ez remove true');

  Future<void> _send(String command) {
    if (_queued >= 3) return _last;
    _queued++;
    _last = _last.then((_) async {
      final result = await Process.run('adb', [
        if (serial != null) ...['-s', serial!],
        'shell',
        command,
      ]);
      _queued--;
      if (result.exitCode != 0) {
        log('adb: ${(result.stderr as String).trim()}');
      }
    });
    return _last;
  }

  /// The kind of arrow, from the name NavArrows gives the pictures it draws
  /// (`sim-left-1a2b3c4d`).
  static String _kind(NavNotification n) {
    final id = n.arrow?.id ?? '';
    final match = RegExp(r'^sim-(\w+?)-').firstMatch(id);
    final kind = match?.group(1);
    return switch (kind) {
      'left' || 'right' || 'straight' || 'uturn' => kind!,
      _ => 'none',
    };
  }

  /// [value] as one word for the phone's shell: in single quotes, an apostrophe
  /// closing and reopening them.
  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

/// A simulated Google Maps, following a simulated car (docs/NAV.md).
///
/// The car's own distance and speed are the truth, so what Maps says here and what
/// the app reads from the car's OBD agree to the error of the OBD (whole km/h,
/// smoothed) and Maps' rounding: that agreement is what an end-to-end test checks.
class NavDrive {
  NavDrive({
    required this.car,
    required this.standIn,
    required this.scheduler,
    this.shape = NavShape.progress,
    this.routeLengthM = 12000,
    this.turnEveryM = 650,
    this.log = _ignore,
  });

  final SimulatedCar car;
  final NavStandIn standIn;
  final Scheduler scheduler;
  final NavShape shape;
  final double routeLengthM;
  final double turnEveryM;
  final void Function(String message) log;

  static void _ignore(String message) {}

  late final NavSimulator _sim = NavSimulator(
    route: NavRoute.zigzag(lengthM: routeLengthM, everyM: turnEveryM),
    shape: shape,
  );
  ScheduledTask? _task;
  double _baseM = 0;
  int _posts = 0;

  /// Starts following the car from where it is now.
  void start() {
    if (_task != null) return;
    _baseM = car.truth.distanceKm * 1000;
    log('navigation: a ${routeLengthM.round()} m route, ${shape.name} shape');
    _task = scheduler.runEvery(const Duration(milliseconds: 500), _tick);
  }

  void _tick() {
    final event = _sim.step(
      travelledM: car.truth.distanceKm * 1000 - _baseM,
      speedMs: car.state.speedMs,
      now: DateTime.now(),
    );
    switch (event) {
      case NavPost(:final notification):
        _posts++;
        if (_posts % 10 == 1) log('navigation: ${notification.title}');
        standIn.post(notification);
      case NavRemove():
        log('navigation: arrived');
        standIn.remove();
        stop();
      case null:
        break;
    }
  }

  void stop() {
    _task?.cancel();
    _task = null;
  }
}
