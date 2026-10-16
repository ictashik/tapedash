import 'mode01_lengths.dart';

/// How often a survey wants a PID, by what it is for.
enum SurveyTier {
  /// What the engine is doing right now: revs, speed, throttle, load, air and
  /// the battery voltage. Read as often as the link allows.
  core,

  /// Sensors and the ECU's own commands that move with the engine: ignition
  /// timing, air-fuel ratio, trims, pedal and throttle, manifold pressure.
  fast,

  /// Temperatures, pressures and counters that drift.
  medium,

  /// Everything else: status words and odometer-like counts.
  still,
}

/// The tiers of the standard Mode 01 PIDs (SAE J1979). A PID not named here, or
/// one a manufacturer added, is [SurveyTier.still].
abstract final class SurveyPids {
  static const Set<int> _core = {0x0C, 0x0D, 0x11, 0x10, 0x04, 0x42};

  static const Set<int> _fast = {
    0x03, 0x06, 0x07, 0x0B, 0x0E, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, //
    0x1A, 0x1B, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x34, //
    0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x43, 0x44, 0x45, 0x47, //
    0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x5E, 0x61, 0x62, 0x63,
  };

  static const Set<int> _medium = {
    0x05, 0x0F, 0x1F, 0x2E, 0x2F, 0x33, 0x3C, 0x3D, 0x3E, 0x3F, 0x46, //
    0x5C,
  };

  static SurveyTier tierOf(int pid) {
    if (_core.contains(pid)) return SurveyTier.core;
    if (_fast.contains(pid)) return SurveyTier.fast;
    if (_medium.contains(pid)) return SurveyTier.medium;
    return SurveyTier.still;
  }
}

/// How a survey paces itself.
class SurveyConfig {
  const SurveyConfig({
    this.maxBatch = 6,
    this.coreEvery = const Duration(milliseconds: 400),
    this.fastEvery = const Duration(seconds: 2),
    this.mediumEvery = const Duration(seconds: 10),
    this.stillEvery = const Duration(seconds: 60),
    this.crossCheckEvery = const Duration(seconds: 30),
    this.vitalsEvery = const Duration(seconds: 5),
    this.adapterVoltsEvery = const Duration(seconds: 5),
    this.silentAfter = 8,
    this.waitProbe = const Duration(seconds: 2),
    this.giveUpAfter = const Duration(minutes: 30),
    this.firstRetry = const Duration(seconds: 1),
    this.longestRetry = const Duration(seconds: 10),
    this.settle = const Duration(milliseconds: 300),
    this.maxMonitorIds = 48,
    this.batchStrikes = 3,
    this.batchRegrowAfter = 150,
    this.suspendAfterMisses = 5,
    this.suspendFor = const Duration(seconds: 60),
    this.switchWhenOverdue = 2.0,
  });

  /// The most PIDs in one request. Six is the limit of the standard.
  final int maxBatch;

  final Duration coreEvery;
  final Duration fastEvery;
  final Duration mediumEvery;
  final Duration stillEvery;

  /// How often a PID that two ECUs both have is read from the one that is not
  /// the main source, to see whether they agree.
  final Duration crossCheckEvery;

  /// How often the survey writes a line about itself into the log.
  final Duration vitalsEvery;

  /// How often it asks the adapter what voltage it sees at the OBD socket
  /// (`ATRV`), which it can answer with the ECU asleep.
  final Duration adapterVoltsEvery;

  /// This many failed requests in a row, and none answered in the last few
  /// seconds, means the car has gone quiet: the ignition went off.
  final int silentAfter;

  /// How often the car is asked whether it is back.
  final Duration waitProbe;

  /// How long a car that does not answer is waited for before the survey ends.
  final Duration giveUpAfter;

  final Duration firstRetry;
  final Duration longestRetry;
  final Duration settle;

  /// The most Mode 06 test results asked for from an ECU.
  final int maxMonitorIds;

  /// This many failed batches in a row halve the batch size.
  final int batchStrikes;

  /// This many answered batches in a row, below the maximum, double it again.
  final int batchRegrowAfter;

  /// A PID the ECU says it has, and then does not answer this many times in a
  /// row, is left alone for [suspendFor].
  final int suspendAfterMisses;
  final Duration suspendFor;

  /// Changing the ECU the adapter listens to costs two commands (there and
  /// back), about as long as a whole request each. So the survey stays on an
  /// ECU while it has anything much due, and leaves only for an ECU that is
  /// this many times overdue.
  final double switchWhenOverdue;

  Duration periodOf(SurveyTier tier) => switch (tier) {
    SurveyTier.core => coreEvery,
    SurveyTier.fast => fastEvery,
    SurveyTier.medium => mediumEvery,
    SurveyTier.still => stillEvery,
  };
}

/// One PID on one ECU, and when it was last read.
class SurveyItem {
  SurveyItem(this.ecu, this.pid, this.period);

  final String ecu;
  final int pid;

  /// How often it is wanted.
  final Duration period;

  Duration? lastRead;
  int reads = 0;
  int misses = 0;
  Duration? suspendedUntil;

  /// How overdue it is: 1 means it is due now, 2 that it is twice as late as it
  /// should be. One never read is more overdue than any that has been.
  double urgency(Duration now) {
    final last = lastRead;
    if (last == null) return 1e9;
    return (now - last).inMicroseconds / period.inMicroseconds;
  }

