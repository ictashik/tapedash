import 'dart:async';

import '../../core/clock.dart';
import '../../core/scheduler.dart';
import 'session_log.dart';
import 'transport.dart';

/// What a [ReplayTransport] does when a command has no recorded reply left.
enum ReplayEnd {
  /// Start again from the first recorded reply for that command.
  loop,

  /// Say `?`, as an adapter does to what it does not understand.
  unknown,
}

/// A [Transport] that plays back a recorded session (CLAUDE.md 10, Recordings).
///
/// It does not replay by the clock. It answers each command with the next
/// recorded reply to the same command, in the order they were recorded, and
/// delivers the pieces of that reply at the offsets they had. So a recording
/// made by one client, at one pace, can be played into another that sends the
/// same commands in a different order or at a different time; what it cannot
/// answer is a command that was never sent in the recording, and that gets `?`.
///
/// A command that got no reply in the recording, such as the first one to a
/// clone that loses it, gets none in the replay either, so a recording keeps
/// the misbehaviour of the adapter it came from.
///
/// With [followLinkEvents], a link that dropped in the recording drops again at
/// the same time from the first connection, and connecting fails for as long as
/// it did.
class ReplayTransport implements Transport {
  ReplayTransport({
    required SessionLog log,
    required this.scheduler,
    required this.clock,
    this.connectDelay = const Duration(milliseconds: 400),
    this.end = ReplayEnd.loop,
    this.followLinkEvents = false,
  }) {
    _load(log);
  }

  final Scheduler scheduler;
  final Clock clock;

  /// How long connecting takes, when it works.
  final Duration connectDelay;

  final ReplayEnd end;
  final bool followLinkEvents;

  final Map<String, List<_Exchange>> _exchanges = {};
  final Map<String, int> _cursors = {};

  /// When the link dropped in the recording, from its first connection.
  final List<Duration> _drops = [];

  /// The spans, from the first connection, in which connecting failed.
  final List<(Duration, Duration)> _outages = [];

  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);

  TransportState _current = const TransportState.disconnected();
  final Set<ScheduledTask> _tasks = {};
  Duration? _firstConnectedAt;

  /// The commands that had no recorded reply and were answered `?`, in order.
  final List<String> unmatched = [];

  /// How many commands had no recorded reply and were answered `?`.
  int get unmatchedCommands => unmatched.length;

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  /// The command as a key: no spaces, upper case.
  static String _key(String command) =>
      command.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  void _load(SessionLog log) {
    _Exchange? current;
    Duration? firstConnected;
    Duration? lostAt;
    for (final entry in log.entries) {
      switch (entry.direction) {
        case SessionDirection.sent:
          final command = entry.text.replaceAll(RegExp(r'[\r\n]+$'), '');
          current = _Exchange(entry.at);
          _exchanges.putIfAbsent(_key(command), () => []).add(current);
        case SessionDirection.received:
          current?.chunks.add((entry.at - current.at, entry.text));
        case SessionDirection.note:
          // The app talking to itself: not part of the conversation.
          break;
        case SessionDirection.event:
          current = null;
          final text = entry.text;
          if (text == 'connected') {
            firstConnected ??= entry.at;
            if (lostAt != null) {
              _outages.add((
                lostAt - firstConnected,
                entry.at - firstConnected,
              ));
              lostAt = null;
            }
          } else if (text.startsWith('disconnected') &&
              text.contains('lost') &&
              firstConnected != null) {
            lostAt = entry.at;
            _drops.add(entry.at - firstConnected);
          }
      }
    }
  }

  @override
  Future<void> connect() {
    if (_current.isConnected) return Future<void>.value();
    final completer = Completer<void>();
    _set(TransportState.connecting);
    _later(connectDelay, () {
      if (_inOutage()) {
        _set(
          const TransportState.disconnected(
            failure: TransportFailure.unreachable,
          ),
        );
        completer.completeError(
          const TransportException(TransportFailure.unreachable),
        );
        return;
      }
      _set(TransportState.connected);
      _startLinkClock();
      completer.complete();
    });
    return completer.future;
  }

  /// At the first connection, schedules the drops the recording had.
  void _startLinkClock() {
    if (_firstConnectedAt != null || !followLinkEvents) return;
    _firstConnectedAt = clock.monotonic();
    for (final drop in _drops) {
      _later(drop, () {
        if (_current.isConnected) {
          _set(
            const TransportState.disconnected(failure: TransportFailure.lost),
          );
        }
      });
    }
  }

  bool _inOutage() {
    final first = _firstConnectedAt;
    if (!followLinkEvents || first == null) return false;
    final since = clock.monotonic() - first;
    for (final (from, to) in _outages) {
      if (since >= from && since < to) return true;
    }
    return false;
  }

  void _set(TransportState next) {
    if (next == _current) return;
    _current = next;
    if (!_states.isClosed) _states.add(next);
  }

  @override
  Future<void> disconnect() {
    for (final task in _tasks.toList()) {
      task.cancel();
    }
    _tasks.clear();
    // The drops scheduled at the first connection go with the tasks: a link
    // that was closed on purpose is not the recording's link.
    _set(const TransportState.disconnected());
    return Future<void>.value();
  }

  @override
  Future<void> write(String data) {
    if (!_current.isConnected) {
      return Future<void>.error(
        const TransportException(TransportFailure.notConnected),
      );
    }
    for (final command in data.split('\r').where((c) => c.isNotEmpty)) {
      _answer(command);
    }
    return Future<void>.value();
  }

  void _answer(String command) {
    final key = _key(command);
    final list = _exchanges[key];
    _Exchange? exchange;
    if (list != null && list.isNotEmpty) {
      final cursor = _cursors[key] ?? 0;
      if (cursor < list.length) {
        exchange = list[cursor];
        _cursors[key] = cursor + 1;
      } else if (end == ReplayEnd.loop) {
        exchange = list.first;
        _cursors[key] = 1;
      }
    }
    if (exchange == null) {
      unmatched.add(command);
      _deliver(const Duration(milliseconds: 5), '?\r\r>');
      return;
    }
    for (final (offset, text) in exchange.chunks) {
      _deliver(offset, text);
    }
  }

  void _deliver(Duration after, String text) {
    _later(after, () {
      if (_current.isConnected && !_incoming.isClosed) _incoming.add(text);
    });
  }

  void _later(Duration delay, void Function() task) {
    late final ScheduledTask handle;
    handle = scheduler.runAfter(delay, () {
      _tasks.remove(handle);
      task();
    });
    _tasks.add(handle);
  }

  /// Stops everything and closes the streams.
  Future<void> dispose() async {
    await disconnect();
    await _incoming.close();
    await _states.close();
  }
}

/// One command of the recording and the pieces that came back for it.
class _Exchange {
  _Exchange(this.at);

  /// When it was sent, in the recording.
  final Duration at;

  /// Each piece of the reply, with its offset from the command.
  final List<(Duration, String)> chunks = [];
}
