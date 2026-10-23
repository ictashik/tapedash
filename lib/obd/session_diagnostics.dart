import '../core/observable.dart';
import '../fuel/fuel_estimator.dart';
import '../vehicle/reading.dart';
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'diagnostics_source.dart';
import 'elm327/elm327_failure.dart';
import 'obd_session.dart';

/// [DiagnosticsSource] over whichever OBD session is current. A drive can start
/// over with a new session (a simulated drive loops, a real adapter reconnects with a fresh
/// one), and this follows it, so the page listens to one set of values throughout.
class SessionDiagnostics implements DiagnosticsSource {
  SessionDiagnostics({
    required this.sessions,
    required this.estimator,
    required this.vehicle,
  }) {
    sessions.addListener(_rebind);
    _rebind();
  }

  final Observable<ObdSession?> sessions;
  final FuelEstimator estimator;
  final VehicleState vehicle;

  final ObservableValue<AdapterInfo?> _info = ObservableValue(null);
  final ObservableValue<double> _rate = ObservableValue(0);
  ObdSession? _bound;

  @override
  Observable<AdapterInfo?> get adapterInfo => _info;

  @override
  Observable<double> get pollRate => _rate;

  @override
  Observable<FuelSource> get fuelSource => estimator.source;

  @override
  Observable<Reading?> get voltage => vehicle.reading(Sensor.voltage);

  void _rebind() {
    _bound?.adapterInfo.removeListener(_onInfo);
    _bound?.pollRate.removeListener(_onRate);
    final session = sessions.value;
    _bound = session;
    session?.adapterInfo.addListener(_onInfo);
    session?.pollRate.addListener(_onRate);
    _onInfo();
    _onRate();
  }

  void _onInfo() => _info.value = _bound?.adapterInfo.value;

  void _onRate() => _rate.value = _bound?.pollRate.value ?? 0;

  @override
  void readCodes(void Function(DtcReadResult result) done) {
    final dtc = _bound?.dtc;
    if (dtc == null) {
      done(const DtcReadResult(failure: Elm327Failure.noData));
      return;
    }
    dtc.read(done);
  }

  @override
  void clearCodes(void Function(DtcClearOutcome outcome) done) {
    final dtc = _bound?.dtc;
    if (dtc == null) {
      done(DtcClearOutcome.failed);
      return;
    }
    dtc.clear(done);
  }

  void dispose() {
    sessions.removeListener(_rebind);
    _bound?.adapterInfo.removeListener(_onInfo);
    _bound?.pollRate.removeListener(_onRate);
    _info.dispose();
    _rate.dispose();
  }
}
