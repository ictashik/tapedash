import 'dart:async';
import 'dart:collection';

import '../../core/clock.dart';
import '../../core/observable.dart';
import '../../core/scheduler.dart';
import '../elm327/elm327_client.dart';
import '../elm327/elm327_failure.dart';
import '../elm327/elm327_init.dart';
import '../elm327/elm327_parser.dart';
import '../obd_session.dart' show AdapterMemory, InMemoryAdapterMemory;
import '../pids/pid.dart';
import '../transport/transport.dart';
import 'headed_reply.dart';
import 'mode01_lengths.dart';
import 'survey_schedule.dart';

/// Where a survey stands.
enum SurveyPhase {
  /// The link to the adapter is not up (yet, or again).
  connecting,

  /// The adapter is being set up.
  starting,

  /// Asking which ECUs answer, and which PIDs each has.
  discovering,

  /// Reading everything once, ECU by ECU: every PID, the fault codes, the test
  /// results and the calibration IDs.
  probing,

  /// The drive: reading the PIDs round and round, as fast as the link allows.
  driving,

  /// The car stopped answering (the ignition is off). It is asked every
  /// couple of seconds whether it is back.
  waitingForCar,

  /// Ended by the user, or by the car being off for too long.
  finished,

  /// It could not be done: the adapter is not one this can use.
  failed,
}

/// Whether the survey is using the adapter's receive filter (`ATCRA`) to listen
/// to one ECU at a time.
enum SurveyFilter {
  /// Not needed: there is one ECU, or the survey has not got that far.
  unused,

  /// In use.
  working,

  /// The adapter does not take it, so every ECU is heard at once.
  refused,
}

/// What a survey is doing and has found, for the screen and for tests.
class SurveyProgress {
  const SurveyProgress({
    required this.phase,
    required this.elapsed,
    this.requests = 0,
    this.answered = 0,
    this.failed = 0,
    this.answersPerSecond = 0,
    this.ecus = const [],
    this.pidsSeen = 0,
    this.pidsAvailable = 0,
    this.batch = 0,
    this.filter = SurveyFilter.unused,
    this.rpm,
    this.speedKmh,
    this.volts,
    this.adapterVolts,
    this.linkDrops = 0,
    this.detail,
  });

  final SurveyPhase phase;

  /// Since the survey began.
  final Duration elapsed;

  /// Requests sent, and how many were answered and how many were not.
  final int requests;
  final int answered;
  final int failed;

  /// Recent answers a second.
  final double answersPerSecond;

  /// The IDs of the ECUs that answered.
  final List<String> ecus;

  /// How many different PIDs have been read, out of how many the ECUs have.
  final int pidsSeen;
  final int pidsAvailable;

  /// How many PIDs go in one request now.
  final int batch;
  final SurveyFilter filter;

  /// The latest, if read in the last few seconds.
  final double? rpm;
  final double? speedKmh;
  final double? volts;

  /// What the adapter itself measures at the OBD socket.
  final double? adapterVolts;

  /// How many times the link was lost and opened again.
  final int linkDrops;

  /// A line in words for whoever is watching, such as why it failed.
  final String? detail;

  /// Whether the car is standing: no speed read, or 0.
  bool get isParked => speedKmh == null || speedKmh == 0;
}

/// A survey of what a car's ECUs have to say (the "survey drive" of Garage).
///
/// It reads and never writes: Mode 01 (live data), 03, 07 and 0A (fault codes),
/// 06 (test results) and 09 (calibration IDs). It does not clear codes, and it
/// does not ask for the VIN. It keeps the adapter's whole conversation in the
/// log of the transport it is given, so everything it finds can be worked out
/// later at a desk, whatever it made of the car at the time.
///
/// **What it does, in order.**
///  1. Starts the adapter up (the same `Elm327Initializer` as the dashboard).
///  2. Turns headers on and asks `0100`, `0120`... so each ECU's reply carries
///     its ID: who answers, and which PIDs each has.
///  3. Reads every one of those PIDs once from each ECU, then the other modes.
///     With several ECUs it listens to one at a time (`ATCRA`), because
///     otherwise only one of them gets its long messages through (see
///     `Elm327Simulator`, and the first real recordings).
///  4. Drives: reads the PIDs round and round, with headers off, six to a
///     request, the ones that say what the engine is doing most often
///     ([SurveySchedule]). If the adapter does not take batches it falls back
///     to fewer, down to one; if it does not take the filter it listens to all.
///  5. If the car goes quiet (ignition off) it waits and starts again when it
///     answers; if the link drops it opens it again.
///
/// **Unverified on hardware**: `ATCRA`, headers-on framing and batches on this
/// adapter are all assumptions until a real survey runs. Every one has a way
/// back, and the log says which was used (`@ survey ...` lines).
class SurveyRunner {
  SurveyRunner({
    required this.transport,
    required this.clock,
    required this.scheduler,
    this.config = const SurveyConfig(),
    this.note,
    AdapterMemory? memory,
  }) : memory = memory ?? InMemoryAdapterMemory() {
    client = Elm327Client(
      transport: transport,
      scheduler: scheduler,
      clock: clock,
    );
    _batch = config.maxBatch;
    _progress = ObservableValue(_snapshot());
  }

