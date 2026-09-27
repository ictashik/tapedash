import 'package:tapedash/sim/ecu.dart';

/// An ECU that answers Mode 01 from a table of PID data, which a test can
/// change while it runs: a PID that is not in the table is not supported, and
/// one in [silent] is advertised but never answered.
class TableEcu implements ObdEcu {
  TableEcu(this.data, {this.awake = true, this.volts = 12.4});

  /// The data bytes of each supported PID.
  final Map<int, List<int>> data;

  /// PIDs the ECU is asked for, and never answers.
  final Set<int> silent = {};

  bool awake;
  double volts;

  /// When set, a request for several PIDs is answered with the first supported
  /// one only, as some ECUs do.
  bool answerOnlyFirst = false;

  /// Every request that reached the ECU.
  final List<List<int>> requests = [];

  @override
  bool get isAwake => awake;

  @override
  double get batteryVolts => volts;

  @override
  List<int>? respond(List<int> request) {
    requests.add(List.of(request));
    if (!awake || request.length < 2 || request.first != 0x01) return null;
    final reply = <int>[0x41];
    var count = 0;
    for (final pid in request.skip(1)) {
      final bytes = data[pid];
      if (bytes == null || silent.contains(pid)) continue;
      reply
        ..add(pid)
        ..addAll(bytes);
      count++;
      if (answerOnlyFirst) break;
    }
    return count == 0 ? null : reply;
  }
}
