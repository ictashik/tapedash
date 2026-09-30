import 'dart:math' as math;
import 'dart:typed_data';

import 'engine_profile.dart';

/// An engine, made of arithmetic: given the revs and the load, it renders the
/// sound of one (mono, 16-bit, [sampleRate] samples a second).
///
/// **How it is made** (a combustion engine; every part is a few lines):
///  * The crank turns at the revs; a cylinder fires when the crank reaches its angle,
///    `cylinders / 2` times a turn. Each firing is an impulse placed between two
///    samples (so that the pitch is exact at any revs, not stepped to the sample
///    rate), as strong as the load and the cylinder's own strength say, and a little
///    off in strength and time at low revs (the lope of an idle).
///  * Two one-pole filters make each impulse the soft-edged exhaust pulse.
///  * The pulse runs down a pipe, a feedback comb whose delay is the round trip of
///    the pipe at the speed of sound in hot gas, with the top of it lost on each
///    trip: that is the ring and the boom of an exhaust.
///  * A few band-passes (the body's resonances) are mixed in, and a low-pass, which
///    the throttle opens, is the muffler.
///  * On top: the intake's rush (filtered noise, with the throttle and the revs), a
///    tick at each firing, a turbo's whistle with load and its hiss when the
///    throttle closes, and pops on an overrun.
///
/// An electric profile is a whine instead: three harmonics of a tone that rises with
/// the revs, and a hum.
///
/// **Smoothness.** The revs and the load it is given are targets, and what it
/// sounds is a step towards them every millisecond: the revs can rise at most 9000
/// and fall at most 6000 a second (a real engine has a flywheel), so a reading that
/// arrives late or in a jump is a glide and never a click. Its gain fades in and
/// out. It is deterministic: the same profile, seed and controls give the same
/// samples.
///
/// **Loudness.** On creation each engine is run for a moment at a reference load
/// and its level set to a fixed one, so that changing profile does not change the
/// volume.
///
/// It allocates nothing while it renders.
class EngineSynth {
  EngineSynth(this.profile, {this.sampleRate = 32000, this.seed = 1})
    : _comb = Float64List(_combLength(profile, sampleRate) + 1),
      _bandB0 = Float64List(profile.formants.length),
      _bandA1 = Float64List(profile.formants.length),
      _bandA2 = Float64List(profile.formants.length),
      _bandZ1 = Float64List(profile.formants.length),
      _bandZ2 = Float64List(profile.formants.length),
      _bandGain = Float64List(profile.formants.length),
      _firing = Float64List(profile.cylinders),
      _strength = Float64List(profile.cylinders) {
    _combLen = _comb.length - 1;
    for (var i = 0; i < profile.formants.length; i++) {
      final f = profile.formants[i];
      final w = 2 * math.pi * f.hz / sampleRate;
      final alpha = math.sin(w) / (2 * f.q);
      final a0 = 1 + alpha;
      _bandB0[i] = alpha / a0;
      _bandA1[i] = -2 * math.cos(w) / a0;
      _bandA2[i] = (1 - alpha) / a0;
      _bandGain[i] = f.gain;
    }
    for (var k = 0; k < profile.cylinders; k++) {
      _firing[k] = k / profile.cylinders;
      _strength[k] = profile.cylinderGains.isEmpty
          ? 1
          : profile.cylinderGains[k % profile.cylinderGains.length];
    }
    _pulseCoefficient =
        1 - math.exp(-1 / (math.max(profile.pulseSeconds, 1e-5) * sampleRate));
    // An impulse through two such poles peaks at c / e: this makes the pulse peak at
    // about 1, whatever its length, so that what is added to it (the intake, the
    // tick) is in proportion to it.
    _pulseGain = math.e / _pulseCoefficient;
    _calibrate();
  }

  final EngineProfile profile;
  final int sampleRate;
  final int seed;

  /// How often the controls are stepped, in samples: a millisecond.
  static const int _block = 32;

  /// How fast the revs can rise and fall, in rpm a second.
  static const double _riseRate = 9000;
  static const double _fallRate = 6000;

  /// The level a reference load is set to, as an rms.
  static const double referenceRms = 0.14;

  /// The unevenness every engine has at any revs, 0 to 1 of a profile's lope scale.
  static const double baselineLope = 0.03;

  /// The speed of sound in hot exhaust gas, m/s.
  static const double _gasSpeed = 450;

  static int _combLength(EngineProfile p, int rate) =>
      math.max(8, (2 * p.pipeMetres / _gasSpeed * rate).round());

