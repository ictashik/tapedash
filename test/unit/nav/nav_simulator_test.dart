import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/nav/nav_arrows.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/nav/nav_parser.dart';
import 'package:tapedash/nav/nav_simulator.dart';
import 'package:tapedash/nav/nav_state.dart';

/// A drive at [speedMs] along [route], stepped every 100 ms: everything Maps
/// would have done, with when.
List<({double t, double travelled, NavSimEvent event})> _drive(
  NavSimulator sim, {
  double speedMs = 14,
  double seconds = 600,
  DateTime? start,
}) {
  final t0 = start ?? DateTime(2026, 10, 24, 20, 58);
  final out = <({double t, double travelled, NavSimEvent event})>[];
  var travelled = 0.0;
  for (var i = 0; i <= seconds * 10; i++) {
    final t = i / 10;
    final now = t0.add(Duration(milliseconds: i * 100));
    final e = sim.step(travelledM: travelled, speedMs: speedMs, now: now);
    if (e != null) out.add((t: t, travelled: travelled, event: e));
    if (sim.finished) break;
    travelled += speedMs * 0.1;
  }
  return out;
}

Iterable<NavNotification> _posts(
  List<({double t, double travelled, NavSimEvent event})> events,
) => events.map((e) => e.event).whereType<NavPost>().map((p) => p.notification);

