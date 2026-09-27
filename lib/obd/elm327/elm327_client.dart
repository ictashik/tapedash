import 'dart:async';
import 'dart:collection';

import '../../core/clock.dart';
import '../../core/scheduler.dart';
import '../transport/transport.dart';
import 'elm327_failure.dart';
import 'elm327_parser.dart';

/// How long the client waits, and how it paces itself.
class Elm327Timing {
  const Elm327Timing({
    this.commandTimeout = const Duration(seconds: 2),
    this.requestTimeout = const Duration(milliseconds: 1500),
    this.resetTimeout = const Duration(seconds: 4),
    this.searchTimeout = const Duration(seconds: 12),
    this.minGap = Duration.zero,
    this.promptGrace = const Duration(milliseconds: 250),
    this.settleAfterTimeout = const Duration(milliseconds: 100),
  });

  /// For an AT command.
  final Duration commandTimeout;

  /// For an OBD request once the adapter is connected to the car.
  final Duration requestTimeout;

  /// For `ATZ`, which reboots the adapter.
  final Duration resetTimeout;

  /// For the first request after a protocol is chosen, when the adapter may
  /// search through the protocols before it answers.
  final Duration searchTimeout;

  /// The least time from one command's end to the next one's start. Zero goes
  /// as fast as the adapter answers; a slower pace is for adapters that cannot
  /// keep up.
  final Duration minGap;

  /// How long to wait for a prompt that is late, when the answer to a request
  /// has arrived whole and the request said how many answers to expect.
  final Duration promptGrace;

  /// The pause after a timeout before the next command, in case the adapter is
  /// still busy with the last one.
  final Duration settleAfterTimeout;

  Elm327Timing copyWith({Duration? minGap}) => Elm327Timing(
    commandTimeout: commandTimeout,
    requestTimeout: requestTimeout,
    resetTimeout: resetTimeout,
    searchTimeout: searchTimeout,
    minGap: minGap ?? this.minGap,
    promptGrace: promptGrace,
    settleAfterTimeout: settleAfterTimeout,
  );
}

/// What came back for one command.
class Elm327Reply {
  const Elm327Reply({
    required this.command,
    required this.sentAt,
    required this.completedAt,
    this.dataAt,
    this.failure,
    this.lines = const [],
    this.messages = const [],
    this.raw = '',
    this.searched = false,
    this.gotPrompt = true,
  });

  /// The command as it was sent, without its carriage return.
  final String command;

  /// When it was written, on the monotonic clock.
  final Duration sentAt;

  /// When the first line of content was complete, or null if none came.
  final Duration? dataAt;

  /// When the reply was done: the prompt arrived, or the wait was given up.
  final Duration completedAt;

  /// Why there is no answer, or null if there is one.
  final Elm327Failure? failure;

  /// The content lines, for any command.
  final List<String> lines;

  /// For an OBD request, each ECU's answer as bytes. Empty for anything else,
  /// and when there is a failure.
  final List<List<int>> messages;

  /// Everything received for this command, for diagnostics.
  final String raw;

  /// Whether the adapter said `SEARCHING...`.
  final bool searched;

  /// False if the reply was accepted without its `>`.
  final bool gotPrompt;

  bool get ok => failure == null;

  /// How long the answer took to arrive: from the write to the first line of
  /// content. The prompt can come much later on an adapter that waits out a
  /// timeout, so this is not the time to the prompt.
  Duration? get latency => dataAt == null ? null : dataAt! - sentAt;

  /// When the car was asked, which is to say when the values in the answer
  /// were read: the middle of the round trip (DESIGN.md 5.2).
  Duration? get sampleTime => latency == null
      ? null
      : sentAt + Duration(microseconds: latency!.inMicroseconds ~/ 2);

  /// From the write to the end of the reply.
  Duration get elapsed => completedAt - sentAt;

  @override
  String toString() =>
      'Elm327Reply($command, ${failure ?? (messages.isNotEmpty ? messages : lines)})';
}

