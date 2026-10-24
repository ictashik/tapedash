import 'nav_arrows.dart';
import 'nav_notification.dart';
import 'nav_state.dart';

/// One manoeuvre on a simulated route.
class NavManeuver {
  const NavManeuver({
    required this.atM,
    required this.turn,
    required this.street,
  });

  /// Where along the route it is, in metres.
  final double atM;
  final NavTurn turn;

  /// The street it leads onto, or the destination for the arrival.
  final String street;

  /// What Google Maps says for it, in English.
  String get instruction => switch (turn) {
    NavTurn.left => 'Turn left onto $street',
    NavTurn.right => 'Turn right onto $street',
    NavTurn.straight => 'Continue onto $street',
    NavTurn.uturn => 'Make a U-turn',
    NavTurn.arrive => 'Arrive at $street',
  };
}

/// A route as Maps would plan it: how long it is, and the manoeuvres along it, the
/// last of them the arrival.
class NavRoute {
  NavRoute({required this.lengthM, required List<NavManeuver> maneuvers})
    : maneuvers = List.unmodifiable(maneuvers),
      assert(maneuvers.isNotEmpty),
      assert(maneuvers.last.turn == NavTurn.arrive);

  final double lengthM;
  final List<NavManeuver> maneuvers;

  /// A route with a turn every [everyM] metres, alternating, to arrive at the
  /// end of [lengthM].
  factory NavRoute.zigzag({double lengthM = 6000, double everyM = 900}) {
    final turns = <NavManeuver>[];
    var at = everyM;
    var i = 0;
    while (at < lengthM - 200) {
      turns.add(
        NavManeuver(
          atM: at,
          turn: i.isEven ? NavTurn.right : NavTurn.left,
          street: 'Cross Rd ${i + 1}',
        ),
      );
      at += everyM;
      i++;
    }
    turns.add(
      NavManeuver(
        atM: lengthM,
        turn: NavTurn.arrive,
        street: 'the destination',
      ),
    );
    return NavRoute(lengthM: lengthM, maneuvers: turns);
  }
}

/// What a simulated Maps does at one step of a drive.
sealed class NavSimEvent {
  const NavSimEvent();
}

/// Maps posts, or updates, its notification.
class NavPost extends NavSimEvent {
  const NavPost(this.notification);
  final NavNotification notification;
}

/// Maps takes its notification away.
class NavRemove extends NavSimEvent {
  const NavRemove();
}

/// Google Maps, as far as TapeDash can see it: a route, followed as a car drives
/// it, posting the notification Maps posts (docs/NAV.md).
///
/// It makes what a capture of Google Maps 25.33 showed, and so is only as true as
/// that capture: the two shapes, the 50 m steps in the distance, a post every
/// couple of seconds on the move, the states `Starting navigation…` and
/// `Rerouting...`, the route's progress back to zero on a reroute, and the
/// notification removed at the end. It is in English, in kilometres and metres,
/// and does not know what Maps shows below 100 m, which no capture has reached.
///
/// Feed it [step] as the car moves. It owns no clock: the time is the one passed.
class NavSimulator {
  NavSimulator({
    required this.route,
    this.shape = NavShape.progress,
    this.twentyFourHour = false,
    this.typicalSpeedMs = 10,
    this.movingEvery = const Duration(seconds: 2),
    this.standingEvery = const Duration(seconds: 7),
  });

  final NavRoute route;
  final NavShape shape;
  final bool twentyFourHour;

  /// The speed Maps plans the ETA at.
  final double typicalSpeedMs;
  final Duration movingEvery;
  final Duration standingEvery;

  /// Maps drops the distance when the turn is this close.
  static const _noDistanceUnderM = 45.0;

  bool _started = false;
  bool _finished = false;
  bool _reroute = false;
  int _maneuver = 0;
  DateTime? _lastPost;

  // After a reroute Maps measures the new route from where the car was.
  double _routeStartM = 0;

  /// Whether the route is done and the notification has been taken away.
  bool get finished => _finished;

  /// Maps loses the way: its next post is `Rerouting...`, and then a new route
  /// from here.
  void reroute() => _reroute = true;

  /// The next thing Maps does, given that the car is [travelledM] along the
  /// route at [speedMs] at [now]; null when it does nothing yet.
  NavSimEvent? step({
    required double travelledM,
    required double speedMs,
    required DateTime now,
  }) {
    if (_finished) return null;

    if (!_started) {
      _started = true;
      _lastPost = now;
      return const NavPost(NavNotification(title: 'Starting navigation…'));
    }

    if (_reroute) {
      _reroute = false;
      _routeStartM = travelledM;
      _lastPost = now;
      return const NavPost(
        NavNotification(title: 'Rerouting...', subText: 'Arrive '),
      );
    }

    if (travelledM >= route.lengthM) {
      _finished = true;
      return const NavRemove();
    }

    // The next manoeuvre ahead of the car.
    final before = _maneuver;
    while (_maneuver < route.maneuvers.length - 1 &&
        route.maneuvers[_maneuver].atM <= travelledM) {
      _maneuver++;
    }

    final every = speedMs > 1.4 ? movingEvery : standingEvery;
    final due = now.difference(_lastPost!) >= every;
    if (!due && _maneuver == before) return null;

    _lastPost = now;
    return NavPost(_notification(travelledM, now));
  }

  NavNotification _notification(double travelledM, DateTime now) {
    final next = route.maneuvers[_maneuver];
    final toTurnM = (next.atM - travelledM).clamp(0.0, double.infinity);
    final leftM = (route.lengthM - travelledM).clamp(0.0, route.lengthM);
    final arrival = now.add(
      Duration(seconds: (leftM / typicalSpeedMs).round()),
    );
    final distance = _distanceText(toTurnM);
    final progress = (travelledM - _routeStartM).round();
    final progressMax = (route.lengthM - _routeStartM).round();
    final arrow = NavArrows.forTurn(next.turn);

    if (shape == NavShape.progress) {
      return NavNotification(
        title: toTurnM >= _noDistanceUnderM
            ? '$distance · ${next.instruction}'
            : next.instruction,
        subText: 'Arrive ${_clock(arrival)}',
        shortCriticalText: toTurnM >= _noDistanceUnderM ? distance : '',
        progress: progress,
        progressMax: progressMax,
        template: 'android.app.Notification\$ProgressStyle',
        arrow: arrow,
      );
    }
    return NavNotification(
      title: distance,
      text: next.instruction,
      subText:
          '${_duration(Duration(seconds: (leftM / typicalSpeedMs).round()))} '
          '· ${_kilometres(leftM)} · ${_clock(arrival)} ETA',
      progress: 0,
      progressMax: 0,
      arrow: arrow,
    );
  }

  /// The distance as Maps rounds it (a capture of Maps 25.33 counting down): tenths
  /// of a kilometre from a kilometre, steps of 50 m down to about 300 m, steps of
  /// 10 m below that. Under about 45 m it gives no distance, only the instruction
  /// (the HUD takes that for the turn itself).
  static String _distanceText(double metres) {
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }
    final step = metres >= 300 ? 50 : 10;
    final rounded = (metres / step).round() * step;
    return '$rounded m';
  }

  static String _kilometres(double metres) =>
      '${(metres / 1000).toStringAsFixed(1)} km';

  static String _duration(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  String _clock(DateTime t) {
    final m = t.minute.toString().padLeft(2, '0');
    if (twentyFourHour) return '${t.hour.toString().padLeft(2, '0')}:$m';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}
