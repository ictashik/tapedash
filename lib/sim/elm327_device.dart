import '../core/scheduler.dart';
import 'adapter_quirks.dart';
import 'elm327_simulator.dart';
import 'sim_random.dart';

/// An [Elm327Simulator] with a serial line: bytes go in, and the adapter's
/// answers come out on a [Scheduler], as they would from a real adapter across
/// a Bluetooth or WiFi link.
///
/// It puts the pieces together that the simulator leaves to its carrier. It
/// puts characters back into lines, and does one command at a time. It adds the
/// link's round trip, so the car is asked in the middle of it, and the app
/// timestamps the answer at the middle of it too. And it loses the first
/// command after the link opens, if the quirks say the clone does.
class Elm327Device {
  Elm327Device({
    required this.simulator,
    required this.scheduler,
    required this.onOutput,
    int seed = 1,
  }) : _random = SimRandom(seed).fork(4),
       _dropNext = simulator.quirks.dropFirstCommand;

  final Elm327Simulator simulator;
  final Scheduler scheduler;

  /// Called with each piece of the adapter's output when it goes out.
  final void Function(String text) onOutput;

  final SimRandom _random;

  AdapterQuirks get quirks => simulator.quirks;

  final List<String> _queue = [];
  final Set<ScheduledTask> _tasks = {};
  String _partial = '';
  bool _busy = false;
  bool _dropNext;
  int _overlapped = 0;

  /// How many commands arrived while another was still being answered. A
  /// well-behaved app waits for the prompt, so this stays at zero; a test can
  /// check that it does.
  int get overlappedCommands => _overlapped;

  /// Whether a command is being answered.
  bool get isBusy => _busy;

  /// A new link has been opened, so a clone that loses the first command
  /// will lose the next one.
  void linkOpened() {
    _dropNext = quirks.dropFirstCommand;
  }

  /// The link has gone. What was on its way, and what was waiting, is lost.
  void linkClosed() {
    for (final task in _tasks.toList()) {
      task.cancel();
    }
    _tasks.clear();
    _queue.clear();
    _partial = '';
    _busy = false;
  }

  /// Characters from the app. A command ends with a carriage return; a line
  /// feed is ignored, as the adapter ignores it.
  void receive(String data) {
    for (final unit in data.codeUnits) {
      if (unit == 0x0D) {
        if (_busy || _queue.isNotEmpty) _overlapped++;
        _queue.add(_partial);
        _partial = '';
      } else if (unit != 0x0A) {
        _partial += String.fromCharCode(unit);
      }
    }
    _pump();
  }

  void _pump() {
    if (_busy || _queue.isEmpty) return;
    final line = _queue.removeAt(0);

    if (_dropNext) {
      // Lost on the way. Nothing comes back, not even the echo.
      _dropNext = false;
      _pump();
      return;
    }

    _busy = true;
    final roundTrip = _roundTrip();
    final there = roundTrip ~/ 2;
    final back = roundTrip - there;
    // The car is asked when the command gets to the adapter, half way through.
    _later(there, () {
      final reply = simulator.execute(line);
      final chunks = reply.chunks;
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final last = i == chunks.length - 1;
        _later(back + chunk.after, () {
          // Free again before the last of it goes out, so that a command
          // written in reply is not counted as an overlap.
          if (last) _busy = false;
          onOutput(chunk.text);
          if (last) _pump();
        });
      }
      if (chunks.isEmpty) {
        _busy = false;
        _pump();
      }
    });
  }

  /// The link's round trip for one command: the fixed part, and a random part
  /// of up to the jitter either way.
  Duration _roundTrip() {
    final micros =
        quirks.latency.inMicroseconds +
        (quirks.jitter.inMicroseconds == 0
            ? 0
            : quirks.jitter.inMicroseconds * _random.uniform(-1, 1));
    return Duration(microseconds: micros < 0 ? 0 : micros.round());
  }

  void _later(Duration delay, void Function() task) {
    late final ScheduledTask handle;
    handle = scheduler.runAfter(delay, () {
      _tasks.remove(handle);
      task();
    });
    _tasks.add(handle);
  }
}
