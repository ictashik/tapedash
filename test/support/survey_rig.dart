import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/survey/survey_log_reader.dart';
import 'package:tapedash/obd/survey/survey_runner.dart';
import 'package:tapedash/obd/survey/survey_schedule.dart';
import 'package:tapedash/obd/transport/recording_transport.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_profile.dart';

/// A short drive for survey tests: the engine idling, the ignition off for a
/// while, then idling again, and the adapter link dropping if asked.
DriveScenario surveyScenario({
  double idleFirst = 60,
  double ignitionOff = 0,
  double idleAfter = 60,
  AdapterQuirks quirks = AdapterQuirks.none,
  List<AdapterFault> faults = const [],
}) => DriveScenario(
  name: 'survey_test',
  description: 'idle, maybe ignition off, idle',
  route: SimRoute.straight(1000),
  engineRunningAtStart: true,
  startCoolantC: 85,
  quirks: quirks,
  adapterFaults: faults,
  driverBuilder: () => ScriptedDriver([
    IdleFor(idleFirst),
    if (ignitionOff > 0) ...[IgnitionOffFor(ignitionOff), IdleFor(idleAfter)],
  ]),
);

/// A survey on a simulated car, on a fake clock, with its conversation
/// recorded.
class SurveyRig {
  SurveyRig({
    DriveScenario? scenario,
    VehicleProfile profile = VehicleProfiles.surveyTwin,
    AdapterQuirks quirks = AdapterQuirks.measuredBle,
    SurveyConfig config = const SurveyConfig(),
    int seed = 1,
    Transport Function(Transport sim)? wrap,
  }) {
    car = SimulatedCar(
      scenario: scenario ?? surveyScenario(),
      profile: profile,
      seed: seed,
      scheduler: clock,
    )..start();
    transport = SimTransport(
      car: car,
      scheduler: clock,
      quirks: quirks,
      seed: seed,
    );
    recorder = RecordingTransport(
      wrap == null ? transport : wrap(transport),
      clock: clock,
      header: const {'survey': '1'},
    );
    runner = SurveyRunner(
      transport: recorder,
      clock: clock,
      scheduler: clock,
      config: config,
      note: recorder.note,
    );
    runner.progress.addListener(() {
      final phase = runner.progress.value.phase;
      if (phases.isEmpty || phases.last.$2 != phase) {
        phases.add((clock.monotonic(), phase));
      }
    });
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimTransport transport;
  late final RecordingTransport recorder;
  late final SurveyRunner runner;

  /// Each phase the survey went through, and when it began.
  final List<(Duration, SurveyPhase)> phases = [];

  void start() => runner.start();

  void run(int seconds) => clock.advance(Duration(seconds: seconds));

  SurveyProgress get progress => runner.progress.value;

  SessionLog get log => recorder.log;

  SurveySummary get summary => SurveyLogReader.read(log);

  List<SurveyPhase> get sequence => [for (final p in phases) p.$2];

  /// The notes the survey wrote, without their `survey ` prefix.
  List<String> get notes => [for (final n in summary.notes) n.$2];

  void close() {
    runner.dispose();
  }
}
