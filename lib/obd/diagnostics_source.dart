import '../core/observable.dart';
import '../fuel/fuel_estimator.dart' show FuelSource;
import '../vehicle/reading.dart';
import 'dtc/dtc_service.dart';
import 'elm327/elm327_init.dart' show AdapterInfo;

export 'dtc/dtc_service.dart' show DtcClearOutcome, DtcReadResult;
export 'elm327/elm327_init.dart' show AdapterInfo;

/// What the Diagnostics page shows and does (DESIGN.md 7.10), as the page sees
/// it: the adapter, the poll rate, the fuel source, the supply voltage, and the
/// fault codes. It has no transport in it, so a page test gives it a fake, and a
/// drive gives it the current session's.
abstract interface class DiagnosticsSource {
  /// What start-up found, or null before the car has answered.
  Observable<AdapterInfo?> get adapterInfo;

  /// How often the fast tier is being read, per second.
  Observable<double> get pollRate;

  /// Where fuel and money figures come from now.
  Observable<FuelSource> get fuelSource;

  /// The module voltage.
  Observable<Reading?> get voltage;

  /// Reads the stored codes, then the pending ones. With no car to ask, it reports
  /// a failure rather than saying nothing.
  void readCodes(void Function(DtcReadResult result) done);

  /// Clears the codes, which only a car at a standstill accepts.
  void clearCodes(void Function(DtcClearOutcome outcome) done);
}

/// The protocols an adapter can report (`ATDPN`), in words.
String protocolName(String? number) => switch (number) {
  '1' => 'SAE J1850 PWM',
  '2' => 'SAE J1850 VPW',
  '3' => 'ISO 9141-2',
  '4' => 'ISO 14230-4 KWP (slow init)',
  '5' => 'ISO 14230-4 KWP (fast init)',
  '6' => 'ISO 15765-4 CAN, 11-bit, 500 kbaud',
  '7' => 'ISO 15765-4 CAN, 29-bit, 500 kbaud',
  '8' => 'ISO 15765-4 CAN, 11-bit, 250 kbaud',
  '9' => 'ISO 15765-4 CAN, 29-bit, 250 kbaud',
  'A' => 'SAE J1939 CAN',
  _ => 'Not reported',
};
