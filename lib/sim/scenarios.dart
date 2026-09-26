import 'adapter_quirks.dart';
import 'drive_scenario.dart';
import 'drive_style.dart';
import 'driver.dart';
import 'profiles.dart';
import 'scenario_events.dart';
import 'sim_random.dart';
import 'sim_route.dart';

/// A block of a city route: a straight, then a 90 degree turn at a corner.
class _CityBlock {
  const _CityBlock(this.lengthM, this.turnDegrees, this.stopSeconds, this.kmh);

  final double lengthM;

  /// Positive is left, negative right.
  final double turnDegrees;

  /// How long the driver waits at the corner, at a signal or a sign.
  final double stopSeconds;

  /// The speed an ordinary driver cruises at.
  final double kmh;
}

/// One fixed city route, so the same road can be driven in different ways.
const List<_CityBlock> _cityBlocks = [
  _CityBlock(340, -90, 0, 48),
  _CityBlock(420, 90, 30, 50),
  _CityBlock(280, 90, 0, 45),
  _CityBlock(360, -90, 45, 50),
  _CityBlock(300, -90, 25, 48),
  _CityBlock(450, 90, 0, 50),
  _CityBlock(260, -90, 35, 45),
  _CityBlock(380, 90, 0, 50),
  _CityBlock(330, 90, 40, 48),
  _CityBlock(410, -90, 20, 50),
  _CityBlock(290, 90, 0, 45),
  _CityBlock(370, -90, 30, 50),
  _CityBlock(310, -90, 0, 48),
  _CityBlock(430, 90, 50, 50),
];

/// The radius of a city corner, metres.
const double _cornerRadiusM = 18;

/// A route and the plan for driving it. The plan is built anew for each run,
/// because the legs of a plan are stateful.
class _Plan {
  const _Plan(this.route, this.legs);

  final SimRoute route;
  final List<DriveLeg> Function() legs;
}

/// Lays out a road piece by piece while remembering how far along it is, so
/// the plan can refer to distances along the route.
class _RouteBuilder {
  final List<RouteSegment> _segments = [];
  double distanceM = 0;

  void straight(double lengthM) {
    _segments.add(Straight(lengthM));
    distanceM += lengthM;
  }

  void arc(double radiusM, double turnDegrees) {
    final piece = Arc(radiusM: radiusM, turnDegrees: turnDegrees);
    _segments.add(piece);
    distanceM += piece.lengthM;
  }

  SimRoute build() => SimRoute(List.of(_segments));
}

/// The distances that define one block of a route.
class _BlockPlan {
  const _BlockPlan({
    required this.straightEndM,
    required this.arcEndM,
    required this.block,
  });

  final double straightEndM;
  final double arcEndM;
  final _CityBlock block;
}

/// Adds [count] city blocks to [builder], cycling through the fixed route,
/// and returns where each one ends.
List<_BlockPlan> _addCityBlocks(
  _RouteBuilder builder,
  int count, {
  int firstBlock = 0,
  double? firstBlockLengthM,
}) {
  final plans = <_BlockPlan>[];
  for (var i = 0; i < count; i++) {
    final block = _cityBlocks[(firstBlock + i) % _cityBlocks.length];
    final length = i == 0 && firstBlockLengthM != null
        ? firstBlockLengthM
        : block.lengthM;
    builder.straight(length);
    final straightEnd = builder.distanceM;
    builder.arc(_cornerRadiusM, block.turnDegrees);
    plans.add(
      _BlockPlan(
        straightEndM: straightEnd,
        arcEndM: builder.distanceM,
        block: block,
      ),
    );
  }
  return plans;
}

List<DriveLeg> _cityLegs(
  List<_BlockPlan> plans,
  DriveStyle style, {
  double? cruiseKmh,
  double turnKmh = 20,
}) => [
  for (final plan in plans)
    RouteBlock(
      straightEndM: plan.straightEndM,
      arcEndM: plan.arcEndM,
      cruiseKmh: cruiseKmh ?? plan.block.kmh,
      turnKmh: turnKmh,
      stopSeconds: plan.block.stopSeconds,
      style: style,
    ),
];

