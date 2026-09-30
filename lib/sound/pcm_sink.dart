import 'dart:typed_data';

import '../core/clock.dart';

/// Whether an output came up.
enum SinkStart {
  started,

  /// It would have played on the phone's own speaker: there is no car audio
  /// (Bluetooth, USB or a wire) to play on, and the caller asked for one.
  noExternalOutput,

  failed,
}

/// Somewhere 16-bit mono PCM goes to be played: the phone's audio output
/// (`AudioTrackSink`), or memory, for tests and for the tools.
///
/// Writing never waits. The sink tells how much it is holding that has not played
/// yet, and the caller keeps that a little ahead of the playing.
abstract interface class PcmSink {
  /// Opens the output at [sampleRate]. With [requireExternalOutput] it does not
  /// open if the only output is the phone's speaker.
  Future<SinkStart> start(int sampleRate, {bool requireExternalOutput = false});

  /// Hands over the first [frames] samples of [pcm]. The sink copies them: the
  /// caller may reuse [pcm] at once.
  void write(Int16List pcm, int frames);

  /// The samples handed over and not yet played, as far as is known: it falls as
  /// they play.
  int get queuedFrames;

  /// True once the output has been taken away (a Bluetooth link dropped, the app
  /// left the screen): nothing more will play, and the caller should stop.
  bool get isLost;

  /// How many times the output ran dry when it should have had sound.
  int get underruns;

  Future<void> stop();
}

/// A [PcmSink] in memory, playing at the pace of a [Clock]: what has been written
/// is consumed at [sampleRate] samples a second. For tests, and for writing a
/// file.
class MemorySink implements PcmSink {
  MemorySink(this._clock, {this.playable = true});

  final Clock _clock;

  /// What [start] answers: false is a phone with no car audio.
  bool playable;

  int _rate = 32000;
  Duration _startedAt = Duration.zero;
  Duration _last = Duration.zero;
  double _queued = 0;
  bool _open = false;
  bool _lost = false;
  int _underruns = 0;
  bool _wasRunning = false;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _frames = 0;

  /// Whether [requireExternalOutput] was asked for on the last start.
  bool requiredExternal = false;

  /// Everything written, in order.
  Int16List get samples {
    final b = _bytes.toBytes();
    return b.buffer.asInt16List(b.offsetInBytes, b.lengthInBytes ~/ 2);
  }

  int get framesWritten => _frames;
  bool get isOpen => _open;

  /// Takes the output away, as a Bluetooth link dropping would.
  void lose() => _lost = true;

  void _advance() {
    final now = _clock.monotonic();
    final played = (now - _last).inMicroseconds / 1e6 * _rate;
    _last = now;
    if (!_open) return;
    if (_queued > 0) _wasRunning = true;
    _queued -= played;
    if (_queued < 0) {
      // It ran dry, having had sound to play.
      if (_wasRunning) {
        _underruns++;
        _wasRunning = false;
      }
      _queued = 0;
    }
  }

  @override
  Future<SinkStart> start(
    int sampleRate, {
    bool requireExternalOutput = false,
  }) async {
    requiredExternal = requireExternalOutput;
    if (!playable && requireExternalOutput) return SinkStart.noExternalOutput;
    _rate = sampleRate;
    _startedAt = _last = _clock.monotonic();
    _open = true;
    _lost = false;
    _queued = 0;
    return SinkStart.started;
  }

  @override
  void write(Int16List pcm, int frames) {
    _advance();
    _queued += frames;
    _frames += frames;
    _bytes.add(
      Uint8List.fromList(pcm.buffer.asUint8List(pcm.offsetInBytes, frames * 2)),
    );
  }

  @override
  int get queuedFrames {
    _advance();
    return _queued.round();
  }

  @override
  bool get isLost => _lost;

  @override
  int get underruns {
    _advance();
    return _underruns;
  }

  /// How long since it was opened.
  Duration get open => _clock.monotonic() - _startedAt;

  @override
  Future<void> stop() async {
    _open = false;
  }
}
