import '../../core/observable.dart';
import '../../obd/obd_session.dart';
import '../../vehicle/vehicle_state.dart';

/// What the app knows of where its data comes from, and how to steer a demo.
///
/// The UI reads a [VehicleState] and never knows whether a simulated car or a real
/// adapter is behind it: this is the same graph either way (CLAUDE.md 6). Only the
/// controls differ, and a real adapter offers none of the demo ones.
abstract interface class DataSource {
  /// The vehicle, live.
  VehicleState get vehicle;

  /// Whether the data is simulated (Demo Mode) or comes from a real adapter.
  bool get isDemo;

  /// A short name for the deck: "DEMO city_stop_go" or the adapter's name.
  Observable<String> get description;

  /// Where the connection stands.
  Observable<ConnectionStatus> get connection;

  /// How many times a second the fast tier is being read.
  Observable<double> get pollRate;
}

/// A [DataSource] that is a simulated drive, which can be started, stopped and
/// changed (CLAUDE.md 7.6).
abstract interface class DemoControl implements DataSource {
  List<String> get scenarios;
  List<String> get profiles;

  Observable<String> get scenario;
  Observable<String> get profile;

  /// Whether the simulated car is being driven.
  Observable<bool> get running;

  void start();
  void stop();

  /// Starts the current scenario over from the beginning.
  void restart();

  /// Changes the drive and, if given, the car, and starts it over.
  void select({String? scenario, String? profile});
}