/// The conversation with an ELM327 adapter (CLAUDE.md 8.1): one command in
/// flight at a time, each ended by its prompt, with the echo and the adapter's
/// notices taken off and its errors turned into typed failures.
///
/// It works in callbacks, and never awaits, so on a fake clock a whole drive
/// runs inside one `advance`. It behaves the same on a transport that delivers
/// at once and on one that delivers later.
///
/// What it does about a bad adapter:
///  - a reply is read as its pieces arrive, so a prompt in a separate piece, or
///    a line cut in two, is no trouble;
///  - a request can say which answer it expects (`expectPrefix`), and a reply
///    that is for another request, such as a late one to a command that timed
///    out, is skipped and the wait goes on;
///  - a bare prompt is not an answer to a request;
///  - a reply that has all its data but no prompt is accepted after a short
///    grace, if the request said how many answers to expect;
///  - the time of each reply is measured to its first line of data, not to its
///    prompt.
class Elm327Client {
  Elm327Client({
    required this.transport,
    required this.scheduler,
    required this.clock,
    this.timing = const Elm327Timing(),
  }) {
    _stateSubscription = transport.state.listen(_onState);
    _dataSubscription = transport.incoming.listen(_onData);
  }

  final Transport transport;
  final Scheduler scheduler;
  final Clock clock;

  /// The timing. It can be changed while running, for instance to slow the
  /// pace for an adapter that cannot keep up.
  Elm327Timing timing;

  final Queue<_Job> _queue = Queue();
  _Job? _active;
  final StringBuffer _buffer = StringBuffer();
  Duration _sentAt = Duration.zero;
  Duration? _dataAt;
  Duration? _lastChunkAt;
  Duration? _lastFinishedAt;
  ScheduledTask? _timeoutTask;
  ScheduledTask? _graceTask;
  ScheduledTask? _pumpTask;
  StreamSubscription<Object?>? _stateSubscription;
  StreamSubscription<Object?>? _dataSubscription;
  bool _disposed = false;
  bool _settle = false;

  int _sent = 0;
  int _timeouts = 0;
  int _garbled = 0;
  int _skipped = 0;
  int _stray = 0;
  int _missingPrompts = 0;

  /// Commands written.
  int get commandsSent => _sent;

  /// Commands that got no reply in time.
  int get timeouts => _timeouts;

  /// Replies that arrived and could not be read.
  int get garbledReplies => _garbled;

  /// Replies skipped as belonging to another request, or as a bare prompt.
  int get skippedReplies => _skipped;

  /// Characters that arrived when nothing was waiting for them.
  int get strayCharacters => _stray;

  /// Replies accepted without their prompt.
  int get missingPrompts => _missingPrompts;

  /// Whether nothing is in flight or waiting.
  bool get isIdle => _active == null && _queue.isEmpty;

  /// How many commands are waiting behind the one in flight.
  int get queued => _queue.length;

  /// Sends an AT command, or any text that is not a request for data, and
  /// calls [done] with the outcome. [text] has no carriage return.
  void command(
    String text,
    void Function(Elm327Reply reply) done, {
    Duration? timeout,
  }) {
    _submit(
      _Job(
        text: text,
        timeout: timeout ?? timing.commandTimeout,
        isRequest: false,
        done: done,
      ),
    );
  }

  /// Sends a request for data, as the bytes the car is to be sent, and calls
  /// [done] with the outcome.
  ///
  /// [responses] is how many answers to expect. Adding it to the request lets
  /// the adapter finish as soon as they are in, where otherwise it waits out
  /// its timeout for more. [expectPrefix] is the start of the answer that this
  /// request is for, such as `[0x41, 0x0C]`: an answer that does not start
  /// with it is skipped as belonging to some other request.
  void request(
    List<int> bytes,
    void Function(Elm327Reply reply) done, {
    int? responses,
    List<int>? expectPrefix,
    Duration? timeout,
  }) {
    final hex = [
      for (final b in bytes) b.toRadixString(16).toUpperCase().padLeft(2, '0'),
    ].join();
    _submit(
      _Job(
        text: responses == null
            ? hex
            : '$hex${responses.toRadixString(16).toUpperCase()}',
        timeout: timeout ?? timing.requestTimeout,
        isRequest: true,
        expectPrefix: expectPrefix,
        expected: responses != null && responses > 0 ? responses : null,
        done: done,
      ),
    );
  }

