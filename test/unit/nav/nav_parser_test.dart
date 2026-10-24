import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/nav/nav_parser.dart';
import 'package:tapedash/nav/nav_state.dart';

import '../../support/nav_fixtures.dart';

// The phone's clock when the capture was made was a little before 9:25 PM.
final _evening = DateTime(2026, 10, 24, 20, 58);

NavState _parse(NavNotification n, [DateTime? now]) =>
    const NavParser().parse(n, now ?? _evening);

NavNotification _fixture(String title) {
  final all = loadNavFixture('maps_25_33_android16.jsonl');
  return all
      .where((r) => r.notification?.title?.contains(title) ?? false)
      .first
      .notification!;
}

void main() {
  group('the notifications Google Maps 25.33 posted on Android 16', () {
    final records = loadNavFixture('maps_25_33_android16.jsonl');

    test('there are real ones to read', () {
      expect(
        records.where((r) => r.event == 'posted'),
        hasLength(greaterThan(25)),
      );
      expect(records.where((r) => r.event == 'removed'), isNotEmpty);
    });

    test(
      'every one reads without a failure, and a figure it gives is sane',
      () {
        for (final r in records.where((r) => r.event == 'posted')) {
          final s = _parse(r.notification!);
          expect(s.phase, isNot(NavPhase.idle), reason: '${r.raw}');
          if (s.distanceToTurnM != null) {
            expect(s.distanceToTurnM, inInclusiveRange(0, 20000));
          }
          if (s.distanceLeftM != null) {
            expect(s.distanceLeftM, inInclusiveRange(0, 100000));
          }
          if (s.timeLeft != null) {
            expect(s.timeLeft!.isNegative, isFalse);
          }
          // A picture, if the notification had one, comes through.
          expect(s.arrow?.id, r.notification!.arrow?.id);
        }
      },
    );

    test('Starting navigation… is a state with Google\'s own words', () {
      final s = _parse(_fixture('Starting navigation'));
      expect(s.phase, NavPhase.starting);
      expect(s.message, 'Starting navigation…');
      expect(s.arrow, isNull);
      expect(s.distanceText, isNull);
    });

    test('Rerouting... is a state with no picture and no ETA', () {
      final s = _parse(_fixture('Rerouting'));
      expect(s.phase, NavPhase.rerouting);
      expect(s.message, 'Rerouting...');
      expect(s.arrow, isNull);
      expect(s.etaText, isNull);
    });

    test('the classic shape: distance, street, and time, distance and ETA', () {
      final n = loadNavFixture(
        'maps_25_33_android16.jsonl',
      ).firstWhere((r) => r.notification?.title == '0 m').notification!;
      final s = _parse(n);

      expect(s.phase, NavPhase.guiding);
      expect(s.shape, NavShape.classic);
      expect(s.distanceText, '0 m');
      expect(s.distanceToTurnM, 0);
      expect(s.instruction, 'toward Vittal Mallya Rd');
      expect(s.timeLeft, const Duration(minutes: 28));
      expect(s.timeLeftIsDerived, isFalse);
      expect(s.distanceLeftM, closeTo(6700, 1e-9));
      expect(s.etaText, '9:25 PM');
      expect(s.eta, DateTime(2026, 10, 24, 21, 25));
      expect(s.arrow!.id, '5c317d6e0e');
    });

    test('the classic shape with an empty title has no distance', () {
      final n = loadNavFixture('maps_25_33_android16.jsonl')
          .firstWhere(
            (r) => r.notification?.title == '' && r.notification?.text != null,
          )
          .notification!;
      final s = _parse(n);

      expect(s.phase, NavPhase.guiding);
      expect(s.distanceText, isNull);
      expect(s.distanceToTurnM, isNull);
      expect(s.instruction, 'toward Vittal Mallya Rd');
    });

    test(
      'the progress shape: a distance, an instruction and the route left',
      () {
        final n = _fixture('650 m · Turn right at Richmond Cir');
        final s = _parse(n);

        expect(s.phase, NavPhase.guiding);
        expect(s.shape, NavShape.progress);
        expect(s.distanceText, '650 m');
        expect(s.distanceToTurnM, 650);
        expect(s.instruction, 'Turn right at Richmond Cir onto Mission Rd');
        // Progress 171 of 6605 metres.
        expect(s.distanceLeftM, 6605 - 171);
        expect(s.etaText, '9:25 PM');
        expect(s.eta, DateTime(2026, 10, 24, 21, 25));
        // No time left in this shape: it is the ETA less the phone's clock.
        expect(s.timeLeft, const Duration(minutes: 27));
        expect(s.timeLeftIsDerived, isTrue);
        expect(s.arrow, isNotNull);
      },
    );

    test('an instruction with a full stop and brackets stays whole', () {
      final s = _parse(_fixture('Sandarshini'));

      expect(s.distanceToTurnM, 500);
      expect(
        s.instruction,
        'Turn left after Sandarshini Sweet Shoppe. (on the left) onto Mission Rd',
      );
    });

    test('an instruction with no distance is only an instruction', () {
      for (final title in ['Head north', 'Head west']) {
        final s = _parse(_fixture(title));
        expect(s.phase, NavPhase.guiding, reason: title);
        expect(s.instruction, title);
        expect(s.distanceText, isNull);
        expect(s.distanceToTurnM, isNull);
        expect(s.distanceLeftM, isNotNull);
        expect(s.arrow, isNotNull);
      }
    });

    test('the route left falls as the car goes along it', () {
      final lefts = [
        for (final r in records)
          if (r.notification?.title?.contains('Richmond Cir') ?? false)
            _parse(r.notification!).distanceLeftM!,
      ];
      expect(lefts.length, greaterThan(5));
      for (var i = 1; i < lefts.length; i++) {
        expect(lefts[i], lessThanOrEqualTo(lefts[i - 1]));
      }
    });

    test('a different picture for a different turn', () {
      final ids = {
        for (final r in records)
          if (r.notification?.arrow != null) r.notification!.arrow!.id,
      };
      expect(ids.length, greaterThanOrEqualTo(3));
    });
  });

  group('what the capture did not have', () {
    NavNotification progress({
      String? title,
      String? critical,
      String? sub = 'Arrive 9:25 PM',
      int progress = 100,
      int max = 5000,
    }) => NavNotification(
      title: title,
      subText: sub,
      shortCriticalText: critical ?? '',
      progress: progress,
      progressMax: max,
      template: 'android.app.Notification\$ProgressStyle',
      arrow: fixtureArrow('x'),
    );

    test('miles and feet', () {
      final s = _parse(
        progress(title: '0.3 mi · Turn left onto Main St', critical: '0.3 mi'),
      );
      expect(s.distanceText, '0.3 mi');
      expect(s.distanceToTurnM, closeTo(482.8, 0.1));
      expect(s.instruction, 'Turn left onto Main St');

      final f = _parse(
        progress(title: '500 ft · Keep right', critical: '500 ft'),
      );
      expect(f.distanceToTurnM, closeTo(152.4, 0.1));
    });

    test(
      'a unit it does not know: the text is kept, the figure is not made up',
      () {
        final unit = String.fromCharCodes([0x0CAE, 0x0CC0]);
        final s = _parse(
          progress(title: '650 $unit · Turn right', critical: '650 $unit'),
        );
        expect(s.distanceText, '650 $unit');
        expect(s.distanceToTurnM, isNull);
        // The instruction does not repeat the distance.
        expect(s.instruction, 'Turn right');
      },
    );

    test('the same unit, taught to it', () {
      final unit = String.fromCharCodes([0x0CAE, 0x0CC0]);
      final s = NavParser(units: {unit: 1}).parse(
        progress(title: '650 $unit · Turn right', critical: '650 $unit'),
        _evening,
      );
      expect(s.distanceToTurnM, 650);
    });

    test('a 24 hour ETA', () {
      final s = _parse(progress(title: 'Head north', sub: 'Arrive 21:25'));
      expect(s.eta, DateTime(2026, 10, 24, 21, 25));
      expect(s.etaText, '21:25');
    });

    test('an ETA that has just passed is this minute, not tomorrow', () {
      final s = _parse(
        progress(title: 'Head north'),
        DateTime(2026, 10, 24, 21, 27),
      );
      expect(s.eta, DateTime(2026, 10, 24, 21, 25));
      expect(s.timeLeft, Duration.zero);
    });

    test('an ETA well past is tomorrow\'s', () {
      final s = _parse(
        progress(title: 'Head north'),
        DateTime(2026, 10, 24, 23, 50),
      );
      expect(s.eta, DateTime(2026, 10, 25, 21, 25));
    });

    test('a route that has ended has nothing left', () {
      final s = _parse(
        progress(title: 'Head north', progress: 6000, max: 5000),
      );
      expect(s.distanceLeftM, 0);
    });

    test('no figure is read out of text that has none', () {
      final s = _parse(
        const NavNotification(
          title: 'Something Google has not said before',
          arrow: null,
          subText: 'Arrive soon',
        ),
      );
      expect(s.phase, NavPhase.rerouting);
      expect(s.message, 'Something Google has not said before');
      expect(s.distanceLeftM, isNull);
      expect(s.eta, isNull);
    });

    test('the classic shape in miles with a 24 hour ETA', () {
      final s = _parse(
        NavNotification(
          title: '0.2 mi',
          text: 'toward Main St',
          subText: '1 hr 5 min · 24 mi · 21:25 ETA',
          arrow: fixtureArrow('a'),
        ),
      );
      expect(s.timeLeft, const Duration(hours: 1, minutes: 5));
      expect(s.distanceLeftM, closeTo(24 * 1609.344, 1e-6));
      expect(s.eta, DateTime(2026, 10, 24, 21, 25));
      expect(s.distanceToTurnM, closeTo(321.9, 0.1));
    });

    test('the parts of a classic sub text are told apart by what they are', () {
      final s = _parse(
        NavNotification(
          title: '100 m',
          text: 'Turn left',
          subText: '9:25 PM ETA · 28 min · 6.7 km',
          arrow: fixtureArrow('a'),
        ),
      );
      expect(s.timeLeft, const Duration(minutes: 28));
      expect(s.distanceLeftM, closeTo(6700, 1e-9));
      expect(s.etaText, '9:25 PM');
    });
  });

  group('the units Maps wrote in', () {
    test('metric on the capture', () {
      final n = loadNavFixture('maps_25_33_android16.jsonl')
          .map((r) => r.notification)
          .whereType<NavNotification>()
          .where((n) => n.arrow != null);
      for (final notification in n) {
        expect(_parse(notification).imperial, isFalse);
      }
    });

    test('miles and feet are imperial, in either shape', () {
      final progress = _parse(
        NavNotification(
          title: '0.3\u00A0mi \u00B7 Turn left',
          shortCriticalText: '0.3\u00A0mi',
          subText: 'Arrive 9:25 PM',
          progress: 1,
          progressMax: 9,
          arrow: fixtureArrow('a'),
        ),
      );
      final classic = _parse(
        NavNotification(
          title: '',
          text: 'Turn left',
          subText: '28 min \u00B7 6.7\u00A0mi \u00B7 9:25 PM ETA',
          arrow: fixtureArrow('a'),
        ),
      );
      final feet = _parse(
        NavNotification(
          title: '500\u00A0ft',
          text: 'Turn left',
          subText: '28 min \u00B7 9:25 PM ETA',
          arrow: fixtureArrow('a'),
        ),
      );

      expect(progress.imperial, isTrue);
      expect(classic.imperial, isTrue);
      expect(feet.imperial, isTrue);
    });
  });

  group('the wire form', () {
    test('a notification survives the channel', () {
      final n = NavNotification(
        title: '650 m',
        text: 't',
        subText: 's',
        shortCriticalText: 'c',
        progress: 3,
        progressMax: 9,
        template: 'x',
        arrow: fixtureArrow('abc', width: 2, height: 2),
      );
      final back = NavNotification.fromMap(n.toMap());

      expect(back.title, '650 m');
      expect(back.text, 't');
      expect(back.subText, 's');
      expect(back.shortCriticalText, 'c');
      expect(back.progress, 3);
      expect(back.progressMax, 9);
      expect(back.template, 'x');
      expect(back.arrow!.id, 'abc');
      expect(back.arrow!.alpha, hasLength(4));
    });

    test('an arrow already held is sent by its id only', () {
      final arrow = fixtureArrow('abc', width: 2, height: 2);
      final n = NavNotification(arrow: arrow);
      final map = n.toMap(sendArrowPixels: false);

      expect((map['arrow']! as Map).containsKey('alpha'), isFalse);
      expect(NavNotification.fromMap(map).arrow, isNull);
      expect(
        NavNotification.fromMap(map, arrowFor: (id) => arrow).arrow,
        same(arrow),
      );
    });

    test('a picture whose size does not match its pixels is not used', () {
      final map = {
        'arrow': {
          'id': 'a',
          'width': 3,
          'height': 3,
          'alpha': fixtureArrow('a', width: 2, height: 2).alpha,
        },
      };
      expect(NavNotification.fromMap(map).arrow, isNull);
    });
  });
}
