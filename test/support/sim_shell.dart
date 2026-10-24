// The simulator, wired into the app's screens for the widget tests (CLAUDE.md 7,
// 10): a drive shell fed by a simulated car, and a radio factory that hands the
// real drive a simulated adapter. Demo Mode, which used to do the first inside the
// app, was removed on 2026-10-23 (docs/DECISIONS.md); the simulator itself stays,
// as the way every screen is exercised without a car.
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/app/radio_transport_factory.dart';
import 'package:tapedash/app/watch_shell.dart';
import 'package:tapedash/core/clock.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/location/location_source.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/transport/session_sink.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/platform/device_features.dart';
import 'package:tapedash/platform/image_sharer.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_profile.dart';
import 'package:tapedash/sound/voice_host.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/ui/dev/debug_overlay.dart';

import 'sim_drive.dart';
import 'sim_drive_location.dart';

/// The example price a simulated drive uses, in rupees a litre.
const double examplePricePerLitre = 102.5;

/// In-memory services with a price set and the tank full as of [now], so that the
/// money screens and the counted fuel left have something to show.
AppServices exampleServices({TripRepository? trips, DateTime? now}) {
  final services = AppServices.inMemory(
    price: examplePricePerLitre,
    trips: trips,
  );
  if (now != null) {
    final tank = services.setup.value.tankLitres;
    // In memory, so this completes before anything can look.
    services.ledger.recordFillUp(
      at: now,
      litres: tank,
      amount: tank * examplePricePerLitre,
      fullTank: true,
    );
  }
  return services;
}

/// A [DriveShell] fed by a simulated car, which it starts, follows with a
/// simulated GPS, and disposes with itself.
class SimDriveShell extends StatefulWidget {
  const SimDriveShell({
    super.key,
    required this.clock,
    required this.scheduler,
    this.scenario = 'city_stop_go',
    this.profile,
    this.app,
    this.onChangeAdapter,
    this.onSurvey,
    this.phoneHot,
    this.phoneTemperature,
    this.debugRows = const [],
    this.onOpenLab,
    this.soundHost,
    this.sharer,
  });

  final Clock clock;
  final Scheduler scheduler;
  final String scenario;
  final String? profile;

  /// The services. Null uses example ones: a price and a full tank.
  final AppServices? app;
  final VoidCallback? onChangeAdapter;
  final VoidCallback? onSurvey;
  final ValueListenable<bool>? phoneHot;
  final Observable<double?>? phoneTemperature;
  final List<DebugRow> debugRows;
  final VoidCallback? onOpenLab;
  final VoiceHost Function()? soundHost;
  final ImageSharer? sharer;

  @override
  State<SimDriveShell> createState() => SimDriveShellState();
}

class SimDriveShellState extends State<SimDriveShell> {
  late final SimDrive drive = SimDrive(
    clock: widget.clock,
    scheduler: widget.scheduler,
    scenario: widget.scenario,
    profile: widget.profile,
  );
  late final SimDriveLocation location = SimDriveLocation(
    drive: drive,
    scheduler: widget.scheduler,
    clock: widget.clock,
  );
  late final AppServices app =
      widget.app ?? exampleServices(now: widget.clock.now());

  @override
  void dispose() {
    location.dispose();
    drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DriveShell(
    feed: drive,
    clock: widget.clock,
    scheduler: widget.scheduler,
    location: location,
    app: app,
    onChangeAdapter: widget.onChangeAdapter,
    onSurvey: widget.onSurvey,
    phoneHot: widget.phoneHot,
    phoneTemperature: widget.phoneTemperature,
    debugRows: widget.debugRows,
    onOpenLab: widget.onOpenLab,
    soundHost: widget.soundHost,
    sharer: widget.sharer,
  );
}

/// Hands the real drive a simulated adapter in place of a radio: the whole app on
/// a car that is a simulation, through the production path (a `LiveDrive` over an
/// `ObdSession`).
class SimRadioFactory extends RadioTransportFactory {
  SimRadioFactory(this.car, this.clock);

  final SimulatedCar car;
  final Scheduler clock;
  final List<AdapterConfig> made = [];

  /// When set, the adapter cannot be reached: every connection fails, as one to
  /// an adapter that is out of range or switched off does.
  bool unreachable = false;