  void _submit(_Job job) {
    if (_disposed || !transport.currentState.isConnected) {
      // Never call back from inside the call that asked.
      scheduler.runAfter(Duration.zero, () => _finishUnsent(job));
      return;
    }
    _queue.add(job);
    _pump();
  }

  void _finishUnsent(_Job job) {
    final now = clock.monotonic();
    job.done(
      Elm327Reply(
        command: job.text,
        sentAt: now,
        completedAt: now,
        failure: Elm327Failure.disconnected,
      ),
    );
  }

  void _pump() {
    if (_disposed || _active != null || _queue.isEmpty) return;
    if (!transport.currentState.isConnected) {
      _failAll(Elm327Failure.disconnected);
      return;
    }
    final last = _lastFinishedAt;
    if (last != null) {
      var pause = timing.minGap;
      if (_settle && timing.settleAfterTimeout > pause) {
        pause = timing.settleAfterTimeout;
      }
      final wait = last + pause - clock.monotonic();
      if (wait > Duration.zero) {
        _pumpTask?.cancel();
        _pumpTask = scheduler.runAfter(wait, () {
          _pumpTask = null;
          _pump();
        });
        return;
      }
    }
    _pumpTask?.cancel();
    _pumpTask = null;
    _settle = false;

    final job = _queue.removeFirst();
    _active = job;
    _buffer.clear();
    _dataAt = null;
    _lastChunkAt = null;
    _sentAt = clock.monotonic();
    _sent++;
    transport.write('${job.text}\r').catchError((Object _) {});
    _timeoutTask = scheduler.runAfter(job.timeout, _onTimeout);
  }

  void _onData(String chunk) {
    final job = _active;
    if (job == null) {
      _stray += chunk.length;
      return;
    }
    _buffer.write(chunk);
    _lastChunkAt = clock.monotonic();
    final text = _buffer.toString();

    final prompt = text.indexOf('>');
    if (prompt >= 0) {
      // Whatever follows the first prompt is not part of this reply.
      if (prompt + 1 < text.length) _stray += text.length - prompt - 1;
      _noteData(text.substring(0, prompt), job);
      _complete(job, text.substring(0, prompt + 1), gotPrompt: true);
      return;
    }
    _noteData(text, job);
    _maybeGrace(job, text);
  }

  /// Notes the moment the first line of content was complete.
  void _noteData(String text, _Job job) {
    if (_dataAt != null) return;
    final end = text.lastIndexOf(RegExp(r'[\r\n]'));
    // At the prompt, the text ends the last line whether or not it has a CR.
    final complete = text.endsWith('\r') || text.endsWith('\n')
        ? text
        : (end < 0 ? '' : text.substring(0, end + 1));
    if (complete.isEmpty) return;
    final parsed = Elm327Parser.parse(complete, sentCommand: job.text);
    if (parsed.lines.isNotEmpty || parsed.failure != null) {
      _dataAt = _lastChunkAt;
    }
  }

  /// A request that said how many answers to expect, and has them all but the
  /// prompt, is accepted if the prompt is late.
  void _maybeGrace(_Job job, String text) {
    if (!job.isRequest || job.expected == null || _graceTask != null) return;
    final end = text.lastIndexOf(RegExp(r'[\r\n]'));
    if (end < 0) return;
    final parsed = Elm327Parser.parse(
      text.substring(0, end + 1),
      sentCommand: job.text,
    );
    final ready =
        parsed.failure != null ||
        _matching(job, Elm327Parser.messages(parsed.lines)).length >=
            job.expected!;
    if (!ready) return;
    _graceTask = scheduler.runAfter(timing.promptGrace, () {
      _graceTask = null;
      if (identical(_active, job)) {
        _complete(job, _buffer.toString(), gotPrompt: false);
      }
    });
  }