  final Transport transport;
  final Clock clock;
  final Scheduler scheduler;
  final SurveyConfig config;
  final AdapterMemory memory;

  /// Writes a line about the survey into the log (a `@` line).
  final void Function(String text)? note;

  late final Elm327Client client;
  late final ObservableValue<SurveyProgress> _progress;

  Observable<SurveyProgress> get progress => _progress;

  // ---- the run
  bool _running = false;
  bool _finished = false;
  bool _linkUp = false;
  bool _connecting = false;
  int _epoch = 0;
  Duration _startedAt = Duration.zero;
  Duration _retryDelay = Duration.zero;
  ScheduledTask? _retryTask;
  ScheduledTask? _loopTask;
  ScheduledTask? _ticker;
  Elm327Initializer? _initializer;
  StreamSubscription<TransportState>? _stateSubscription;
  SurveyPhase _phase = SurveyPhase.connecting;
  String? _detail;
  int _initFailures = 0;
  int _linkDrops = 0;

  // ---- what it has found
  final Map<String, Set<int>> _supported = {};
  List<String> _ecus = const [];
  bool _headersOn = false;
  bool _discovered = false;
  bool _probed = false;
  SurveyFilter _filterState = SurveyFilter.unused;
  String? _filter;
  SurveySchedule? _schedule;

  // ---- the step queue of discovery and the probe
  final Queue<_Step> _steps = Queue();
  void Function()? _stepsDone;

  // ---- the drive loop
  int _batch = 6;
  int _strikes = 0;
  int _goodBatches = 0;
  int _failStreak = 0;
  Duration _lastAnswerAt = Duration.zero;
  Duration _nextVitals = Duration.zero;
  Duration _nextAdapterVolts = Duration.zero;
  Duration _waitingSince = Duration.zero;

  // ---- counts, and the latest values
  int _requests = 0;
  int _answered = 0;
  int _failed = 0;
  int _answeredAtTick = 0;
  double _rate = 0;
  final Map<int, int> _seen = {};
  final Map<int, (double, Duration)> _live = {};
  double? _adapterVolts;

  bool get isRunning => _running;

  // ------------------------------------------------------------------ control

  /// Starts. The transport may be connected already or not.
  void start() {
    if (_running || _finished) return;
    _running = true;
    _startedAt = clock.monotonic();
    _lastAnswerAt = _startedAt;
    _say('survey start');
    _stateSubscription = transport.state.listen(_onTransportState);
    _ticker = scheduler.runEvery(const Duration(seconds: 1), _tick);
    _setPhase(SurveyPhase.connecting);
    if (transport.currentState.isConnected) {
      _linkUp = true;
      _onLinkUp();
    } else {
      _connect();
    }
  }

  /// Ends the survey. The transport is left to whoever made it.
  void finish([String reason = 'stopped']) {
    if (_finished) return;
    _say(
      'survey done reason=$reason requests=$_requests answered=$_answered '
      'failed=$_failed pids=${_seen.length}',
    );
    _stop();
    if (_phase != SurveyPhase.failed) _phase = SurveyPhase.finished;
    _publish();
  }

  void _stop() {
    _finished = true;
    _running = false;
    _epoch++;
    _initializer?.cancel();
    _initializer = null;
    _retryTask?.cancel();
    _retryTask = null;
    _loopTask?.cancel();
    _loopTask = null;
    _ticker?.cancel();
    _ticker = null;
    _steps.clear();
    _stepsDone = null;
  }