_Plan _cityPlan(
  int blocks,
  DriveStyle style, {
  double? cruiseKmh,
  double turnKmh = 20,
  double idleSeconds = 6,
}) {
  final builder = _RouteBuilder();
  final plans = _addCityBlocks(builder, blocks);
  return _Plan(
    builder.build(),
    () => [
      IdleFor(idleSeconds),
      ..._cityLegs(plans, style, cruiseKmh: cruiseKmh, turnKmh: turnKmh),
      StopFor(4, style: style),
    ],
  );
}

/// The road for a highway: long straights with gentle bends.
SimRoute _highwayRoute(double totalM) {
  final builder = _RouteBuilder();
  var sign = 1;
  while (builder.distanceM < totalM) {
    builder.straight(4000);
    builder.arc(1500, 15.0 * sign);
    sign = -sign;
  }
  return builder.build();
}

/// The scripted drives of CLAUDE.md 7.3.
abstract final class DriveScenarios {
  /// Five minutes of idle from cold: the engine starts, the revs settle from
  /// the cold fast idle, and the coolant creeps up.
  static final DriveScenario coldStartIdle = DriveScenario(
    name: 'cold_start_idle',
    description: 'Five minutes of idling from a cold start',
    route: SimRoute.straight(100),
    duration: const Duration(minutes: 5),
    driverBuilder: () => ScriptedDriver([IdleFor(300)]),
  );

  /// Twenty minutes of city driving with traffic signals: up to 50 km/h, and
  /// idling at the signals.
  static final DriveScenario cityStopGo = () {
    final plan = _cityPlan(24, DriveStyle.normal);
    return DriveScenario(
      name: 'city_stop_go',
      description: '20 minutes of city driving with signals, 0 to 50 km/h',
      route: plan.route,
      duration: const Duration(minutes: 20),
      driverBuilder: () => ScriptedDriver(plan.legs()),
    );
  }();

  /// Half an hour at 70 to 100 km/h with a few overtakes.
  static final DriveScenario highwayCruise = () {
    final route = _highwayRoute(70000);
    List<DriveLeg> legs() {
      const overtake = DriveStyle(
        accelerationMs2: 2.0,
        brakeDecelerationMs2: 1.4,
        pedalRatePerSecond: 2.5,
        brakeRatePerSecond: 3,
      );
      return [
        IdleFor(4),
        for (var i = 0; i < 4; i++) ...[
          GoToSpeed(82, holdSeconds: 200 + 30.0 * i),
          GoToSpeed(93, holdSeconds: 120),
          GoToSpeed(104, style: overtake, holdSeconds: 22),
          GoToSpeed(88, holdSeconds: 200),
        ],
      ];
    }

    return DriveScenario(
      name: 'highway_cruise',
      description: '30 minutes at 70 to 100 km/h with a few overtakes',
      route: route,
      duration: const Duration(minutes: 30),
      driverBuilder: () => ScriptedDriver(legs()),
    );
  }();

  static const int _cityRouteBlocks = 12;

  /// Frequent hard accelerations and hard braking on the city route.
  static final DriveScenario aggressiveCity = () {
    final plan = _cityPlan(
      _cityRouteBlocks,
      DriveStyle.hardDriving,
      cruiseKmh: 64,
      turnKmh: 22,
    );
    return DriveScenario(
      name: 'aggressive_city',
      description: 'The city route, driven hard',
      route: plan.route,
      driverBuilder: () => ScriptedDriver(plan.legs()),
    );
  }();

  /// The same route as [aggressiveCity], driven gently. Its cost must come out
  /// clearly lower, which is the premise of the coach.
  static final DriveScenario ecoCity = () {
    final plan = _cityPlan(
      _cityRouteBlocks,
      DriveStyle.gentle,
      cruiseKmh: 45,
      turnKmh: 18,
    );
    return DriveScenario(
      name: 'eco_city',
      description: 'The same city route, driven gently',
      route: plan.route,
      driverBuilder: () => ScriptedDriver(plan.legs()),
    );
  }();

