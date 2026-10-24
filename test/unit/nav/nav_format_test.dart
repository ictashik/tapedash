import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/nav/nav_format.dart';
import 'package:tapedash/nav/nav_state.dart';

NavState _state({
  String? distanceText,
  double? distanceLeftM,
  Duration? timeLeft,
  String? etaText,
  bool imperial = false,
}) => NavState(
  phase: NavPhase.guiding,
  receivedAt: DateTime(2026),
  distanceText: distanceText,
  distanceLeftM: distanceLeftM,
  timeLeft: timeLeft,
  etaText: etaText,
  imperial: imperial,
);

void main() {
  group('the distance to the turn', () {
    test('is Maps\' number and its unit as a label', () {
      expect(
        NavFormat.distanceToTurn(_state(distanceText: '650 m')),
        const NavFigure('650', 'M'),
      );
      expect(
        NavFormat.distanceToTurn(_state(distanceText: '1.2 km')),
        const NavFigure('1.2', 'KM'),
      );
      expect(
        NavFormat.distanceToTurn(_state(distanceText: '0.3 mi')),
        const NavFigure('0.3', 'MI'),
      );
      expect(
        NavFormat.distanceToTurn(_state(distanceText: '0 m')),
        const NavFigure('0', 'M'),
      );
    });

    test('keeps a decimal comma as Maps wrote it', () {
      expect(
        NavFormat.distanceToTurn(_state(distanceText: '1,2 km')),
        const NavFigure('1,2', 'KM'),
      );
    });

    test('is Google\'s own text when it is in a unit it could not read', () {
      final unit = String.fromCharCodes([0x0CAE, 0x0CC0]);
      expect(
        NavFormat.distanceToTurn(_state(distanceText: '650 $unit')),
        NavFigure('650', unit.toUpperCase()),
      );
      expect(
        NavFormat.distanceToTurn(_state(distanceText: 'very soon')),
        const NavFigure('very soon'),
      );
    });

    test('is nothing when there is none', () {
      expect(NavFormat.distanceToTurn(_state()), isNull);
      expect(NavFormat.distanceToTurn(_state(distanceText: '  ')), isNull);
    });
  });

  group('the distance left', () {
    test('tenths of a kilometre under a hundred, whole above', () {
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 6700)),
        const NavFigure('6.7', 'KM'),
      );
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 99900)),
        const NavFigure('99.9', 'KM'),
      );
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 124400)),
        const NavFigure('124', 'KM'),
      );
    });

    test('metres in steps of 50 under a kilometre, of 10 under a hundred', () {
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 730)),
        const NavFigure('750', 'M'),
      );
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 60)),
        const NavFigure('60', 'M'),
      );
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 949)),
        const NavFigure('950', 'M'),
      );
    });

    test('a kilometre when it is nearly one', () {
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 960)),
        const NavFigure('1.0', 'KM'),
      );
    });

    test('in miles and feet when Maps wrote in them', () {
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 6700, imperial: true)),
        const NavFigure('4.2', 'MI'),
      );
      expect(
        NavFormat.distanceLeft(_state(distanceLeftM: 120, imperial: true)),
        const NavFigure('400', 'FT'),
      );
    });

    test('is nothing when Maps did not say', () {
      expect(NavFormat.distanceLeft(_state()), isNull);
    });
  });

  group('the time left', () {
    test('is whole minutes under an hour', () {
      expect(
        NavFormat.timeLeft(_state(timeLeft: const Duration(minutes: 26))),
        const NavFigure('26', 'MIN'),
      );
      expect(
        NavFormat.timeLeft(_state(timeLeft: const Duration(seconds: 1590))),
        const NavFigure('27', 'MIN'),
      );
    });

    test('is hours and minutes from an hour', () {
      expect(
        NavFormat.timeLeft(_state(timeLeft: const Duration(minutes: 65))),
        const NavFigure('1:05', 'H'),
      );
      expect(
        NavFormat.timeLeft(_state(timeLeft: const Duration(hours: 3))),
        const NavFigure('3:00', 'H'),
      );
    });

    test('is never nought: the last minute is one', () {
      expect(
        NavFormat.timeLeft(_state(timeLeft: Duration.zero)),
        const NavFigure('1', 'MIN'),
      );
      expect(
        NavFormat.timeLeft(_state(timeLeft: const Duration(seconds: 20))),
        const NavFigure('1', 'MIN'),
      );
    });

    test('is nothing when there is none', () {
      expect(NavFormat.timeLeft(_state()), isNull);
    });
  });

  group('the ETA', () {
    test('takes AM and PM off as a label', () {
      expect(
        NavFormat.eta(_state(etaText: '9:25 PM')),
        const NavFigure('9:25', 'PM'),
      );
      expect(
        NavFormat.eta(_state(etaText: '9:25 am')),
        const NavFigure('9:25', 'AM'),
      );
      expect(
        NavFormat.eta(_state(etaText: '9:25 p.m.')),
        const NavFigure('9:25', 'PM'),
      );
    });

    test('has no label on a 24 hour clock', () {
      expect(NavFormat.eta(_state(etaText: '21:25')), const NavFigure('21:25'));
    });

    test('is nothing when there is none', () {
      expect(NavFormat.eta(_state()), isNull);
      expect(NavFormat.eta(_state(etaText: ' ')), isNull);
    });
  });
}