  /// Stops and lets go of the adapter conversation.
  void dispose() {
    if (!_finished) _stop();
    _stateSubscription?.cancel();
    _stateSubscription = null;
    client.dispose();
    _progress.dispose();
  }

  void _fail(String detail) {
    _say('survey failed: $detail');
    _detail = detail;
    _phase = SurveyPhase.failed;
    _stop();
    _publish();
  }

  // --------------------------------------------------------------- the link

  void _connect() {
    if (!_running || _connecting || _linkUp) return;
    _connecting = true;
    transport.connect().then((_) {}, onError: (Object _) {});
  }

  void _onTransportState(TransportState state) {
    if (!_running) return;
    switch (state.status) {
      case TransportStatus.connecting:
        break;
      case TransportStatus.connected:
        _connecting = false;
        if (!_linkUp) {
          _linkUp = true;
          _onLinkUp();
        }
      case TransportStatus.disconnected:
        _connecting = false;
        _linkDown();
    }
  }

  void _linkDown() {
    final wasUp = _linkUp;
    _linkUp = false;
    _epoch++;
    _initializer?.cancel();
    _initializer = null;
    _loopTask?.cancel();
    _loopTask = null;
    _steps.clear();
    _stepsDone = null;
    _filter = null;
    _headersOn = false;
    if (!_running) return;
    if (wasUp) {
      _linkDrops++;
      _say('survey link lost');
    }
    _setPhase(SurveyPhase.connecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running || _retryTask != null) return;
    _retryDelay = _retryDelay == Duration.zero
        ? config.firstRetry
        : _min(_retryDelay * 2, config.longestRetry);
    _retryTask = scheduler.runAfter(_retryDelay, () {
      _retryTask = null;
      _connect();
    });
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;

  // ----------------------------------------------------------------- start-up

  void _onLinkUp() {
    _setPhase(SurveyPhase.starting);
    final epoch = _epoch;
    _initializer =
        Elm327Initializer(
          client: client,
          scheduler: scheduler,
          options: InitOptions(
            knownProtocol: memory.protocol,
            settle: config.settle,
          ),
        )..run((result) {
          if (epoch != _epoch || !_running) return;
          _initializer = null;
          _onInitDone(result);
        });
  }

  void _onInitDone(InitResult result) {
    switch (result.status) {
      case InitStatus.ready:
        _initFailures = 0;
        _retryDelay = Duration.zero;
        final info = result.info!;
        final protocol = info.protocolNumber;
        if (protocol != null) memory.protocol = protocol;
        _say(
          'survey adapter banner="${info.banner}" protocol=$protocol '
          'ecus=${info.ecuCount} retries=${info.retries}'
          '${info.warnings.isEmpty ? '' : ' warnings=${info.warnings.join('; ')}'}',
        );
        _onAdapterReady();
      case InitStatus.waitingForIgnition:
        _initFailures = 0;
        _say('survey car not answering at start');
        _waitForCar();
      case InitStatus.failed:
        switch (result.failure) {
          case InitFailure.linkLost:
            break;
          case InitFailure.incompatible:
            _fail('the adapter cannot be used: ${result.detail ?? ''}');
          case InitFailure.noResponse || null:
            if (++_initFailures >= 3) {
              _fail('the adapter does not answer');
            } else {
              _closeLink();
            }
        }
    }
  }

  void _closeLink() {
    _epoch++;
    _linkUp = false;
    _connecting = false;
    _scheduleReconnect();
    transport.disconnect().catchError((Object _) {});
  }

  /// The adapter is set up and the car answers.
  void _onAdapterReady() {
    _filter = null;
    _headersOn = false;
    if (_probed && _schedule != null) {
      // A reconnection: nothing to find out again.
      _say('survey resumed after reconnect');
      _startLoop();
    } else if (_discovered) {
      _probe();
    } else {
      _identify();
    }
  }

  /// What the adapter calls itself and what it sees at the socket, for the log.
  void _identify() {
    _steps.clear();
    _push('ATI', (_) {});
    _push('AT@1', (_) {});
    _push('ATRV', _onAdapterVolts);
    _runSteps(_discover);
  }

  // -------------------------------------------------------------- discovery

  void _discover() {
    _setPhase(SurveyPhase.discovering);
    _steps.clear();
    _supported.clear();
    _push('ATH1', (r) {
      _headersOn = r.ok;
      if (!r.ok) _say('survey headers refused: ECUs cannot be told apart');
    });
    _steps.addLast(_maskStep(0, first: true));
    _runSteps(_afterDiscovery);
  }

  /// The step that asks which PIDs follow [base] (`0100`, `0120`...) and, if
  /// the answer says there are more, puts the next such step next in line.
  _Step _maskStep(int base, {bool first = false}) {
    return _Step(() => '01${_hex2(base)}', (r) {
      if (first && _headersOn && r.messages.isEmpty && r.hasLines) {
        // Headers are on and nothing could be read: the framing is not what
        // was expected. Go on without telling the ECUs apart.
        _say('survey headed replies unreadable: going on without headers');
        _headersOn = false;
        _steps
          ..clear()
          ..addLast(_Step(() => 'ATH0', (_) {}))
          ..addLast(_maskStep(0));
        return;
      }
      var more = false;
      for (final m in r.messages) {
        final p = m.payload;
        if (p.length < 6 || p[0] != 0x41 || p[1] != base) continue;
        final set = _supported.putIfAbsent(m.id, () => {});
        for (var byte = 0; byte < 4; byte++) {
          for (var bit = 0; bit < 8; bit++) {
            if (p[2 + byte] & (0x80 >> bit) != 0) {
              set.add(base + byte * 8 + bit + 1);
            }
          }
        }
        if (p[5] & 1 != 0) more = true;
      }
      if (more && base < 0xC0) _insertAll([_maskStep(base + 0x20)]);
    });
  }

  void _afterDiscovery() {
    _discovered = true;
    _ecus = _supported.keys.toList()..sort();
    if (_ecus.isEmpty) {
      _say('survey no ECU answered');
      _waitForCar();
      return;
    }
    for (final ecu in _ecus) {
      final pids = (_supported[ecu]!.toList()..sort()).map(_hex2).join(',');
      _say('survey ecu id=$ecu pids=$pids');
    }
    _probe();
  }

  // ---------------------------------------------------------------- the probe

  bool get _manyEcus => _ecus.length > 1;

  /// The digit that says how many answers to wait for, when only one can come.
  String get _expect =>
      (!_manyEcus || _filterState == SurveyFilter.working) ? '1' : '';

  void _probe() {
    _setPhase(SurveyPhase.probing);
    _steps.clear();
    for (final ecu in _ecus) {
      if (_manyEcus && _filterState != SurveyFilter.refused) {
        _push('ATCRA$ecu', (r) {
          if (r.ok) {
            _filter = ecu;
            _filterState = SurveyFilter.working;
          } else {
            _filter = null;
            _filterState = SurveyFilter.refused;
            _say('survey ATCRA refused: listening to every ECU at once');
          }
        }, when: () => _filterState != SurveyFilter.refused);
      }
      _say('survey probe ecu=$ecu');
      for (final pid in _supported[ecu]!.toList()..sort()) {
        if (Mode01Lengths.isSupportMask(pid)) continue;
        _push('01${_hex2(pid)}', (_) {}, expectDigit: true);
      }
      _push('0900', (r) => _onMode09Mask(r), expectDigit: true);
      _push('0600', (r) => _onMode06Mask(r, 0x00, []), expectDigit: true);
      _push('03', (_) {}, expectDigit: true);
      _push('07', (_) {}, expectDigit: true);
      _push('0A', (_) {}, expectDigit: true);
    }
    if (_manyEcus) {
      _push('ATCRA', (_) {
        _filter = null;
      }, when: () => _filterState == SurveyFilter.working);
    }
    _push('ATH0', (_) => _headersOn = false);
    _runSteps(() {
      _probed = true;
      _schedule = SurveySchedule.build(_supported, config);
      _say('survey probe done');
      _startLoop();
    });
  }

  void _onMode09Mask(_Reply r) {
    // Which of the calibration ID (04), its verification number (06) and the
    // ECU name (0A) the ECU has. PID 02, the VIN, is never asked for.
    final wanted = <int>[];
    for (final m in r.messages) {
      final p = m.payload;
      if (p.length < 6 || p[0] != 0x49 || p[1] != 0x00) continue;
      for (final pid in const [0x04, 0x06, 0x0A]) {
        final index = pid - 1;
        if (p[2 + index ~/ 8] & (0x80 >> (index % 8)) != 0) wanted.add(pid);
      }
    }
    final steps = [
      for (final pid in wanted.toSet())
        _Step(() => '09${_hex2(pid)}$_expect', (_) {}),
    ];
    _insertAll(steps);
  }

  void _onMode06Mask(_Reply r, int base, List<int> found) {
    var more = false;
    for (final m in r.messages) {
      final p = m.payload;
      if (p.length < 6 || p[0] != 0x46 || p[1] != base) continue;
      for (var byte = 0; byte < 4; byte++) {
        for (var bit = 0; bit < 8; bit++) {
          if (p[2 + byte] & (0x80 >> bit) != 0) {
            final id = base + byte * 8 + bit + 1;
            if (!Mode01Lengths.isSupportMask(id)) found.add(id);
          }
        }
      }
      if (p[5] & 1 != 0) more = true;
    }
    if (more && base < 0xE0) {
      final next = base + 0x20;
      _insertAll([
        _Step(
          () => '06${_hex2(next)}$_expect',
          (r2) => _onMode06Mask(r2, next, found),
        ),
      ]);
    } else {
      _insertAll([
        for (final id in found.toSet().take(config.maxMonitorIds))
          _Step(() => '06${_hex2(id)}$_expect', (_) {}),
      ]);
    }
  }

  // ---------------------------------------------------------------- step queue

  void _push(
    String command,
    void Function(_Reply) handle, {
    bool expectDigit = false,
    bool Function()? when,
  }) {
    _steps.addLast(
      _Step(
        () => expectDigit ? '$command$_expect' : command,
        handle,
        when: when,
      ),
    );
  }

  /// Puts [steps] in front of everything waiting, in order.
  void _insertAll(List<_Step> steps) {
    final waiting = List<_Step>.of(_steps);
    _steps
      ..clear()
      ..addAll(steps)
      ..addAll(waiting);
  }

  void _runSteps(void Function() done) {
    _stepsDone = done;
    _stepPump();
  }

  void _stepPump() {
    if (!_running) return;
    if (_steps.isEmpty) {
      final done = _stepsDone;
      _stepsDone = null;
      done?.call();
      return;
    }
    final step = _steps.removeFirst();
    if (step.when != null && !step.when!()) {
      _stepPump();
      return;
    }
    _ask(step.command(), (r) {
      step.handle(r);
      _stepPump();
    });
  }

  void _ask(String command, void Function(_Reply) then) {
    final epoch = _epoch;
    _requests++;
    client.command(command, (reply) {
      if (epoch != _epoch || !_running) return;
      if (reply.failure == Elm327Failure.disconnected) return;
      if (reply.failure == Elm327Failure.lowVoltageReset) {
        _adapterReset();
        return;
      }
      if (reply.ok) {
        _answered++;
      } else {
        _failed++;
      }
      then(_Reply(reply, _messagesOf(reply)));
    });
  }

  List<HeadedMessage> _messagesOf(Elm327Reply reply) {
    if (!reply.ok || reply.lines.isEmpty) return const [];
    if (_headersOn) return HeadedReply.parse(reply.lines).messages;
    final plain = Elm327Parser.messages(reply.lines);
    if (plain == null) return const [];
    return [
      for (final bytes in plain)
        HeadedMessage(id: _filter ?? 'ALL', payload: bytes, complete: true),
    ];
  }

  /// The adapter reset itself (a drop in its supply): it has forgotten every
  /// setting, so start it up again.
  void _adapterReset() {
    _say('survey adapter reset (low voltage)');
    _epoch++;
    _steps.clear();
    _stepsDone = null;
    _loopTask?.cancel();
    _loopTask = null;
    _filter = null;
    _headersOn = false;
    if (_linkUp) _onLinkUp();
  }

  // ----------------------------------------------------------------- the drive

  void _startLoop() {
    final now = clock.monotonic();
    _setPhase(SurveyPhase.driving);
    _failStreak = 0;
    _lastAnswerAt = now;
    _nextVitals = now + config.vitalsEvery;
    _nextAdapterVolts = now;
    _schedule?.clearSuspensions();
    _say(
      'survey drive batch=$_batch filter=${_filterState.name} '
      'ecus=${_ecus.length}',
    );
    _loop();
  }

  void _loop() {
    if (!_running || !_linkUp || _phase != SurveyPhase.driving) return;
    final now = clock.monotonic();
    if (now >= _nextVitals) {
      _nextVitals = now + config.vitalsEvery;
      _vitals();
    }
    if (now >= _nextAdapterVolts) {
      _nextAdapterVolts = now + config.adapterVoltsEvery;
      _ask('ATRV', (r) {
        _onAdapterVolts(r);
        _loop();
      });
      return;
    }
    final schedule = _schedule;
    final request = schedule?.next(
      now,
      maxBatch: _batch,
      stayOn: _filter,
      switchWhenOverdue: config.switchWhenOverdue,
    );
    if (schedule == null || request == null) {
      _loopTask = scheduler.runAfter(const Duration(milliseconds: 200), _loop);
      return;
    }
    final needsFilter =
        _manyEcus &&
        _filterState != SurveyFilter.refused &&
        _filter != request.ecu;
    if (needsFilter) {
      _ask('ATCRA${request.ecu}', (r) {
        if (r.ok) {
          _filter = request.ecu;
          _filterState = SurveyFilter.working;
        } else {
          _filter = null;
          _filterState = SurveyFilter.refused;
          _say('survey ATCRA refused: listening to every ECU at once');
        }
        _send(request);
      });
    } else {
      _send(request);
    }
  }

  void _send(SurveyRequest request) {
    final epoch = _epoch;
    _requests++;
    final single = !_manyEcus || _filterState == SurveyFilter.working;
    client.request(
      [0x01, ...request.pids],
      (reply) {
        if (epoch != _epoch || !_running) return;
        if (reply.failure == Elm327Failure.disconnected) return;
        _onAnswer(request, reply);
        _loop();
      },
      responses: single ? 1 : null,
      expectPrefix: const [0x41],
      acceptPrefixes: const [
        [0x7F],
      ],
    );
  }

  void _onAnswer(SurveyRequest request, Elm327Reply reply) {
    final now = clock.monotonic();
    final failure = reply.failure;
    if (failure == Elm327Failure.disconnected) return;
    if (failure == Elm327Failure.lowVoltageReset) {
      _adapterReset();
      return;
    }
    final size = request.pids.length;
    final got = <int>{};
    if (failure == null) {
      for (final message in reply.messages) {
        final walked = Mode01Lengths.walk(message);
        for (final (pid, data) in walked.values) {
          got.add(pid);
          _seen[pid] = (_seen[pid] ?? 0) + 1;
          _noteValue(pid, data, now);
        }
      }
    }
    final schedule = _schedule!;
    if (got.isNotEmpty) {
      _answered++;
      _failStreak = 0;
      _lastAnswerAt = now;
      schedule.record(request, now, got: got, config: config);
      _batchResult(size, ok: true);
      return;
    }
    _failed++;
    _failStreak++;
    if (size == 1) {
      // One PID asked for and nothing back: the PID's own miss.
      schedule.record(request, now, got: const {}, config: config);
    } else {
      _batchResult(size, ok: false);
    }
    if (_failStreak >= config.silentAfter &&
        now - _lastAnswerAt > const Duration(seconds: 5)) {
      _waitForCar();
    }
  }

  /// Halves the batch after repeated failures and grows it back after a long
  /// run of successes.
  void _batchResult(int size, {required bool ok}) {
    if (size <= 1) return;
    if (ok) {
      _strikes = 0;
      if (_batch < config.maxBatch &&
          ++_goodBatches >= config.batchRegrowAfter) {
        _goodBatches = 0;
        final bigger = (_batch * 2).clamp(1, config.maxBatch);
        _say('survey batch $_batch->$bigger reason=steady');
        _batch = bigger;
      }
    } else {
      _goodBatches = 0;
      if (++_strikes >= config.batchStrikes) {
        _strikes = 0;
        final smaller = _batch ~/ 2 < 1 ? 1 : _batch ~/ 2;
        if (smaller != _batch) {
          _say('survey batch $_batch->$smaller reason=failures');
          _batch = smaller;
        }
      }
    }
  }

  void _noteValue(int pid, List<int> data, Duration now) {
    final known = Pids.byId(pid);
    if (known == null || known.length != data.length) return;
    _live[pid] = (known.decode(data), now);
  }

  void _onAdapterVolts(_Reply r) {
    if (!r.ok || r.reply.lines.isEmpty) return;
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*V',
      caseSensitive: false,
    ).firstMatch(r.reply.lines.last);
    if (match != null) _adapterVolts = double.tryParse(match.group(1)!);
  }

