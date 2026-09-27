import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import 'elm327/elm327_client.dart';
import 'elm327/elm327_failure.dart';
import 'pids/pid.dart';

/// How often a PID is read (CLAUDE.md 8.2).
enum PollTier {
  /// Every cycle, as fast as the adapter answers.
  fast,

  /// About once a second.
  medium,

  /// Every few seconds.
  slow,
}

/// The numbers behind the poller.
class PollConfig {
  const PollConfig({
    this.mediumPeriod = const Duration(seconds: 1),
    this.slowPeriod = const Duration(seconds: 4),
    this.maxPidsPerRequest = 6,
    this.batching = true,
    this.batchStrikeLimit = 3,
    this.batchPause = const Duration(seconds: 60),
    this.minRequestInterval = const Duration(milliseconds: 5),
    this.silentAfter = 3,
    this.deadAfter = 5,
  });

  final Duration mediumPeriod;
  final Duration slowPeriod;

  /// The most PIDs in one request: six, which is what a CAN ECU accepts
  /// (SAE J1979).
  final int maxPidsPerRequest;

  /// Whether to ask for several PIDs in one request at all, when the car is on
  /// CAN.
  final bool batching;

  /// How many batched requests in a row can fail before batching is given up
  /// for [batchPause].
  final int batchStrikeLimit;

  /// How long batching stays off after too many failures. Then it is tried
  /// again.
  final Duration batchPause;

  /// The shortest time between one request finishing and the next starting. It
  /// stops a transport that answers at once from being polled in a tight loop.
  final Duration minRequestInterval;

  /// This many requests in a row that the car did not answer (`NO DATA`,
  /// `CAN ERROR`...) is an ECU that has gone quiet.
  final int silentAfter;

  /// This many requests in a row that the adapter did not answer, or answered
  /// with noise, is an adapter or a link that is failing.
  final int deadAfter;

  PollConfig copyWith({bool? batching}) => PollConfig(
    mediumPeriod: mediumPeriod,
    slowPeriod: slowPeriod,
    maxPidsPerRequest: maxPidsPerRequest,
    batching: batching ?? this.batching,
    batchStrikeLimit: batchStrikeLimit,
    batchPause: batchPause,
    minRequestInterval: minRequestInterval,
    silentAfter: silentAfter,
    deadAfter: deadAfter,
  );
}

/// How the polling is going.
enum PollHealth {
  /// The car is answering.
  ok,

  /// The adapter answers, and the car does not: the ignition is off, or the
  /// ECU is asleep.
  ecuSilent,

  /// The adapter is not answering, or only in noise.
  adapterFailing,
}

/// One PID's value, as read from the car.
class PidReading {
  const PidReading({
    required this.pid,
    required this.data,
    required this.value,
    required this.at,
    required this.receivedAt,
    required this.latency,
  });

  final Pid pid;
  final List<int> data;

  /// Decoded, in the sensor's unit.
  final double value;

  /// When it was read: the middle of the request's round trip (DESIGN.md 5.2).
  final Duration at;

  /// When the answer arrived.
  final Duration receivedAt;

  /// The request's round trip, to the data.
  final Duration latency;
}

/// A claim on some PIDs being polled, until it is released.
class PollDemand {
  PollDemand._(this._poller, this._tiers);

  final Poller _poller;
  final Map<int, PollTier> _tiers;
  bool _released = false;

  /// Stops asking for these PIDs. Others may still want them.
  void release() {
    if (_released) return;
    _released = true;
    _poller._demands.remove(this);
  }
}

/// Reads the PIDs that are wanted, in tiers, one request at a time
/// (CLAUDE.md 8.2).
///
/// What is polled is whatever has been demanded and the car supports. Each PID
/// has the fastest tier anyone has demanded for it, so a page that wants the
/// fuel source every cycle just asks, and gives it up when it is done. PIDs that
/// are due go oldest first, so that the fast tier cannot starve the others.
///
/// On CAN, up to six PIDs go in one request, and the request says it expects one
/// answer so the adapter need not wait out its timeout. If a batched request
/// fails, the PIDs are asked for one at a time for a while; if the adapter does
/// not understand batches, they are given up for good; and if batches keep
/// failing, they are paused for a minute and then tried again.
class Poller {
  Poller({
    required this.client,
    required this.scheduler,
    required this.clock,
    required this.supported,
    required this.isCan,
    required this.onReading,
    this.config = const PollConfig(),
  }) : _batching = config.batching && isCan;

