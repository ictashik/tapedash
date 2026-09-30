// Renders what the engine sounds are, to WAV files, so that a profile can be
// listened to at a desk before it is heard in a car (and looked at, as a
// spectrogram, by whoever cannot listen).
//
//   dart run tool/render_engine.dart [--out DIR] [--profile ID|all] [--scene NAME|all]
//
// Scenes: idle, sweep (idle, up to the limit on full throttle, lift, back down),
// drive (pulls and lifts with the revs dropping on each shift).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/engine_synth.dart';

/// One scene: (seconds, rpm, load) waypoints, joined by straight lines.
const Map<String, List<(double, double, double)>> scenes = {
  'idle': [(0, 800, 0.12), (6, 800, 0.12)],
  'sweep': [
    (0, 800, 0.12),
    (2, 800, 0.12),
    (8, 6200, 0.9),
    (9, 6200, 0.9),
    (10, 6000, 0.0),
    (14, 1500, 0.0),
    (16, 800, 0.12),
    (18, 800, 0.12),
  ],
  'drive': [
    (0, 800, 0.12),
    (1, 800, 0.12),
    (4, 3200, 0.7), // a pull in first
    (4.4, 2100, 0.1), // the shift
    (7, 3600, 0.7), // and in second
    (7.4, 2400, 0.1),
    (10, 3000, 0.45), // third, settling
    (13, 2600, 0.2), // a cruise
    (15, 1800, 0.0), // a lift
    (18, 900, 0.1), // a stop
    (20, 800, 0.12),
  ],
};

void main(List<String> args) {
  String option(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final out = Directory(option('--out', 'build/engine'))
    ..createSync(recursive: true);
  final profileId = option('--profile', 'all');
  final sceneName = option('--scene', 'all');
  final profiles = profileId == 'all'
      ? EngineProfile.all
      : [EngineProfile.byId(profileId)];
  final names = sceneName == 'all' ? scenes.keys.toList() : [sceneName];

  for (final profile in profiles) {
    for (final name in names) {
      final scene = scenes[name];
      if (scene == null) {
        stderr.writeln('No scene "$name" (${scenes.keys.join(', ')})');
        exit(64);
      }
      final pcm = render(profile, scene);
      final file = File('${out.path}/${profile.id}-$name.wav')
        ..writeAsBytesSync(wav(pcm, 32000));
      stdout.writeln(
        '${file.path}  ${(pcm.length / 32000).toStringAsFixed(1)} s',
      );
    }
  }
}

/// The scene's sound: the controls are set every 20 ms from the waypoints, as a
/// drive would set them.
Int16List render(EngineProfile profile, List<(double, double, double)> scene) {
  const rate = 32000;
  final synth = EngineSynth(profile, sampleRate: rate);
  final total = scene.last.$1;
  final pcm = Int16List((total * rate).round());
  final scratch = Float64List(1024);
  const step = rate ~/ 50;
  var segment = 0;
  for (var at = 0; at < pcm.length; at += step) {
    final t = at / rate;
    while (segment < scene.length - 2 && scene[segment + 1].$1 <= t) {
      segment++;
    }
    final a = scene[segment];
    final b = scene[segment + 1];
    final f = b.$1 == a.$1 ? 1.0 : ((t - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
    synth.setTargets(
      rpm: a.$2 + (b.$2 - a.$2) * f,
      load: a.$3 + (b.$3 - a.$3) * f,
    );
    final n = math.min(step, pcm.length - at);
    final block = Int16List(n);
    synth.renderPcm16(block, n, scratch: scratch);
    pcm.setRange(at, at + n, block);
  }
  return pcm;
}

/// A mono 16-bit PCM WAV file.
Uint8List wav(Int16List pcm, int rate) {
  final bytes = ByteData(44 + pcm.length * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + pcm.length * 2, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, pcm.length * 2, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    bytes.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}