  // -------------------------------------------------------- waiting for the car

  void _waitForCar() {
    _setPhase(SurveyPhase.waitingForCar);
    _waitingSince = clock.monotonic();
    _say('survey car silent');
    _steps.clear();
    _stepsDone = null;
    _waitAndProbe();
  }

  void _waitAndProbe() {
    final epoch = _epoch;
    _loopTask = scheduler.runAfter(config.waitProbe, () {
      _loopTask = null;
      if (epoch != _epoch || !_running || !_linkUp) return;
      _ask('ATRV', (r) {
        _onAdapterVolts(r);
        _ask('0100', (a) {
          final messages = a.messages;
          if (messages.isNotEmpty) {
            _carBack();
          } else if (clock.monotonic() - _waitingSince > config.giveUpAfter) {
            finish('the car stayed off');
          } else {
            _waitAndProbe();
          }
        });
      });
    });
  }

  void _carBack() {
    final away = clock.monotonic() - _waitingSince;
    _say('survey car back after ${away.inSeconds}s');
    _filter = null;
    if (_probed && _schedule != null) {
      // The adapter may have kept a filter through the ignition cycle: clear
      // it, so that what it listens to is what we think.
      _ask('ATCRA', (_) => _startLoop());
    } else if (_discovered && _ecus.isNotEmpty) {
      _probe();
    } else {
      _identify();
    }
  }