  /// A queue: mostly idling, with the odd crawl forward.
  static final DriveScenario trafficJam = () {
    final random = SimRandom(2024);
    // The pattern is drawn once, so every run has the same jam.
    final crawls = <(double, double, double)>[
      for (var i = 0; i < 40; i++)
        (random.uniform(5, 9), random.uniform(2, 5), random.uniform(20, 65)),
    ];
    return DriveScenario(
      name: 'traffic_jam',
      description: '15 minutes in a queue: long idling with crawling',
      route: SimRoute([const Straight(20000)]),
      duration: const Duration(minutes: 15),
      driverBuilder: () => ScriptedDriver([
        IdleFor(45),
        for (final (kmh, hold, wait) in crawls) ...[
          GoToSpeed(kmh, style: DriveStyle.gentle, holdSeconds: hold),
          StopFor(wait, style: DriveStyle.gentle),
        ],
      ]),
    );
  }();

  /// City, then highway, then city, with the ignition off and on part way. If
  /// the engine is off for under five minutes the trip resumes, and otherwise
  /// it is a new trip (CLAUDE.md 8.6).
  static DriveScenario mixedCommute({
    Duration ignitionOff = const Duration(minutes: 3),
  }) {
    final builder = _RouteBuilder();
    final first = _addCityBlocks(builder, 8);
    builder.straight(23000);
    final highwayEnd = builder.distanceM;
    final second = _addCityBlocks(
      builder,
      8,
      firstBlock: 3,
      firstBlockLengthM: 700,
    );
    final route = builder.build();
    return DriveScenario(
      name: 'mixed_commute',
      description: 'City, highway and city, with the ignition off part way',
      route: route,
      driverBuilder: () => ScriptedDriver([
        IdleFor(6),
        ..._cityLegs(first, DriveStyle.normal),
        StopFor(3),
        IgnitionOffFor(ignitionOff.inMicroseconds / 1e6),
        IdleFor(6),
        RouteCruise(untilDistanceM: highwayEnd, kmh: 92),
        ..._cityLegs(second, DriveStyle.normal),
        StopFor(4),
      ]),
    );
  }

  /// Repeated high-rev pulls and lifts on the sporty manual, for tuning the
  /// needle, trail, peak hold and shift horizon.
  static final DriveScenario spiritedRevs = DriveScenario(
    name: 'spirited_revs',
    description: 'High-rev pulls and lifts on the six-speed manual',
    profile: VehicleProfiles.petrolManualSporty,
    route: SimRoute.straight(60000),
    startCoolantC: 90,
    engineRunningAtStart: true,
    driverBuilder: () => ScriptedDriver([
      IdleFor(4),
      for (var i = 0; i < 8; i++) ...[
        PullTo(118),
        LiftTo(50),
        PullTo(96),
        LiftTo(42),
        GoToSpeed(70, holdSeconds: 3),
      ],
      StopFor(3),
    ]),
  );

  /// A drive with P0420 and P0171 stored.
  static final DriveScenario dtcPresent = () {
    final plan = _cityPlan(8, DriveStyle.normal);
    return DriveScenario(
      name: 'dtc_present',
      description: 'A city drive with P0420 and P0171 stored',
      route: plan.route,
      duration: const Duration(minutes: 5),
      dtcs: const [
        DtcInjection(at: Duration.zero, code: 'P0420'),
        DtcInjection(at: Duration.zero, code: 'P0171'),
      ],
      driverBuilder: () => ScriptedDriver(plan.legs()),
    );
  }();

  /// A flaky adapter: random NO DATA, dropped prompts, garbage, and a
  /// disconnect and reconnect part way.
  static final DriveScenario adapterFlaky = () {
    final plan = _cityPlan(14, DriveStyle.normal);
    return DriveScenario(
      name: 'adapter_flaky',
      description: 'A city drive on a flaky adapter that drops out part way',
      route: plan.route,
      duration: const Duration(minutes: 10),
      quirks: AdapterQuirks.flaky,
      adapterFaults: const [
        AdapterDisconnect(
          at: Duration(minutes: 4),
          outage: Duration(seconds: 15),
        ),
      ],
      driverBuilder: () => ScriptedDriver(plan.legs()),
    );
  }();

  static final List<DriveScenario> all = [
    coldStartIdle,
    cityStopGo,
    highwayCruise,
    aggressiveCity,
    ecoCity,
    trafficJam,
    mixedCommute(),
    spiritedRevs,
    dtcPresent,
    adapterFlaky,
  ];

  /// The scenario called [name], or null.
  static DriveScenario? byName(String name) {
    for (final scenario in all) {
      if (scenario.name == name) return scenario;
    }
    return null;
  }
}