  @override
  Transport create(AdapterConfig config) {
    made.add(config);
    return unreachable
        ? UnreachableTransport()
        : SimTransport(car: car, scheduler: clock);
  }
}

/// A transport whose adapter is never there.
class UnreachableTransport implements Transport {
  // Nothing is ever delivered, and the streams hold no resource worth closing.
  // ignore: close_sinks
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);
  // ignore: close_sinks
  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  TransportState _current = const TransportState.disconnected();

  /// How many times a connection was tried.
  int attempts = 0;

  void _set(TransportState next) {
    _current = next;
    _states.add(next);
  }

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    attempts++;
    _set(TransportState.connecting);
    _set(
      const TransportState.disconnected(failure: TransportFailure.unreachable),
    );
    throw const TransportException(TransportFailure.unreachable);
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> write(String data) async =>
      throw const TransportException(TransportFailure.notConnected);
}

/// The adapter a simulated app has been given to drive from.
const AdapterConfig simAdapter = AdapterConfig(
  kind: AdapterKind.bluetoothClassic,
  address: '00:1D:A5:00:00:01',
  name: 'OBDII',
);

/// The whole app on a simulated car, through the production path: a chosen
/// adapter whose transport is the simulator, read by a `LiveDrive`. What Demo
/// Mode used to give a widget test without a car, without a mode of its own.
class SimRig {
  SimRig._(this.clock, this.app, this.car, this.factory);

  /// Services with [simAdapter] chosen (unless [adapter] is false) and the cold
  /// open already seen, and a car at the start of [scenario].
  static Future<SimRig> create(
    FakeClock clock, {
    DriveScenario? scenario,
    VehicleProfile? profile,
    bool adapter = true,
    AppServices? services,
  }) async {
    final app = services ?? await AppServices.memory();
    final car = SimulatedCar(
      scenario: scenario ?? DriveScenarios.cityStopGo,
      profile: profile,
      scheduler: clock,
    )..start();
    if (adapter) await app.adapters.choose(simAdapter);
    app.settings.onboarded.value = true;
    return SimRig._(clock, app, car, SimRadioFactory(car, clock));
  }

  final FakeClock clock;
  final AppServices app;
  final SimulatedCar car;
  final SimRadioFactory factory;

  /// The app, over the simulated adapter.
  Widget widget({
    SessionSink? sessionSink,
    DeviceFeatures? device,
    LocationSource? location,
  }) => TapeDashApp(
    clock: clock,
    scheduler: clock,
    services: app,
    transports: factory,
    sessionSink: sessionSink,
    device: device,
    location: location,
    skipColdOpen: true,
  );

  void dispose() => car.stop();
}

/// A [WatchShell] fed by a simulated car, which it starts, follows with a simulated
/// GPS and disposes with itself: the watch's `SimDriveShell`.
class SimWatchShell extends StatefulWidget {
  const SimWatchShell({
    super.key,
    required this.clock,
    required this.scheduler,
    this.scenario = 'city_stop_go',
    this.profile,
    this.app,
    this.device,
    this.onChangeAdapter,
    this.phoneHot,
  });

  final Clock clock;
  final Scheduler scheduler;
  final String scenario;
  final String? profile;
  final AppServices? app;
  final DeviceFeatures? device;
  final VoidCallback? onChangeAdapter;
  final ValueListenable<bool>? phoneHot;

  @override
  State<SimWatchShell> createState() => SimWatchShellState();
}

class SimWatchShellState extends State<SimWatchShell> {
  late final SimDrive drive = SimDrive(
    clock: widget.clock,
    scheduler: widget.scheduler,
    scenario: widget.scenario,
    profile: widget.profile,
  );
  late final SimDriveLocation location = SimDriveLocation(
    drive: drive,
    scheduler: widget.scheduler,
    clock: widget.clock,
  );
  late final AppServices app =
      widget.app ?? exampleServices(now: widget.clock.now());

  @override
  void dispose() {
    location.dispose();
    drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WatchShell(
    feed: drive,
    clock: widget.clock,
    scheduler: widget.scheduler,
    location: location,
    app: app,
    device: widget.device,
    onChangeAdapter: widget.onChangeAdapter,
    phoneHot: widget.phoneHot,
  );
}
