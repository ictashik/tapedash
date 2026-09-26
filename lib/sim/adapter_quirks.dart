/// The ways a cheap adapter misbehaves (CLAUDE.md 7.4).
///
/// The app has to cope with all of these, and the simulator can turn each on.
class AdapterQuirks {
  const AdapterQuirks({
    this.latency = Duration.zero,
    this.jitter = Duration.zero,
    this.dropFirstCommand = false,
    this.ignoreAdaptiveTiming = false,
    this.noMultiPid = false,
    this.noDataRate = 0,
    this.missingPromptRate = 0,
    this.garbageRate = 0,
  });

  /// The time from a command being sent to its answer arriving: a fixed part
  /// plus, for each command, a random part of up to [jitter] either way.
  final Duration latency;
  final Duration jitter;

  /// The first command after connecting is lost. Many clones do this.
  final bool dropFirstCommand;

  /// `ATAT` is accepted but has no effect, so the adapter always waits out the
  /// full timeout after a request that does not say how many replies to expect.
  final bool ignoreAdaptiveTiming;

  /// A request for several PIDs at once is not understood, and gets `?`.
  final bool noMultiPid;

  /// The chance, 0 to 1, that a supported PID is answered with `NO DATA`.
  final double noDataRate;

  /// The chance that an answer arrives without its closing `>` prompt.
  final double missingPromptRate;

  /// The chance that a few garbage bytes are mixed into an answer.
  final double garbageRate;

  /// A well-behaved adapter: instant, and no faults.
  static const AdapterQuirks none = AdapterQuirks();

  /// A typical Bluetooth Classic clone: 40 to 120 ms per command (CLAUDE.md
  /// 7.4), and it ignores adaptive timing.
  static const AdapterQuirks bluetoothClone = AdapterQuirks(
    latency: Duration(milliseconds: 80),
    jitter: Duration(milliseconds: 40),
    ignoreAdaptiveTiming: true,
  );

  /// A flaky one: slow, forgetful, and sometimes silent or noisy.
  static const AdapterQuirks flaky = AdapterQuirks(
    latency: Duration(milliseconds: 80),
    jitter: Duration(milliseconds: 40),
    dropFirstCommand: true,
    ignoreAdaptiveTiming: true,
    noDataRate: 0.04,
    missingPromptRate: 0.01,
    garbageRate: 0.005,
  );

  /// The quirks that are switched on, in a line: `latency 80 ms +/- 40 ms,
  /// drops first command`. `none` if there are none.
  @override
  String toString() {
    final parts = <String>[
      if (latency > Duration.zero || jitter > Duration.zero)
        'latency ${latency.inMilliseconds} ms +/- ${jitter.inMilliseconds} ms',
      if (dropFirstCommand) 'drops first command',
      if (ignoreAdaptiveTiming) 'ignores adaptive timing',
      if (noMultiPid) 'no multi-PID',
      if (noDataRate > 0) 'NO DATA ${_percent(noDataRate)}',
      if (missingPromptRate > 0)
        'missing prompt ${_percent(missingPromptRate)}',
      if (garbageRate > 0) 'garbage ${_percent(garbageRate)}',
    ];
    return parts.isEmpty ? 'none' : parts.join(', ');
  }

  static String _percent(double rate) {
    final percent = rate * 100;
    final text = percent == percent.roundToDouble()
        ? percent.round().toString()
        : percent.toStringAsFixed(1);
    return '$text%';
  }

  AdapterQuirks copyWith({
    Duration? latency,
    Duration? jitter,
    bool? dropFirstCommand,
    bool? ignoreAdaptiveTiming,
    bool? noMultiPid,
    double? noDataRate,
    double? missingPromptRate,
    double? garbageRate,
  }) => AdapterQuirks(
    latency: latency ?? this.latency,
    jitter: jitter ?? this.jitter,
    dropFirstCommand: dropFirstCommand ?? this.dropFirstCommand,
    ignoreAdaptiveTiming: ignoreAdaptiveTiming ?? this.ignoreAdaptiveTiming,
    noMultiPid: noMultiPid ?? this.noMultiPid,
    noDataRate: noDataRate ?? this.noDataRate,
    missingPromptRate: missingPromptRate ?? this.missingPromptRate,
    garbageRate: garbageRate ?? this.garbageRate,
  );
}