  // ---------------------------------------------------------------- reporting

  void _vitals() {
    final now = clock.monotonic();
    String v(int pid, [int digits = 0]) {
      final live = _live[pid];
      if (live == null || now - live.$2 > const Duration(seconds: 5)) {
        return '-';
      }
      return live.$1.toStringAsFixed(digits);
    }

    _say(
      'survey vitals phase=${_phase.name} req=$_requests ok=$_answered '
      'fail=$_failed rate=${_rate.toStringAsFixed(1)} batch=$_batch '
      'filter=${_filterState.name} rpm=${v(0x0C)} kmh=${v(0x0D)} '
      'volts=${v(0x42, 2)} adapterV=${_adapterVolts?.toStringAsFixed(1) ?? '-'}',
    );
  }

  void _tick() {
    final done = _answered - _answeredAtTick;
    _answeredAtTick = _answered;
    _rate = _rate == 0 ? done.toDouble() : _rate * 0.7 + done * 0.3;
    _publish();
  }

  void _setPhase(SurveyPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    _say('survey phase ${phase.name}');
    _publish();
  }

  void _say(String text) => note?.call(text);

  void _publish() {
    _progress.value = _snapshot();
  }

  SurveyProgress _snapshot() {
    final now = clock.monotonic();
    double? fresh(int pid) {
      final live = _live[pid];
      if (live == null || now - live.$2 > const Duration(seconds: 5)) {
        return null;
      }
      return live.$1;
    }

    var available = 0;
    final union = <int>{};
    for (final set in _supported.values) {
      union.addAll(set.where((p) => !Mode01Lengths.isSupportMask(p)));
    }
    available = union.length;
    return SurveyProgress(
      phase: _phase,
      elapsed: _running || _finished ? now - _startedAt : Duration.zero,
      requests: _requests,
      answered: _answered,
      failed: _failed,
      answersPerSecond: _rate,
      ecus: List.unmodifiable(_ecus),
      pidsSeen: _seen.length,
      pidsAvailable: available,
      batch: _batch,
      filter: _filterState,
      rpm: fresh(0x0C),
      speedKmh: fresh(0x0D),
      volts: fresh(0x42),
      adapterVolts: _adapterVolts,
      linkDrops: _linkDrops,
      detail: _detail,
    );
  }

  static String _hex2(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(2, '0');
}

/// One command of the discovery or the probe, and what to do with its reply.
class _Step {
  _Step(this.command, this.handle, {this.when});

  /// The command, made when it is sent, since whether to ask for one answer or
  /// several depends on what has been found by then.
  final String Function() command;
  final void Function(_Reply reply) handle;

  /// If set, the step is skipped when this says no.
  final bool Function()? when;
}

class _Reply {
  const _Reply(this.reply, this.messages);

  final Elm327Reply reply;
  final List<HeadedMessage> messages;

  bool get ok => reply.ok;
  bool get hasLines => reply.lines.isNotEmpty;
}