void main() {
  const parser = NavParser();
  final now = DateTime(2026, 10, 24, 20, 58);

  group('arrows drawn in code', () {
    test('one distinct picture for each kind of turn', () {
      final ids = {for (final t in NavTurn.values) NavArrows.forTurn(t).id};
      expect(ids, hasLength(NavTurn.values.length));
    });

    test('each is a 126 px mask with something drawn and room round it', () {
      for (final turn in NavTurn.values) {
        final a = NavArrows.forTurn(turn);
        final lit = a.alpha.where((v) => v > 0).length;
        expect(a.width, 126);
        expect(a.alpha.length, 126 * 126);
        expect(lit, greaterThan(500), reason: turn.name);
        expect(lit, lessThan(126 * 126 ~/ 2), reason: turn.name);
        // The first and last rows are clear: the stroke has margin.
        expect(a.alpha.take(126).every((v) => v == 0), isTrue);
        expect(a.alpha.skip(125 * 126).every((v) => v == 0), isTrue);
      }
    });

    test('left is right\'s mirror image, and straight is its own', () {
      final left = NavArrows.forTurn(NavTurn.left);
      final right = NavArrows.forTurn(NavTurn.right);
      final straight = NavArrows.forTurn(NavTurn.straight);
      var different = 0;
      for (var y = 0; y < 126; y++) {
        for (var x = 0; x < 126; x++) {
          if ((left.alpha[y * 126 + x] - right.alpha[y * 126 + 125 - x]).abs() >
              2) {
            different++;
          }
          expect(
            (straight.alpha[y * 126 + x] - straight.alpha[y * 126 + 125 - x])
                .abs(),
            lessThanOrEqualTo(2),
          );
        }
      }
      expect(different, 0);
    });

    test('the same turn is the same picture, with the same name', () {
      expect(
        identical(
          NavArrows.forTurn(NavTurn.left),
          NavArrows.forTurn(NavTurn.left),
        ),
        isTrue,
      );
      expect(NavArrows.forTurn(NavTurn.left).id, startsWith('sim-left-'));
    });
  });

  group('a drive along a route', () {
    final route = NavRoute.zigzag(lengthM: 3000, everyM: 800);

    test(
      'starts with Starting navigation…, then guides, then takes it away',
      () {
        final events = _drive(NavSimulator(route: route), seconds: 400);

        final first = events.first.event as NavPost;
        expect(first.notification.title, 'Starting navigation…');
        expect(parser.parse(first.notification, now).phase, NavPhase.starting);
        expect(events.last.event, isA<NavRemove>());
        expect(events.where((e) => e.event is NavRemove), hasLength(1));
      },
    );

    test('posts every couple of seconds on the move, as Maps was seen to', () {
      final events = _drive(NavSimulator(route: route), seconds: 100);
      final times = [for (final e in events.skip(1)) e.t];
      final gaps = [
        for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
      ];

      // Never longer than the cadence; shorter only where the manoeuvre changed
      // (a post of its own, as Maps makes).
      expect(gaps.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(2.1));
      final short = gaps.where((g) => g < 1.9).length;
      final turnsPassed = route.maneuvers.where((m) => m.atM < 14 * 100).length;
      expect(short, lessThanOrEqualTo(turnsPassed), reason: '$gaps');
      expect(
        gaps.where((g) => g > 1.9),
        hasLength(greaterThan(gaps.length - 3)),
      );
    });

    test('posts rarely when standing', () {
      final events = _drive(
        NavSimulator(route: route),
        speedMs: 0,
        seconds: 60,
      );
      // Starting, and then one every 7 s.
      expect(events.length, inInclusiveRange(8, 10));
    });

    test('is read back as the route says, in the progress shape', () {
      final events = _drive(NavSimulator(route: route), seconds: 400);

      for (final e in events) {
        final event = e.event;
        if (event is! NavPost) continue;
        final s = parser.parse(event.notification, now);
        if (s.phase != NavPhase.guiding) continue;
        expect(s.shape, NavShape.progress);
        // What is left of the route is the route less the distance gone.
        expect(
          s.distanceLeftM,
          closeTo((3000 - e.travelled).clamp(0, 3000), 1),
          reason: 't=${e.t}',
        );
        // The distance to the next turn is Maps' rounding of the truth.
        final next = route.maneuvers.firstWhere((m) => m.atM > e.travelled);
        final truth = next.atM - e.travelled;
        if (s.distanceToTurnM != null) {
          expect(
            s.distanceToTurnM,
            closeTo(truth, truth >= 300 ? 25.01 : 5.01),
          );
        }
        expect(s.arrow, isNotNull);
        expect(s.etaText, isNotNull);
      }
    });

    test('is read back as the route says, in the classic shape', () {
      final events = _drive(
        NavSimulator(route: route, shape: NavShape.classic),
        seconds: 400,
      );

      var guided = 0;
      for (final e in events) {
        final event = e.event;
        if (event is! NavPost) continue;
        final s = parser.parse(event.notification, now);
        if (s.phase != NavPhase.guiding) continue;
        guided++;
        expect(s.shape, NavShape.classic);
        // Maps rounds the distance left to a tenth of a kilometre.
        expect(
          s.distanceLeftM,
          closeTo((3000 - e.travelled).clamp(0, 3000), 51),
        );
        expect(s.timeLeft, isNotNull);
        expect(s.timeLeftIsDerived, isFalse);
        expect(s.instruction, isNotNull);
        expect(s.etaText, endsWith('M'));
      }
      expect(guided, greaterThan(100));
    });

    test('the manoeuvre changes as the car passes it', () {
      final events = _drive(NavSimulator(route: route), seconds: 400);
      final instructions = {
        for (final n in _posts(events))
          if (parser.parse(n, now).phase == NavPhase.guiding)
            parser.parse(n, now).instruction,
      };

      expect(instructions, contains('Turn right onto Cross Rd 1'));
      expect(instructions, contains('Turn left onto Cross Rd 2'));
      expect(instructions, contains('Arrive at the destination'));
    });

    test('counts down in steps of 10 m near the turn, as Maps does', () {
      final events = _drive(NavSimulator(route: route), seconds: 100);
      final near = {
        for (final n in _posts(events))
          if (parser.parse(n, now).distanceToTurnM != null &&
              parser.parse(n, now).distanceToTurnM! < 300)
            parser.parse(n, now).distanceToTurnM!,
      };

      expect(near, isNotEmpty);
      for (final m in near) {
        expect(m % 10, 0, reason: '$m');
      }
      expect(near.any((m) => m % 50 != 0), isTrue, reason: 'finer than 50 m');
    });

    test('gives no distance in the last metres, only the instruction', () {
      final events = _drive(NavSimulator(route: route), seconds: 100);
      final close = [
        for (final e in events)
          if (e.event is NavPost)
            if (parser.parse((e.event as NavPost).notification, now).phase ==
                    NavPhase.guiding &&
                (route.maneuvers.first.atM - e.travelled).abs() < 40 &&
                e.travelled < route.maneuvers.first.atM)
              parser.parse((e.event as NavPost).notification, now),
      ];

      expect(close, isNotEmpty);
      for (final s in close) {
        expect(s.distanceText, isNull);
        expect(s.distanceToTurnM, isNull);
        expect(s.instruction, 'Turn right onto Cross Rd 1');
        expect(s.arrow, isNotNull);
      }
    });

    test('the distance to the turn falls in steps of 50 m at a distance', () {
      final events = _drive(NavSimulator(route: route), seconds: 100);
      final texts = {
        for (final n in _posts(events))
          if (parser.parse(n, now).distanceToTurnM != null)
            parser.parse(n, now).distanceToTurnM!,
      };

      for (final m in texts.where((m) => m >= 300 && m < 1000)) {
        expect(m % 50, 0, reason: '$m');
      }
    });

    test('says Rerouting... and then measures a new route from there', () {
      final sim = NavSimulator(route: route);
      final before = _drive(sim, seconds: 30);
      expect(before.last.event, isA<NavPost>());

      sim.reroute();
      final travelled = 420.0;
      final at = now.add(const Duration(seconds: 31));
      final rerouting = sim.step(travelledM: travelled, speedMs: 14, now: at);

      final n = (rerouting! as NavPost).notification;
      final s = parser.parse(n, at);
      expect(s.phase, NavPhase.rerouting);
      expect(s.message, 'Rerouting...');
      expect(s.arrow, isNull);

      final next = sim.step(
        travelledM: travelled + 28,
        speedMs: 14,
        now: at.add(const Duration(seconds: 2)),
      );
      final posted = (next! as NavPost).notification;
      final g = parser.parse(posted, at);
      // The route is now the rest of it, and the progress starts again.
      expect(g.phase, NavPhase.guiding);
      expect(g.distanceLeftM, closeTo(3000 - travelled - 28, 1));
      expect(posted.progress, 28);
      expect(posted.progressMax, 3000 - travelled.round());
    });

    test('is the same every time', () {
      List<Object?> run() => [
        for (final n in _posts(
          _drive(NavSimulator(route: route), seconds: 200),
        ))
          n.toMap(sendArrowPixels: false),
      ];
      expect(run(), run());
    });

    test('writes a 24 hour clock when asked', () {
      final events = _drive(
        NavSimulator(route: route, twentyFourHour: true),
        seconds: 20,
      );
      final s = parser.parse(
        _posts(events).firstWhere((n) => n.arrow != null),
        now,
      );
      expect(s.etaText, matches(RegExp(r'^\d\d:\d\d$')));
    });
  });
}
