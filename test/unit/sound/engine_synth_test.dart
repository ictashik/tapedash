// The engine's sound (lib/sound/engine_synth.dart): that it is at the pitch the
// revs say, follows the revs and the load, is silent when off, never clicks or
// clips, and is the same every time. Whether it sounds like an engine is for an
// ear; these are what can be checked without one.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/engine_synth.dart';

const _rate = 32000;

/// [seconds] of [synth] at steady [rpm] and [load], after letting it settle.
Float64List steady(
  EngineSynth synth,
  double rpm,
  double load, {
  double seconds = 1,
}) {
  synth.setTargets(rpm: rpm, load: load);
  synth.settle();
  final warm = Float64List(_rate ~/ 4);
  synth.renderFloat(warm, warm.length);
  final out = Float64List((seconds * _rate).round());
  synth.renderFloat(out, out.length);
  return out;
}

/// The strength of [hz] in [x] (a Goertzel filter over all of it).
double strength(Float64List x, double hz) {
  final w = 2 * math.pi * hz / _rate;
  final c = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (final v in x) {
    final s0 = v + c * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final power = s1 * s1 + s2 * s2 - c * s1 * s2;
  return math.sqrt(math.max(0, power)) / x.length * 2;
}

/// The frequency in [from], [to] with the most strength.
double peak(Float64List x, double from, double to, {double step = 0.1}) {
  var best = from;
  var bestStrength = -1.0;
  for (var f = from; f <= to; f += step) {
    final s = strength(x, f);
    if (s > bestStrength) {
      bestStrength = s;
      best = f;
    }
  }
  return best;
}

double rms(Float64List x) {
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

void main() {
  group('the pitch is the firing\'s', () {
    test(
      'a four at 3000 rpm fires 100 times a second: 100 Hz and its harmonics',
      () {
        final x = steady(
          EngineSynth(EngineProfile.inline4),
          3000,
          0.6,
          seconds: 2,
        );

        final fundamental = strength(x, 100);
        expect(fundamental, greaterThan(strength(x, 150) * 6));
        expect(fundamental, greaterThan(strength(x, 125) * 6));
        expect(strength(x, 200), greaterThan(strength(x, 175) * 6));
        expect(peak(x, 40, 160), closeTo(100, 0.5));
      },
    );

    test('it follows the revs: half the revs, half the pitch', () {
      final synth = EngineSynth(EngineProfile.inline4);

      expect(
        peak(steady(synth, 1500, 0.6, seconds: 2), 30, 80),
        closeTo(50, 0.5),
      );
      expect(
        peak(steady(synth, 6000, 0.6, seconds: 2), 150, 250),
        closeTo(200, 1),
      );
    });

    test('it is exact to a fraction of a sample: 3010 rpm is 100.33 Hz', () {
      final x = steady(
        EngineSynth(EngineProfile.inline4),
        3010,
        0.6,
        seconds: 3,
      );

      expect(peak(x, 98, 103, step: 0.05), closeTo(100.33, 0.2));
    });

    test(
      'more cylinders, more often: a V8 at 1500 rpm fires at 100 Hz too',
      () {
        final x = steady(EngineSynth(EngineProfile.v8), 1500, 0.6, seconds: 2);

        expect(peak(x, 60, 160), closeTo(100, 1));
      },
    );

    test('three and six cylinders', () {
      final three = steady(
        EngineSynth(EngineProfile.inline3),
        2400,
        0.6,
        seconds: 2,
      );
      final six = steady(EngineSynth(EngineProfile.v6), 2000, 0.6, seconds: 2);

      expect(peak(three, 40, 90), closeTo(60, 0.6), reason: '2400 / 120 * 3');
      expect(peak(six, 70, 130), closeTo(100, 1), reason: '2000 / 120 * 6');
    });
  });

  group('the load and the level', () {
    test('it is louder with the throttle open', () {
      final synth = EngineSynth(EngineProfile.inline4);
      final shut = rms(steady(synth, 3000, 0.05));
      final open = rms(steady(synth, 3000, 0.9));

      expect(open, greaterThan(shut * 2));
    });

    test('it is louder at high revs than at an idle', () {
      final synth = EngineSynth(EngineProfile.inline4);

      expect(
        rms(steady(synth, 5500, 0.5)),
        greaterThan(rms(steady(synth, 800, 0.5)) * 1.5),
      );
    });

    test(
      'every engine is the same level at the reference: they swap at one volume',
      () {
        for (final profile in EngineProfile.all) {
          final level = rms(steady(EngineSynth(profile), 3000, 0.6));

          expect(
            level,
            inInclusiveRange(
              EngineSynth.referenceRms * 0.75,
              EngineSynth.referenceRms * 1.3,
            ),
            reason: profile.id,
          );
        }
      },
    );

    test('it never clips, at the hardest it is asked for', () {
      for (final profile in EngineProfile.all) {
        final x = steady(EngineSynth(profile), profile.redlineRpm * 1.25, 1);
        final top = x.map((v) => v.abs()).reduce(math.max);

        expect(top, lessThanOrEqualTo(1.0), reason: profile.id);
        expect(top, greaterThan(0.05), reason: profile.id);
      }
    });
  });

  group('off, on and in between', () {
    test('inactive, it is silent', () {
      final synth = EngineSynth(EngineProfile.inline4);
      steady(synth, 3000, 0.6);

      synth.setTargets(rpm: 3000, load: 0.6, active: false);
      final out = Float64List(_rate * 4);
      synth.renderFloat(out, out.length);
      final tail = Float64List.sublistView(out, _rate * 3);

      expect(rms(tail), lessThan(1e-4));
      expect(synth.gain, 0);
    });

    test('it comes in over a moment, not with a click', () {
      final synth = EngineSynth(EngineProfile.v8);
      synth.setTargets(rpm: 3000, load: 0.6);
      final out = Float64List(_rate);
      synth.renderFloat(out, out.length);

      expect(
        out.sublist(0, 200).map((v) => v.abs()).reduce(math.max),
        lessThan(0.05),
      );
      expect(rms(Float64List.sublistView(out, _rate ~/ 2)), greaterThan(0.05));
    });

    test('no revs is silence, not a drone', () {
      final synth = EngineSynth(EngineProfile.inline4);
      final x = steady(synth, 0, 0, seconds: 1);

      expect(rms(x), lessThan(1e-3));
    });

    test(
      'the revs glide: they rise at most 9000 a second and fall at most 6000',
      () {
        final synth = EngineSynth(EngineProfile.inline4);
        synth.setTargets(rpm: 800, load: 0.1);
        synth.settle();
        final buf = Float64List(_rate ~/ 10);
        synth.setTargets(rpm: 7000, load: 0.9);
        synth.renderFloat(buf, buf.length);

        expect(synth.rpm - 800, lessThanOrEqualTo(9000 * 0.1 + 1));
        expect(synth.rpm, greaterThan(800));

        synth.setTargets(rpm: 800, load: 0.1);
        final before = synth.rpm;
        synth.renderFloat(buf, buf.length);
        expect(before - synth.rpm, lessThanOrEqualTo(6000 * 0.1 + 1));
      },
    );

    test('a jump in the revs never makes a click', () {
      final synth = EngineSynth(EngineProfile.inline4);
      final x = <double>[];
      final buf = Float64List(800);
      var t = 0.0;
      for (final (rpm, load) in const [
        (800.0, 0.1),
        (6000.0, 0.9),
        (900.0, 0.0),
        (4000.0, 0.5),
        (4000.0, 0.5),
      ]) {
        synth.setTargets(rpm: rpm, load: load);
        for (var i = 0; i < 60; i++) {
          synth.renderFloat(buf, buf.length);
          x.addAll(buf);
          t += 800 / _rate;
        }
      }
      var worst = 0.0;
      for (var i = 1; i < x.length; i++) {
        worst = math.max(worst, (x[i] - x[i - 1]).abs());
      }

      // A pulse's edge is soft (two poles at about a millisecond): no step of a
      // sample to the next is more than a fraction of full scale.
      expect(worst, lessThan(0.35));
      expect(t, greaterThan(4));
    });

    test('non-finite controls are ignored', () {
      final synth = EngineSynth(EngineProfile.inline4);
      synth.setTargets(rpm: 2500, load: 0.4);
      synth.setTargets(rpm: double.nan, load: double.infinity);

      final x = steady(synth, 2500, 0.4);

      expect(x.every((v) => v.isFinite), isTrue);
    });
  });

  group('the same every time', () {
    test('the same profile, seed and controls give the same samples', () {
      Float64List run(int seed) {
        final s = EngineSynth(EngineProfile.v8, seed: seed);
        return steady(s, 800, 0.1, seconds: 0.5);
      }

      expect(run(1), run(1));
      expect(
        run(1),
        isNot(run(2)),
        reason: 'a different seed is a different lope',
      );
    });

    test('reset puts it back as it was made', () {
      final synth = EngineSynth(EngineProfile.v6);
      final first = steady(synth, 2500, 0.5, seconds: 0.25);

      synth.reset();
      final second = steady(synth, 2500, 0.5, seconds: 0.25);

      expect(second, first);
    });

    test('every engine stays finite over a long, rough drive', () {
      final random = math.Random(7);
      for (final profile in EngineProfile.all) {
        final synth = EngineSynth(profile);
        final buf = Float64List(640);
        for (var i = 0; i < 400; i++) {
          synth.setTargets(
            rpm: random.nextDouble() * 8000,
            load: random.nextDouble(),
            active: random.nextDouble() > 0.03,
          );
          synth.renderFloat(buf, buf.length);
          expect(
            buf.every((v) => v.isFinite && v.abs() <= 1.0),
            isTrue,
            reason: profile.id,
          );
        }
      }
    });
  });

  group('the extras', () {
    test(
      'a turbo whistles under load, at a pitch that rises with the revs',
      () {
        final turbo = EngineSynth(EngineProfile.turbo4);
        final plain = EngineSynth(EngineProfile.inline4);
        // At 4000 rpm the whistle is at 650 + 4000 * 0.42 = 2330 Hz.
        final loaded = steady(turbo, 4000, 0.9, seconds: 1);
        final light = steady(turbo, 4000, 0.05, seconds: 1);
        final without = steady(plain, 4000, 0.9, seconds: 1);

        expect(strength(loaded, 2330), greaterThan(strength(light, 2330) * 4));
        expect(
          strength(loaded, 2330),
          greaterThan(strength(without, 2330) * 3),
        );
      },
    );

    test('it hisses when the throttle is closed on load', () {
      final turbo = EngineSynth(EngineProfile.turbo4);
      steady(turbo, 4000, 0.9);

      turbo.setTargets(rpm: 3900, load: 0.0);
      final lift = Float64List(_rate ~/ 2);
      turbo.renderFloat(lift, lift.length);
      final quiet = steady(
        EngineSynth(EngineProfile.turbo4),
        3900,
        0.0,
        seconds: 0.5,
      );

      // The hiss is at the top: more of it after a lift than after steady light load.
      double high(Float64List x) => [
        for (var f = 3000.0; f < 7000; f += 400) strength(x, f),
      ].reduce((a, b) => a + b);
      expect(high(lift), greaterThan(high(quiet) * 1.3));
    });

    test('an electric motor whines: 380 Hz plus 0.55 Hz for each rpm', () {
      final x = steady(
        EngineSynth(EngineProfile.electric),
        2000,
        0.5,
        seconds: 1,
      );

      // 380 + 2000 * 0.55 = 1480 Hz.
      expect(peak(x, 1000, 2000, step: 2), closeTo(1480, 4));
    });

    test('an overrun on a V8 has pops', () {
      final synth = EngineSynth(EngineProfile.v8);
      final x = steady(synth, 3500, 0.0, seconds: 4);
      final quiet = steady(
        EngineSynth(EngineProfile.inline4),
        3500,
        0.0,
        seconds: 4,
      );

      // The pops are the peaks above the tone: the crest of the signal is higher.
      double crest(Float64List v) =>
          v.map((e) => e.abs()).reduce(math.max) / rms(v);
      expect(crest(x), greaterThan(crest(quiet)));
    });
  });

  group('the output', () {
    test('16-bit PCM is the floating-point sound times 32767', () {
      final a = EngineSynth(EngineProfile.inline4);
      final b = EngineSynth(EngineProfile.inline4);
      a.setTargets(rpm: 3000, load: 0.5);
      b.setTargets(rpm: 3000, load: 0.5);
      a.settle();
      b.settle();
      final f = Float64List(2000);
      a.renderFloat(f, f.length);
      final p = Int16List(2000);
      b.renderPcm16(p, p.length);

      for (var i = 0; i < f.length; i++) {
        expect(p[i], (f[i] * 32767).round(), reason: 'sample $i');
      }
    });

    test('ten seconds of it takes a fraction of ten seconds', () {
      final synth = EngineSynth(EngineProfile.turbo4);
      synth.setTargets(rpm: 4000, load: 0.7);
      final buf = Float64List(_rate);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        synth.renderFloat(buf, buf.length);
      }

      // Very generous: the point is that it is nowhere near real time, so that an
      // old phone, many times slower than this machine, still keeps up.
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('the profiles', () {
    test('have their own ids, and a way to be found by one', () {
      final ids = EngineProfile.all.map((p) => p.id).toList();

      expect(ids.toSet(), hasLength(ids.length));
      expect(EngineProfile.byId('v8'), EngineProfile.v8);
      expect(EngineProfile.byId('nonsense'), EngineProfile.all.first);
      expect(EngineProfile.byId(null), EngineProfile.all.first);
    });

    test('differ in how they sound, not just in name', () {
      // The share of the energy above 1 kHz, at the same revs and load.
      double bright(EngineProfile p) {
        final x = steady(EngineSynth(p), 3000, 0.6, seconds: 1);
        var high = 0.0, all = 0.0;
        for (var f = 100.0; f < 6000; f += 50) {
          final s = strength(x, f);
          all += s * s;
          if (f > 1000) high += s * s;
        }
        return high / all;
      }

      expect(
        bright(EngineProfile.flat6),
        greaterThan(bright(EngineProfile.v8) * 1.5),
      );
    });
  });
}
