import '../core/observable.dart';
import '../obd/obd_session.dart';
import '../vehicle/vehicle_state.dart';

/// What the drive screens read from, whether the car is a simulated one (Demo
/// Mode) or a real one on an adapter: a [VehicleState], the connection's state,
/// and the OBD session behind them. The UI never knows which (CLAUDE.md 6).
abstract interface class DriveFeed {
  VehicleState get vehicle;

  /// Whether the data is simulated.
  bool get isDemo;

  Observable<ConnectionStatus> get connection;

  /// The OBD session reading the car, replaced whenever the drive starts over or
  /// the link is opened afresh. Null before [start].
  Observable<ObdSession?> get sessions;

  /// How often the fast tier is being read.
  Observable<double> get pollRate;

  /// A short name for the status line: "DEMO city_stop_go" or the adapter's name.
  Observable<String> get description;

  /// Starts reading the car. A no-op if it is already started.
  void start();
}