  final Elm327Client client;
  final Scheduler scheduler;
  final Clock clock;

  /// The PIDs the car answers.
  final Set<int> supported;

  /// Whether the car is on CAN: only then can PIDs be batched, and only then is
  /// it safe to say how many answers to expect.
  final bool isCan;

  final PollConfig config;

  /// Called with each value read.
  final void Function(PidReading reading) onReading;

  final Set<PollDemand> _demands = {};
  final Map<int, _PidState> _states = {};

  final ObservableValue<PollHealth> _health = ObservableValue(PollHealth.ok);
  final ObservableValue<double> _cycleRate = ObservableValue(0);

  bool _running = false;
  bool _inFlight = false;
  ScheduledTask? _wake;

  final bool _batching;
  bool _batchingRefused = false;
  int _batchStrikes = 0;
  int _singlesLeft = 0;
  Duration? _batchPausedUntil;
  bool _compatibility = false;

  int _seq = 0;
  int _requests = 0;
  int _failures = 0;
  int _silentRun = 0;
  int _deadRun = 0;
  final List<Duration> _fastReads = [];

  /// How the polling is going.
  Observable<PollHealth> get health => _health;

  /// How many times a second the fast tier is being read, over the last few
  /// seconds, for the diagnostics.
  Observable<double> get cycleRate => _cycleRate;

  /// Requests sent.
  int get requestsSent => _requests;

  /// Requests that got no usable answer, or not all of the one asked for.
  int get failedRequests => _failures;

  /// Whether several PIDs are asked for at once when more than one is due.
  bool get isBatching =>
      _batching && !_batchingRefused && !_compatibility && _batchPauseOver();

  /// Whether the adapter has been found not to understand batched requests.
  bool get batchingRefused => _batchingRefused;

  bool get isRunning => _running;

  /// Compatibility mode (CLAUDE.md 8.1): no batching, and a slower pace, for an
  /// adapter that cannot keep up.
  bool get compatibilityMode => _compatibility;

  set compatibilityMode(bool on) {
    if (on == _compatibility) return;
    _compatibility = on;
    client.timing = client.timing.copyWith(
      minGap: on ? const Duration(milliseconds: 40) : Duration.zero,
    );
  }

  /// The tiers of CLAUDE.md 8.2 for the PIDs in [supported]: RPM, speed and
  /// throttle every cycle; load and the fuel source about once a second; and
  /// coolant, intake air, fuel level and voltage every few seconds. The fuel
  /// source is the engine fuel rate if there is one, else MAF, else MAP.
  static Map<int, PollTier> standardTiers(Set<int> supported) {
    final fuel = supported.contains(Pids.fuelRate.id)
        ? Pids.fuelRate
        : supported.contains(Pids.airFlow.id)
        ? Pids.airFlow
        : supported.contains(Pids.manifoldPressure.id)
        ? Pids.manifoldPressure
        : null;
    final tiers = <int, PollTier>{
      Pids.rpm.id: PollTier.fast,
      Pids.speed.id: PollTier.fast,
      Pids.throttle.id: PollTier.fast,
      Pids.load.id: PollTier.medium,
      if (fuel != null) fuel.id: PollTier.medium,
      Pids.coolant.id: PollTier.slow,
      Pids.intakeAir.id: PollTier.slow,
      Pids.fuelLevel.id: PollTier.slow,
      Pids.voltage.id: PollTier.slow,
    };
    return {
      for (final e in tiers.entries)
        if (supported.contains(e.key)) e.key: e.value,
    };
  }

  /// Wants [tiers] polled, each PID at its tier, until the returned demand is
  /// released. A PID the car does not support is left out.
  PollDemand demand(Map<int, PollTier> tiers) {
    final d = PollDemand._(this, Map.of(tiers));
    _demands.add(d);
    if (_running && !_inFlight) {
      // Something new may be due sooner than the wake that is waiting.
      _wake?.cancel();
      _wake = null;
      _kick();
    }
    return d;
  }