  // ---- Controls ----
  double _targetRpm = 0;
  double _targetLoad = 0;
  double _targetGain = 0;
  double _rpm = 0;
  double _load = 0;
  double _gain = 0;
  double _norm = 1;

  /// True while the level is being measured: the extras that come and go (the
  /// turbo's whistle, the pops) are left out, so that they do not set it.
  bool _calibrating = false;

  // ---- Crank ----
  final Float64List _firing;
  final Float64List _strength;
  // The crank in cycles (two turns each), counted from [_base]: a cylinder's firing
  // is at [_base] plus its place in the cycle.
  double _cycles = 0;
  double _nextFire = 0;
  double _base = 0;
  int _cylinder = 0;
  double _perSample = 0;
  double _fireAmp = 0;
  double _lopeAmount = 0;

  // ---- The exhaust ----
  late final double _pulseCoefficient;
  late final double _pulseGain;
  double _p1 = 0, _p2 = 0;
  final Float64List _comb;
  late final int _combLen;
  int _combPos = 0;
  double _combLow = 0;
  final Float64List _bandB0, _bandA1, _bandA2, _bandZ1, _bandZ2, _bandGain;
  double _bright = 0;
  double _brightCoefficient = 0.3;
  double _carry = 0;

  // ---- What rides on top ----
  double _intakeState = 0;
  double _intakeAmount = 0;
  double _tick = 0;
  double _loadPeak = 0;
  double _bov = 0;
  double _bovState = 0;
  double _pop = 0;
  double _popState = 0;
  double _turboPhase = 0;
  double _whinePhase = 0;
  double _humPhase = 0;

  // ---- Out ----
  double _dcIn = 0, _dcOut = 0;
  int _rng = 1;
  int _sub = 0;

  /// The revs the sound is at now (they glide to the target).
  double get rpm => _rpm;

  double get load => _load;

  /// 0 when silent, 1 when sounding.
  double get gain => _gain;

  /// Where the sound is heading: the revs, the load (0 to 1) and whether it is to
  /// sound at all. It gets there smoothly: call it as often as the readings come.
  /// A non-finite number is ignored.
  void setTargets({
    required double rpm,
    required double load,
    bool active = true,
  }) {
    if (rpm.isFinite) {
      _targetRpm = rpm.clamp(0.0, profile.redlineRpm * 1.25).toDouble();
    }
    if (load.isFinite) _targetLoad = load.clamp(0.0, 1.0).toDouble();
    _targetGain = active ? 1 : 0;
  }

  /// Puts the sound at its target at once, silent or not: for a fresh start.
  void settle() {
    _rpm = _targetRpm;
    _load = _targetLoad;
    _gain = _targetGain;
  }

  /// Everything back as it was when it was made (the level stays).
  void reset() {
    _targetRpm = _targetLoad = _targetGain = 0;
    _rpm = _load = _gain = 0;
    _cycles = 0;
    _base = 0;
    _cylinder = 0;
    _nextFire = _firing[0];
    _perSample = 0;
    _fireAmp = 0;
    _lopeAmount = 0;
    _p1 = _p2 = 0;
    _comb.fillRange(0, _comb.length, 0);
    _combPos = 0;
    _combLow = 0;
    _bandZ1.fillRange(0, _bandZ1.length, 0);
    _bandZ2.fillRange(0, _bandZ2.length, 0);
    _bright = 0;
    _carry = 0;
    _intakeState = _tick = _loadPeak = _bov = _bovState = _pop = _popState = 0;
    _turboPhase = _whinePhase = _humPhase = 0;
    _dcIn = _dcOut = 0;
    _rng = seed == 0 ? 1 : seed;
    _sub = 0;
  }

