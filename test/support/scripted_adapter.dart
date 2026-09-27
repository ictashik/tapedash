import 'package:tapedash/core/fake_clock.dart';

import 'fake_transport.dart';

/// What a [ScriptedAdapter] says to one command: [text] arrives [afterMs] after
/// the command was written.
class Say {
  const Say(this.text, {this.afterMs = 10, this.then = const []});

  /// The whole text, echo and prompt included.
  final String text;
  final int afterMs;

  /// More pieces for the same command, each [afterMs] after the command was
  /// written: a late reply to something else, followed by the real one.
  final List<Say> then;

  /// The usual reply to a command that works: [body], and the prompt.
  factory Say.ok(String body, {int afterMs = 10}) =>
      Say('$body\r\r>', afterMs: afterMs);

  /// No reply at all: the command is lost.
  static const Say? silence = null;
}

/// An adapter that answers a test's commands from a script, so that what the
/// ELM327 layer does with each answer can be tried one at a time, without a
/// simulated car.
///
/// [script] has, for each command as written (without its carriage return), the
/// replies to give, in order. When they run out, the last one repeats. A
/// command with no entry gets `?`.
class ScriptedAdapter {
  ScriptedAdapter(this.transport, this.clock, Map<String, List<Say?>> script)
    : _script = {for (final e in script.entries) e.key: List.of(e.value)} {
    transport.onCommand = _onCommand;
  }

  final FakeTransport transport;
  final FakeClock clock;
  final Map<String, List<Say?>> _script;

  /// Every command received.
  final List<String> commands = [];

  void _onCommand(String command) {
    commands.add(command);
    final replies = _script[command];
    Say? say = const Say('?\r\r>');
    if (replies != null && replies.isNotEmpty) {
      say = replies.length > 1 ? replies.removeAt(0) : replies.first;
    }
    if (say == null) return;
    for (final piece in [say, ...say.then]) {
      final text = piece.text;
      clock.runAfter(
        Duration(milliseconds: piece.afterMs),
        () => transport.receive(text),
      );
    }
  }
}