  /// The tier at which [pid] is polled now, or null if nobody wants it or the
  /// car does not have it.
  PollTier? tierOf(int pid) {
    if (!supported.contains(pid)) return null;
    PollTier? best;
    for (final d in _demands) {
      final tier = d._tiers[pid];
      if (tier != null && (best == null || tier.index < best.index)) {
        best = tier;
      }
    }
    return best;
  }

  /// Starts polling.
  void start() {
    if (_running) return;
    _running = true;
    _kick();
  }

  /// Stops polling. A request already sent is waited for, and its answer is
  /// thrown away.
  void stop() {
    _running = false;
    _wake?.cancel();
    _wake = null;
  }

  Duration _period(PollTier tier) => switch (tier) {
    PollTier.fast => Duration.zero,
    PollTier.medium => config.mediumPeriod,
    PollTier.slow => config.slowPeriod,
  };

  /// After a PID's first failure it is asked again at once, since a single lost
  /// answer is common. After that it waits, doubling from 100 ms to 2 s, so a
  /// PID that never answers costs one request in a while and not one in every
  /// cycle.
  static Duration _retryDelay(int failStreak) {
    if (failStreak <= 1) return Duration.zero;
    final millis = 100 * (1 << (failStreak - 2).clamp(0, 10));
    return Duration(milliseconds: millis > 2000 ? 2000 : millis);
  }

  bool _batchPauseOver() {
    final until = _batchPausedUntil;
    if (until == null) return true;
    if (clock.monotonic() < until) return false;
    _batchPausedUntil = null;
    _batchStrikes = 0;
    return true;
  }

  _PidState _state(int pid) => _states.putIfAbsent(pid, _PidState.new);

  /// Plans the next request for [delay] from now, unless one is planned.
  void _plan(Duration delay) {
    if (!_running || _inFlight || _wake != null) return;
    _wake = scheduler.runAfter(delay, () {
      _wake = null;
      _next();
    });
  }

  void _kick() => _plan(Duration.zero);

  void _next() {
    if (!_running || _inFlight) return;
    final now = clock.monotonic();

    // What is due, the oldest read first.
    final due = <int>[];
    Duration? soonest;
    for (final pid in supported) {
      if (tierOf(pid) == null) continue;
      final at = _state(pid).nextDue;
      if (at <= now) {
        due.add(pid);
      } else if (soonest == null || at < soonest) {
        soonest = at;
      }
    }
    if (due.isEmpty) {
      // Nothing yet: wake when something is, or when a demand comes.
      if (soonest != null) _plan(soonest - now);
      return;
    }
    // Oldest first, by the order of the reads and not their time: PIDs read in
    // one request share a time, and going by number would let the low ones win
    // every round.
    due.sort((a, b) {
      final byAge = _state(a).lastSeq.compareTo(_state(b).lastSeq);
      return byAge != 0 ? byAge : a.compareTo(b);
    });

    final batch = isBatching && _singlesLeft == 0 && due.length > 1;
    if (_singlesLeft > 0) _singlesLeft--;
    _send(batch ? due.take(config.maxPidsPerRequest).toList() : [due.first]);
  }

  void _send(List<int> pids) {
    _inFlight = true;
    _requests++;
    final batched = pids.length > 1;
    client.request(
      [0x01, ...pids],
      (reply) => _onReply(reply, pids, batched),
      responses: isCan ? 1 : null,
      expectPrefix: batched ? [0x41] : [0x41, pids.single],
    );
  }

