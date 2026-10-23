import '../core/observable.dart';
import '../obd/obd_session.dart';
import '../vehicle/vehicle_state.dart';

/// What the drive screens read from, whether the car is a real one on an adapter
/// or a simulated one (a test): a [VehicleState], the connection's state, and the
/// OBD session behind them. The UI never knows which (CLAUDE.md 6).
abstract interface class DriveFeed {
  VehicleState get vehicle;

  Observable<ConnectionStatus> get connection;

  /// The OBD session reading the car, replaced whenever the drive starts over or
  /// the link is opened afresh. Null before [start].
  Observable<ObdSession?> get sessions;

  /// How often the fast tier is being read.
  Observable<double> get pollRate;

  /// A short name for the status line: the adapter's name.
  Observable<String> get description;

  /// Starts reading the car. A no-op if it is already started.
  void start();
}