  @override
  String toString() => 'SurveyItem($ecu ${pid.toRadixString(16)} x$reads)';
}

/// A request to send: PIDs from one ECU.
class SurveyRequest {
  const SurveyRequest(this.ecu, this.pids);

  final String ecu;
  final List<int> pids;

  @override
  String toString() =>
      'SurveyRequest($ecu ${pids.map((p) => p.toRadixString(16)).join(',')})';
}

/// Which PIDs to ask for next (the survey's drive loop).
///
/// Every request reads as many PIDs as the batch size allows, since a request
/// for six costs hardly more time than one for a single PID on the adapters
/// seen so far (172 ms against 141), and the PIDs it picks are the ones that
/// are most overdue for their tier. Swapping to another ECU costs two commands
/// (there and back), so it stays on one until the other is
/// [SurveyConfig.switchWhenOverdue] times overdue; a first visit to a small ECU
/// then reads everything of its that is due, not one PID.
class SurveySchedule {
  SurveySchedule(this.items);

  /// The schedule for ECUs with these PIDs ([supported] by the ECU's ID).
  ///
  /// A PID that several ECUs have is read from the one with the most PIDs; the
  /// others have it only as a cross-check, at [SurveyConfig.crossCheckEvery].
  /// PIDs that only ask which others exist (00, 20...) are not read here.
  factory SurveySchedule.build(
    Map<String, Set<int>> supported,
    SurveyConfig config,
  ) {
    final main = <int, String>{};
    final byCount = supported.keys.toList()
      ..sort((a, b) => supported[b]!.length.compareTo(supported[a]!.length));
    for (final ecu in byCount) {
      for (final pid in supported[ecu]!) {
        main.putIfAbsent(pid, () => ecu);
      }
    }
    final items = <SurveyItem>[];
    for (final ecu in supported.keys) {
      for (final pid in supported[ecu]!.toList()..sort()) {
        if (Mode01Lengths.isSupportMask(pid)) continue;
        final tier = SurveyPids.tierOf(pid);
        if (main[pid] == ecu) {
          items.add(SurveyItem(ecu, pid, config.periodOf(tier)));
        } else if (tier == SurveyTier.core) {
          items.add(SurveyItem(ecu, pid, config.crossCheckEvery));
        }
      }
    }
    return SurveySchedule(items);
  }

  final List<SurveyItem> items;

  /// The ECUs in the schedule.
  Set<String> get ecus => {for (final i in items) i.ecu};

  /// The next request, or null if there is nothing to ask. [stayOn] is the ECU
  /// the adapter is listening to now.
  SurveyRequest? next(
    Duration now, {
    required int maxBatch,
    String? stayOn,
    double switchWhenOverdue = 2.0,
  }) {
    final live = [
      for (final i in items)
        if (i.suspendedUntil == null || i.suspendedUntil! <= now) i,
    ];
    if (live.isEmpty) return null;

    final best = <String, double>{};
    for (final i in live) {
      final u = i.urgency(now);
      if (u > (best[i.ecu] ?? -1)) best[i.ecu] = u;
    }
    String ecu = best.keys.first;
    for (final e in best.keys) {
      if (best[e]! > best[ecu]!) ecu = e;
    }
    // Stay where the adapter is listening, unless another ECU is far enough
    // behind to be worth the two commands, or there is nothing left to gain
    // here and the other has something due. (Time on this one is not wasted: a
    // request reads whatever is most overdue, due or not.)
    if (stayOn != null && best.containsKey(stayOn) && ecu != stayOn) {
      final here = best[stayOn]!;
      final there = best[ecu]!;
      final leave = there >= switchWhenOverdue || (here < 0.5 && there >= 1.0);
      if (!leave) ecu = stayOn;
    }

    final mine = live.where((i) => i.ecu == ecu).toList()
      ..sort((a, b) => b.urgency(now).compareTo(a.urgency(now)));
    final top = mine.first;
    // A PID whose length is not known cannot be walked in a batch, so it goes
    // on its own.
    if (Mode01Lengths.of(top.pid) == null || maxBatch <= 1) {
      return SurveyRequest(ecu, [top.pid]);
    }
    final pids = <int>[];
    for (final i in mine) {
      if (Mode01Lengths.of(i.pid) == null) continue;
      pids.add(i.pid);
      if (pids.length >= maxBatch) break;
    }
    return SurveyRequest(ecu, pids);
  }

  /// Notes the outcome of [request], sent at [now]: the PIDs in [got] came
  /// back, the others did not.
  void record(
    SurveyRequest request,
    Duration now, {
    required Set<int> got,
    required SurveyConfig config,
  }) {
    for (final pid in request.pids) {
      final item = _find(request.ecu, pid);
      if (item == null) continue;
      // Counted as read either way, so that a PID that is not answered does
      // not come first every time.
      item.lastRead = now;
      if (got.contains(pid)) {
        item.reads++;
        item.misses = 0;
      } else if (++item.misses >= config.suspendAfterMisses) {
        item.suspendedUntil = now + config.suspendFor;
        item.misses = 0;
      }
    }
  }

  /// Puts every PID back in play, for when the car has been asleep.
  void clearSuspensions() {
    for (final i in items) {
      i.suspendedUntil = null;
      i.misses = 0;
    }
  }

  SurveyItem? _find(String ecu, int pid) {
    for (final i in items) {
      if (i.ecu == ecu && i.pid == pid) return i;
    }
    return null;
  }
}