  void _onReply(Elm327Reply reply, List<int> asked, bool batched) {
    _inFlight = false;
    if (!_running) return;
    if (reply.failure == Elm327Failure.disconnected) {
      // The link is gone. Whoever owns it starts the polling again once it is
      // back; there is no point asking meanwhile.
      stop();
      return;
    }
    final now = clock.monotonic();
    final found = _read(reply, asked);
    final failure = reply.ok
        ? (found.isEmpty ? Elm327Failure.garbled : null)
        : reply.failure;

    for (final pid in asked) {
      final state = _state(pid)..lastSeq = ++_seq;
      final reading = found[pid];
      if (reading != null) {
        state
          ..failStreak = 0
          ..nextDue = now + _period(tierOf(pid) ?? PollTier.slow);
        _noteFast(reading);
        onReading(reading);
      } else {
        state
          ..failStreak += 1
          ..nextDue = now + _retryDelay(state.failStreak);
      }
    }

    final all = found.length == asked.length;
    if (!all) _failures++;
    _judge(failure, batched: batched, all: all);
    _plan(config.minRequestInterval);
  }

  /// The values in a reply for the PIDs that were asked, from whichever ECU
  /// gave them.
  Map<int, PidReading> _read(Elm327Reply reply, List<int> asked) {
    final found = <int, PidReading>{};
    if (!reply.ok) return found;
    final at = reply.sampleTime ?? reply.sentAt;
    final receivedAt = reply.dataAt ?? reply.completedAt;
    for (final message in reply.messages) {
      final answer = Mode01Answer.parse(message);
      if (answer == null) continue;
      for (final v in answer.values) {
        if (asked.contains(v.pid.id) && !found.containsKey(v.pid.id)) {
          found[v.pid.id] = PidReading(
            pid: v.pid,
            data: v.data,
            value: v.value,
            at: at,
            receivedAt: receivedAt,
            latency: reply.latency ?? Duration.zero,
          );
        }
      }
    }
    return found;
  }

  /// Bookkeeping after a request: the health of the link, and what to do about
  /// batching.
  void _judge(
    Elm327Failure? failure, {
    required bool batched,
    required bool all,
  }) {
    if (failure == null) {
      _silentRun = 0;
      _deadRun = 0;
      _health.value = PollHealth.ok;
    } else if (_carSaidNo(failure)) {
      _silentRun++;
      _deadRun = 0;
      if (_silentRun >= config.silentAfter) {
        _health.value = PollHealth.ecuSilent;
      }
    } else {
      _deadRun++;
      _silentRun = 0;
      if (_deadRun >= config.deadAfter) {
        _health.value = PollHealth.adapterFailing;
      }
    }

    if (!batched) return;
    if (failure == Elm327Failure.unknownCommand) {
      // The adapter does not know a request with several PIDs.
      _batchingRefused = true;
    } else if (all) {
      _batchStrikes = 0;
    } else {
      // Ask for these one at a time for a while, which also gets the values
      // this request failed to bring.
      _singlesLeft = config.maxPidsPerRequest;
      _batchStrikes++;
      if (_batchStrikes >= config.batchStrikeLimit) {
        _batchPausedUntil = clock.monotonic() + config.batchPause;
      }
    }
  }

  /// Failures that mean the car is not there, as against noise or a dead
  /// adapter.
  static bool _carSaidNo(Elm327Failure f) => switch (f) {
    Elm327Failure.noData ||
    Elm327Failure.canError ||
    Elm327Failure.unableToConnect ||
    Elm327Failure.busInitError ||
    Elm327Failure.busBusy ||
    Elm327Failure.busError => true,
    _ => false,
  };

  /// The rate the fast tier is read at: the last ten reads of its first PID by
  /// number, which is RPM when RPM is polled.
  void _noteFast(PidReading reading) {
    if (tierOf(reading.pid.id) != PollTier.fast) return;
    var first = 0xFF;
    for (final pid in supported) {
      if (tierOf(pid) == PollTier.fast && pid < first) first = pid;
    }
    if (reading.pid.id != first) return;
    _fastReads.add(reading.receivedAt);
    if (_fastReads.length > 10) _fastReads.removeAt(0);
    if (_fastReads.length >= 2) {
      final span = _fastReads.last - _fastReads.first;
      if (span > Duration.zero) {
        _cycleRate.value =
            (_fastReads.length - 1) / (span.inMicroseconds / 1e6);
      }
    }
  }
}

/// What the poller remembers about one PID.
class _PidState {
  /// Where this PID came in the order of reads: 0 if it never has.
  int lastSeq = 0;
  Duration nextDue = Duration.zero;
  int failStreak = 0;
}
