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
    this.noReceiveFilter = false,
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

  /// `ATCRA`, which makes the adapter listen to one ECU, is not understood and
  /// gets `?`.
  final bool noReceiveFilter;

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

  /// A cheap BLE adapter as met on the first real drive: about 1.3 poll cycles a
  /// second. The BLE hop and the adapter's own pace make each command 150 to 250
  /// ms, and it does not take a request for several PIDs, so every PID is a
  /// round trip of its own.
  static const AdapterQuirks slowBle = AdapterQuirks(
    latency: Duration(milliseconds: 160),
    jitter: Duration(milliseconds: 60),
    ignoreAdaptiveTiming: true,
    noMultiPid: true,
  );

  /// The BLE adapter of the first real drives, as its recordings measured it:
  /// 141 ms for a request, and 172 ms for one with several PIDs, so it does
  /// take them (the `slowBle` guess was that it did not).
  static const AdapterQuirks measuredBle = AdapterQuirks(
    latency: Duration(milliseconds: 140),
    jitter: Duration(milliseconds: 6),
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

  /// The presets by the name used on the command line of the tools.
  static const Map<String, AdapterQuirks> presets = {
    'none': none,
    'bluetooth_clone': bluetoothClone,
    'slow_ble': slowBle,
    'measured_ble': measuredBle,
    'flaky': flaky,
  };

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
      if (noReceiveFilter) 'no receive filter',
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
    bool? noReceiveFilter,
    double? noDataRate,
    double? missingPromptRate,
    double? garbageRate,
  }) => AdapterQuirks(
    latency: latency ?? this.latency,
    jitter: jitter ?? this.jitter,
    dropFirstCommand: dropFirstCommand ?? this.dropFirstCommand,
    ignoreAdaptiveTiming: ignoreAdaptiveTiming ?? this.ignoreAdaptiveTiming,
    noMultiPid: noMultiPid ?? this.noMultiPid,
    noReceiveFilter: noReceiveFilter ?? this.noReceiveFilter,
    noDataRate: noDataRate ?? this.noDataRate,
    missingPromptRate: missingPromptRate ?? this.missingPromptRate,
    garbageRate: garbageRate ?? this.garbageRate,
  );
}
