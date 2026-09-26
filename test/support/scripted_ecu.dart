import 'package:tapedash/sim/ecu.dart';

/// An ECU that says exactly what it is told to, so that the adapter's output
/// can be compared with the examples in the ELM327 datasheet, byte for byte.
class ScriptedEcu implements ObdEcu {
  ScriptedEcu(
    this.answers, {
    this.awake = true,
    this.volts = 12.47,
    this.onRespond,
  });

  /// Answers, by request as hex digits without spaces.
  final Map<String, List<int>> answers;
  bool awake;
  double volts;

  /// Every request that reached the ECU.
  final List<List<int>> requests = [];

  /// Called whenever a request reaches the ECU, so a test can note when.
  final void Function(List<int> request)? onRespond;

  @override
  bool get isAwake => awake;

  @override
  double get batteryVolts => volts;

  @override
  List<int>? respond(List<int> request) {
    requests.add(request);
    onRespond?.call(request);
    if (!awake) return null;
    final key = request
        .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join();
    return answers[key];
  }
}

/// The answers the datasheet shows for its own examples.
final Map<String, List<int>> datasheetAnswers = {
  // "01 00": 41 00 BE 1F B8 10
  '0100': [0x41, 0x00, 0xBE, 0x1F, 0xB8, 0x10],
  // "01 05": 41 05 7B
  '0105': [0x41, 0x05, 0x7B],
  // "01 0C": 41 0C 1A F8
  '010C': [0x41, 0x0C, 0x1A, 0xF8],
  // "09 02", the VIN of a CAN car: 014 / 0: 49 02 01 31 44 34 / ...
  '0902': [
    0x49, 0x02, 0x01, 0x31, 0x44, 0x34, //
    0x47, 0x50, 0x30, 0x30, 0x52, 0x35, 0x35,
    0x42, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
  ],
  // "01 04 05 0B 0C": 00A / 0: 41 04 3F 05 44 0B / 1: 21 0C 17 B8 00 00 00
  '0104050B0C': [0x41, 0x04, 0x3F, 0x05, 0x44, 0x0B, 0x21, 0x0C, 0x17, 0xB8],
  // "01 0B 04 0C 05": the same PIDs in another order
  '010B040C05': [0x41, 0x0B, 0x21, 0x04, 0x3F, 0x0C, 0x17, 0xB8, 0x05, 0x44],
  // Mode 03 with three codes: 8 bytes, so two frames
  '03': [0x43, 0x03, 0x04, 0x20, 0x01, 0x71, 0x03, 0x00],
};
