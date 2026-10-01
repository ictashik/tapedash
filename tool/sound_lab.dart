// The engine sound, to play with at a desk: a web page with a throttle, a gearbox
// and the revs, that you hear through the computer's speakers.
//
//   dart run tool/sound_lab.dart [--port 8777]     then open http://127.0.0.1:8777
//
// The sound is the app's own `EngineSynth`, rendered here in Dart and streamed to
// the page over a WebSocket as 16-bit PCM; the page only plays it. So what is heard
// is what the phone makes, not a copy of it. Local only (127.0.0.1), no network.
//
// Two ways to drive it, chosen on the page:
//  * Drive: a small car (gears, clutch, drag, a rev limiter, an automatic if
//    wanted) turns the throttle, brake and gear into revs and load.
//  * Direct: the revs and the load are set by hand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/engine_synth.dart';

const int sampleRate = 32000;

Future<void> main(List<String> args) async {
  final at = args.indexOf('--port');
  final port = at >= 0 && at + 1 < args.length ? int.parse(args[at + 1]) : 8777;
  final page = File.fromUri(Platform.script.resolve('sound_lab/index.html'));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Sound lab: http://127.0.0.1:$port  (Ctrl-C to stop)');
  await for (final request in server) {
    final path = request.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      // ignore: close_sinks, it lives until the page closes it
      final socket = await WebSocketTransformer.upgrade(request);
      Session(socket);
    } else if (path == '/' || path == '/index.html') {
      request.response.headers.contentType = ContentType.html;
      request.response.add(await page.readAsBytes());
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}

/// A small car: a gearbox and a clutch between the engine's revs and the road.
/// Not a vehicle model to be believed, just enough to make shifts, lifts and pulls
/// sound as they do.
class Car {
  Car(this.profile);

  EngineProfile profile;

  /// Gear ratios times the final drive (first to sixth), and the wheel's radius.
  static const List<double> ratios = [
    3.6 * 3.9,
    2.1 * 3.9,
    1.45 * 3.9,
    1.05 * 3.9,
    0.82 * 3.9,
    0.66 * 3.9,
  ];
  static const double reverse = 3.4 * 3.9;
  static const double wheelRadius = 0.31;
  static const double mass = 1200;

  /// 0 neutral, 1 to 6, -1 reverse.
  int gear = 0;
  bool auto = false;
  double speed = 0; // m/s, forward
  double rpm = 0;
  double load = 0;
  double clutch = 0; // 0 engaged, 1 out
  double _shiftLeft = 0;
  int _wantGear = 0;

  void shiftTo(int g) {
    final next = g.clamp(-1, 6);
    if (next == gear) return;
    _wantGear = next;
    _shiftLeft = 0.28; // the clutch is out while the lever moves
    gear = 0;
  }

  void shift(int by) => shiftTo((_shiftLeft > 0 ? _wantGear : gear) + by);

  /// Engine torque, 0 to 1, over the revs: rising to the middle, falling at the top.
  double _torque(double r) {
    final x = ((r - profile.idleRpm) / (profile.redlineRpm - profile.idleRpm))
        .clamp(0.0, 1.2);
    return (0.55 + 1.3 * x - 1.1 * x * x).clamp(0.2, 1.0).toDouble();
  }

  void step(double dt, double throttle, double brake) {
    if (rpm < 1) rpm = profile.idleRpm;
    if (_shiftLeft > 0) {
      _shiftLeft -= dt;
      if (_shiftLeft <= 0) {
        gear = _wantGear;
      }
    }
    if (auto && _shiftLeft <= 0 && gear > 0) {
      final up = profile.redlineRpm * (0.45 + 0.4 * throttle);
      if (rpm > up && gear < 6) shift(1);
      if (rpm < profile.idleRpm * 1.7 && gear > 1 && throttle > 0.05) shift(-1);
      if (rpm < profile.idleRpm * 1.3 && gear > 1) shift(-1);
    }
    if (auto &&
        gear == 0 &&
        _shiftLeft <= 0 &&
        _wantGear == 0 &&
        throttle > 0.05) {
      shiftTo(1);
    }

    final ratio = gear == -1 ? reverse : (gear >= 1 ? ratios[gear - 1] : 0.0);
    final inGear = gear != 0 && ratio > 0;
    final limiter = rpm >= profile.redlineRpm;
    final effective = limiter ? 0.0 : throttle;
    final idleHold = rpm < profile.idleRpm ? 0.12 : 0.0;

    if (inGear) {
      // Locked to the wheels, unless that would stall it (slipping the clutch).
      final wheelRpm = speed.abs() / wheelRadius * ratio * 60 / (2 * math.pi);
      final locked = math.max(profile.idleRpm, wheelRpm);
      // Held on a spring so that a shift's drop and catch is heard, not stepped.
      rpm += (locked - rpm) * (1 - math.exp(-dt * 25));
      final force = effective * _torque(rpm) * 330 * ratio / wheelRadius / 2.2;
      final drag = 0.35 * speed * speed.abs() + 140; // air and rolling
      final engineBrake = (throttle < 0.03 ? 0.02 * rpm * ratio : 0.0)
          .toDouble();
      var accel = (force - drag * speed.sign - engineBrake * speed.sign) / mass;
      if (speed.abs() < 0.2 && effective == 0) accel = 0;
      final dir = gear < 0 ? -1.0 : 1.0;
      speed += dir * accel * dt;
      speed -= speed.sign * math.min(brake * 9 * dt, speed.abs());
      if (gear > 0 && speed < 0) speed = 0;
      if (gear < 0 && speed > 0) speed = 0;
      load = limiter
          ? 0
          : (throttle < 0.03 && rpm > 1500 ? 0.0 : throttle).toDouble();
    } else {
      // Neutral or in the middle of a shift: the engine is free, and spins up and
      // down on its own with a flywheel's lag.
      final target =
          profile.idleRpm + (profile.redlineRpm - profile.idleRpm) * effective;
      final rate = target > rpm ? 5.5 : 2.2;
      rpm += (target - rpm) * (1 - math.exp(-dt * rate));
      speed -= speed.sign * math.min((brake * 9 + 0.3) * dt, speed.abs());
      load = (effective * 0.5 + idleHold).clamp(0.0, 1.0).toDouble();
    }
    rpm = rpm.clamp(0.0, profile.redlineRpm * 1.02).toDouble();
    clutch = _shiftLeft > 0 ? 1 : 0;
  }
}

/// One browser: its engine, its car, and the clock that keeps the samples coming
/// at the rate they are played.
class Session {
  Session(this._socket) {
    _synth = EngineSynth(_profile, sampleRate: sampleRate);
    _car = Car(_profile);
    _socket.listen(_onMessage, onDone: _close, onError: (_) => _close());
    _send({
      'type': 'hello',
      'sampleRate': sampleRate,
      'profiles': [
        for (final p in EngineProfile.all)
          {
            'id': p.id,
            'name': p.name,
            'description': p.description,
            'idle': p.idleRpm,
            'redline': p.redlineRpm,
            'electric': p.isElectric,
          },
      ],
    });
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => _tick());
  }

  final WebSocket _socket;
  final Stopwatch _clock = Stopwatch();
  late Timer _timer;
  late EngineSynth _synth;
  late Car _car;
  EngineProfile _profile = EngineProfile.all.first;
  final Float64List _scratch = Float64List(1024);

  // From the page.
  bool _drive = true;
  bool _on = true;
  double _throttle = 0;
  double _brake = 0;
  double _directRpm = 800;
  double _directLoad = 0.12;
  double _produced = 0; // samples rendered so far
  double _lastTick = 0;
  int _statusAt = 0;

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    double num_(String k, double fallback) =>
        (m[k] is num) ? (m[k] as num).toDouble() : fallback;
    switch (m['type']) {
      case 'controls':
        _throttle = num_('throttle', _throttle).clamp(0.0, 1.0).toDouble();
        _brake = num_('brake', _brake).clamp(0.0, 1.0).toDouble();
        _directRpm = num_('rpm', _directRpm);
        _directLoad = num_('load', _directLoad);
        if (m['mode'] is String) _drive = m['mode'] == 'drive';
        if (m['on'] is bool) _on = m['on'] as bool;
        if (m['auto'] is bool) _car.auto = m['auto'] as bool;
      case 'profile':
        _profile = EngineProfile.byId(m['id'] as String?);
        _synth = EngineSynth(_profile, sampleRate: sampleRate);
        _car = Car(_profile)..auto = _car.auto;
      case 'gear':
        if (m['to'] is num) _car.shiftTo((m['to'] as num).toInt());
        if (m['by'] is num) _car.shift((m['by'] as num).toInt());
      case 'start':
        _car.speed = 0;
        _car.gear = 0;
        _car.rpm = _profile.idleRpm;
    }
  }

  void _tick() {
    if (_socket.readyState != WebSocket.open) return;
    final now = _clock.elapsedMicroseconds / 1e6;
    var dt = now - _lastTick;
    _lastTick = now;
    if (dt <= 0) return;
    dt = math.min(dt, 0.05);

    final double rpm;
    final double load;
    if (_drive) {
      _car.step(dt, _throttle, _brake);
      rpm = _car.rpm;
      load = _car.load;
    } else {
      rpm = _directRpm;
      load = _directLoad;
    }
    _synth.setTargets(rpm: rpm, load: load, active: _on);

    // Keep about 60 ms ahead of what has been played: the page buffers a little
    // more, so a late timer is not a gap.
    final want = ((now + 0.06) * sampleRate).floor();
    var count = want - _produced.floor();
    if (count <= 0) return;
    count = math.min(count, sampleRate ~/ 4);
    final pcm = Int16List(count);
    _synth.renderPcm16(pcm, count, scratch: _scratch);
    _produced += count;
    _socket.add(pcm.buffer.asUint8List());

    final ms = (now * 1000).floor();
    if (ms - _statusAt >= 50) {
      _statusAt = ms;
      _send({
        'type': 'state',
        'rpm': rpm,
        'load': load,
        'speed': _car.speed * 3.6,
        'gear': _car.gear,
        'shifting': _car.clutch > 0,
        'wantGear': _car.clutch > 0 ? _car._wantGear : _car.gear,
        'drive': _drive,
      });
    }
  }

  void _send(Map<String, Object?> m) => _socket.add(jsonEncode(m));

  void _close() {
    _timer.cancel();
  }
}