  void _calibrate() {
    _norm = 1;
    _calibrating = true;
    reset();
    setTargets(rpm: 3000, load: 0.6);
    settle();
    final scratch = Float64List(2048);
    // Half a second to get going, then the level of the next half second.
    for (var i = 0; i < sampleRate ~/ 2; i += scratch.length) {
      renderFloat(scratch, math.min(scratch.length, sampleRate ~/ 2 - i));
    }
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i < sampleRate ~/ 2; i += scratch.length) {
      final count = math.min(scratch.length, sampleRate ~/ 2 - i);
      renderFloat(scratch, count);
      for (var j = 0; j < count; j++) {
        sum += scratch[j] * scratch[j];
      }
      n += count;
    }
    final rms = math.sqrt(sum / math.max(1, n));
    _norm = rms > 1e-9 ? referenceRms / rms : 1;
    _calibrating = false;
    reset();
  }

  double _random() {
    // xorshift32: a deterministic white noise in [-1, 1).
    var x = _rng;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _rng = x & 0xFFFFFFFF;
    return _rng / 2147483648 - 1;
  }

  /// Renders [count] samples into [out] as floating point, nominally -1 to 1.
  void renderFloat(Float64List out, int count) {
    for (var n = 0; n < count; n++) {
      if (_sub == 0) _step();
      _sub = (_sub + 1) % _block;
      out[n] = profile.isElectric ? _electricSample() : _combustionSample();
    }
  }

  /// Renders [count] samples into [out] as 16-bit PCM, in pieces of a block.
  void renderPcm16(Int16List out, int count, {Float64List? scratch}) {
    final buffer = scratch ?? Float64List(1024);
    var done = 0;
    while (done < count) {
      final piece = math.min(buffer.length, count - done);
      renderFloat(buffer, piece);
      for (var i = 0; i < piece; i++) {
        final v = (buffer[i] * 32767).round();
        out[done + i] = v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
      }
      done += piece;
    }
  }

  /// The controls, a millisecond's worth at a time.
  void _step() {
    const dt = _block / 1.0;
    final seconds = dt / sampleRate;
    // The revs: a glide with a flywheel's limits on how fast they can change.
    final diff = _targetRpm - _rpm;
    var move = diff * (1 - math.exp(-seconds / 0.04));
    final rise = _riseRate * seconds;
    final fall = _fallRate * seconds;
    if (move > rise) move = rise;
    if (move < -fall) move = -fall;
    _rpm += move;
    _load += (_targetLoad - _load) * (1 - math.exp(-seconds / 0.08));
    final gainTime = _targetGain > _gain ? 0.15 : 0.35;
    _gain += (_targetGain - _gain) * (1 - math.exp(-seconds / gainTime));
    if (_gain < 1e-4 && _targetGain == 0) _gain = 0;

    _perSample = _rpm / 120 / sampleRate;

    final span = math.max(1.0, profile.redlineRpm - profile.idleRpm);
    final rise01 = ((_rpm - profile.idleRpm) / span).clamp(0.0, 1.0);
    // Louder with the revs and with the load, and quiet as it turns over slowly.
    final turning = _smooth(_rpm, 150, 500);
    final loadGain = 0.42 + 0.58 * math.pow(_load, 0.8);
    _fireAmp = turning * (0.6 + 0.4 * rise01) * loadGain;
    // The lope fades out from the idle up to about 2500 rpm, to a little that is
    // always there: no engine fires twice exactly alike.
    _lopeAmount = profile.isElectric
        ? 0
        : baselineLope +
              profile.lope * (1 - _smooth(_rpm, profile.idleRpm, 2500));

    final open = 0.55 + 0.45 * _load;
    final fc = math.min(profile.brightnessHz * open, sampleRate * 0.45);
    _brightCoefficient = 1 - math.exp(-2 * math.pi * fc / sampleRate);

    _intakeAmount =
        profile.intake * math.pow(_load, 1.3) * (0.3 + 0.7 * rise01) * turning;

    // A turbo's hiss: the load was high and has gone.
    _loadPeak = math.max(_load, _loadPeak * math.exp(-seconds / 0.3));
    if (profile.turbo > 0 && _loadPeak > 0.55 && _load < 0.22 && _bov < 0.05) {
      _bov = 1;
      _loadPeak = 0;
    }
    // The pops of an overrun: throttle shut at speed.
    if (profile.crackle > 0 && _load < 0.1 && _rpm > 1900 && _pop < 0.05) {
      final perSecond = profile.crackle * 7 * rise01;
      if ((_random() + 1) / 2 < perSecond * seconds) {
        _pop = 0.6 + 0.4 * (_random() + 1) / 2;
      }
    }
  }

  static double _smooth(double x, double from, double to) {
    if (x <= from) return 0;
    if (x >= to) return 1;
    final t = (x - from) / (to - from);
    return t * t * (3 - 2 * t);
  }

  double _combustionSample() {
    // ---- The crank: fire the cylinders whose turn it is ----
    double x = _carry;
    _carry = 0;
    final perSample = _perSample;
    if (perSample > 0) {
      _cycles += perSample;
      while (_cycles >= _nextFire) {
        final late = math.min(1.0, (_cycles - _nextFire) / perSample);
        final unevenness = _lopeAmount == 0 ? 0.0 : _lopeAmount * _random();
        final amp =
            _pulseGain *
            _fireAmp *
            _strength[_cylinder] *
            (1 + 0.6 * unevenness);
        // The impulse, placed between two samples: [late] of a sample ago.
        x += amp * late;
        _carry += amp * (1 - late);
        _tick = 1;
        // The next cylinder, a little early or late at an idle.
        _cylinder++;
        if (_cylinder >= profile.cylinders) {
          _cylinder = 0;
          _base += 1;
          if (_base >= 64) {
            // Keep the numbers small, so that the fractions stay exact.
            _cycles -= _base;
            _nextFire -= _base;
            _base = 0;
          }
        }
        final timing = _lopeAmount == 0
            ? 0.0
            : _lopeAmount * 0.12 * _random() / profile.cylinders;
        _nextFire = _base + _firing[_cylinder] + timing;
      }
    }

    // ---- The pulse, the pipe and the body ----
    _p1 += _pulseCoefficient * (x - _p1);
    _p2 += _pulseCoefficient * (_p1 - _p2);
    final pipeOut = _comb[_combPos];
    _combLow += (pipeOut - _combLow) * (1 - profile.pipeDamping);
    final y = _p2 + profile.pipeFeedback * _combLow;
    _comb[_combPos] = y;
    _combPos = _combPos + 1 >= _combLen ? 0 : _combPos + 1;
    var v = y;
    for (var i = 0; i < _bandB0.length; i++) {
      final out = _bandB0[i] * y + _bandZ1[i];
      _bandZ1[i] = -_bandA1[i] * out + _bandZ2[i];
      _bandZ2[i] = -_bandB0[i] * y - _bandA2[i] * out;
      v += _bandGain[i] * out;
    }
    _bright += _brightCoefficient * (v - _bright);
    var s = _bright;

    // ---- What rides on top ----
    final white = _random();
    if (_intakeAmount > 0) {
      _intakeState += 0.25 * (white - _intakeState);
      s += _intakeState * _intakeAmount * 0.9;
    }
    if (_tick > 1e-4) {
      s += _random() * _tick * profile.valvetrain * 0.25 * _fireAmp;
      _tick *= 0.93;
    }
    if (profile.turbo > 0 && !_calibrating) {
      final spool = _smooth(_rpm, 1700, 3600) * math.pow(_load, 1.5);
      if (spool > 0.001) {
        _turboPhase += (650 + _rpm * 0.42) / sampleRate;
        _turboPhase -= _turboPhase.floorToDouble();
        s += math.sin(2 * math.pi * _turboPhase) * spool * profile.turbo * 0.11;
      }
      if (_bov > 1e-4) {
        _bovState += 0.45 * (white - _bovState);
        s += (white - _bovState) * _bov * profile.turbo * 0.16;
        _bov *= 0.99985;
      }
    }
    if (_pop > 1e-4 && !_calibrating) {
      _popState += 0.2 * (white - _popState);
      s += _popState * _pop * 1.3;
      _pop *= 0.996;
    }
    return _finish(s);
  }

  double _electricSample() {
    final turning = _smooth(_rpm, 30, 300);
    final f = profile.whineHz + _rpm * profile.whinePerRpm;
    _whinePhase += f / sampleRate;
    _whinePhase -= _whinePhase.floorToDouble();
    _humPhase += f * 0.25 / sampleRate;
    _humPhase -= _humPhase.floorToDouble();
    final loadGain = 0.25 + 0.75 * math.pow(_load, 0.8);
    final rise01 = (_rpm / profile.redlineRpm).clamp(0.0, 1.0);
    final a = turning * loadGain * (0.35 + 0.65 * rise01) * profile.whineGain;
    final p = 2 * math.pi * _whinePhase;
    var s =
        a *
        (math.sin(p) + 0.45 * math.sin(2 * p + 0.6) + 0.22 * math.sin(3 * p));
    s += a * 0.5 * math.sin(2 * math.pi * _humPhase);
    _intakeState += 0.12 * (_random() - _intakeState);
    s += _intakeState * _intakeAmount * 2.5 * turning;
    return _finish(s * 0.4);
  }

  /// The level, the fades, the DC blocker and a soft clip.
  double _finish(double s) {
    final level = s * _norm * _gain;
    // Removes what is below about 25 Hz, which a speaker cannot give anyway and
    // which would only eat the headroom.
    final hp = level - _dcIn + 0.995 * _dcOut;
    _dcIn = level;
    _dcOut = hp;
    // A soft clip: a cubic that reaches 1 flat.
    final c = hp > 1 ? 1.0 : (hp < -1 ? -1.0 : hp);
    return c * (1.5 - 0.5 * c * c);
  }
}