  /// The messages that start with what the job expects.
  List<List<int>> _matching(_Job job, List<List<int>>? messages) {
    if (messages == null) return const [];
    final prefix = job.expectPrefix;
    if (prefix == null) return messages;
    return [
      for (final m in messages)
        if (_startsWith(m, prefix)) m,
    ];
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  void _complete(_Job job, String raw, {required bool gotPrompt}) {
    final parsed = Elm327Parser.parse(raw, sentCommand: job.text);
    Elm327Failure? failure = parsed.failure;
    var messages = <List<int>>[];

    if (failure == null && job.isRequest) {
      final all = Elm327Parser.messages(parsed.lines);
      if (all == null) {
        failure = Elm327Failure.garbled;
        _garbled++;
      } else if (all.isEmpty) {
        // A bare prompt is not an answer: most likely the tail of an earlier
        // command's reply. The real one may still be on its way.
        _skip();
        return;
      } else {
        messages = _matching(job, all);
        if (messages.isEmpty) {
          // An answer, but to another request.
          _skip();
          return;
        }
      }
    }

    if (!gotPrompt) _missingPrompts++;
    _finish(
      job,
      Elm327Reply(
        command: job.text,
        sentAt: _sentAt,
        dataAt: _dataAt,
        completedAt: clock.monotonic(),
        failure: failure,
        lines: parsed.lines,
        messages: failure == null ? messages : const [],
        raw: raw,
        searched: parsed.searched,
        gotPrompt: gotPrompt,
      ),
    );
  }

  /// Throws away a reply that is not for the job in flight, and waits on.
  void _skip() {
    _skipped++;
    _buffer.clear();
    _dataAt = null;
    _graceTask?.cancel();
    _graceTask = null;
  }

  void _onTimeout() {
    final job = _active;
    if (job == null) return;
    _timeouts++;
    _settle = true;
    _finish(
      job,
      Elm327Reply(
        command: job.text,
        sentAt: _sentAt,
        dataAt: _dataAt,
        completedAt: clock.monotonic(),
        failure: Elm327Failure.timeout,
        raw: _buffer.toString(),
      ),
    );
  }

  void _finish(_Job job, Elm327Reply reply) {
    _timeoutTask?.cancel();
    _timeoutTask = null;
    _graceTask?.cancel();
    _graceTask = null;
    _active = null;
    _lastFinishedAt = clock.monotonic();
    job.done(reply);
    _pump();
  }

  void _onState(TransportState state) {
    if (!state.isConnected) {
      _failAll(Elm327Failure.disconnected);
      _lastFinishedAt = null;
      _settle = false;
    }
  }

  /// Ends the job in flight and everything waiting, with [failure].
  void _failAll(Elm327Failure failure) {
    final jobs = <_Job>[?_active, ..._queue];
    final sentAt = _sentAt;
    final raw = _buffer.toString();
    final active = _active;
    _queue.clear();
    _active = null;
    _timeoutTask?.cancel();
    _timeoutTask = null;
    _graceTask?.cancel();
    _graceTask = null;
    _pumpTask?.cancel();
    _pumpTask = null;
    _buffer.clear();
    final now = clock.monotonic();
    for (final job in jobs) {
      job.done(
        Elm327Reply(
          command: job.text,
          sentAt: identical(job, active) ? sentAt : now,
          completedAt: now,
          failure: failure,
          raw: identical(job, active) ? raw : '',
        ),
      );
    }
  }

  /// Stops listening. Anything waiting fails as disconnected.
  void dispose() {
    if (_disposed) return;
    _failAll(Elm327Failure.disconnected);
    _disposed = true;
    unawaited(_stateSubscription?.cancel());
    unawaited(_dataSubscription?.cancel());
    _stateSubscription = null;
    _dataSubscription = null;
  }
}

class _Job {
  _Job({
    required this.text,
    required this.timeout,
    required this.isRequest,
    required this.done,
    this.expectPrefix,
    this.expected,
  });

  final String text;
  final Duration timeout;
  final bool isRequest;
  final List<int>? expectPrefix;
  final int? expected;
  final void Function(Elm327Reply reply) done;
}
