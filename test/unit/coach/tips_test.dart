// The tip rules (CLAUDE.md 8.9) on hand-made trips.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/tips.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';

Trip trip({
  double normal = 1.0,
  double idling = 0,
  double hard = 0,
  double fast = 0,
  double idleSeconds = 0,
  int hardAccelerations = 0,
  int hardBrakings = 0,
  double highRpmSeconds = 0,
  double? price = 100,
}) => Trip(
  startedAt: DateTime(2026, 3, 1),
  pricePerLitre: price,
  litres: normal + idling + hard + fast,
  idleSeconds: idleSeconds,
  hardAccelerations: hardAccelerations,
  hardBrakings: hardBrakings,
  highRpmSeconds: highRpmSeconds,
  bucketLitres: {
    SpendBucket.normal: normal,
    SpendBucket.idling: idling,
    SpendBucket.hardAcceleration: hard,
    SpendBucket.highSpeed: fast,
  },
);

void main() {
  const engine = TipEngine();

  test('a clean trip has no tip', () {
    expect(engine.tipsFor(trip()), isEmpty);
  });

  test('a trip with no fuel has no tip', () {
    expect(engine.tipsFor(Trip(startedAt: DateTime(2026))), isEmpty);
  });

  group('idling', () {
    test('says what it cost and how long, in the voice of DESIGN.md 10', () {
      final t = trip(normal: 0.9, idling: 0.24, idleSeconds: 14 * 60);
      final tips = engine.tipsFor(t);
      expect(tips.single.kind, TipKind.idling);
      expect(
        tips.single.text,
        '₹24 of this trip went on idling — about 14 minutes with the engine on.',
      );
      expect(tips.single.impactCost, closeTo(24, 1e-9));
    });

    test('one minute is singular', () {
      final t = trip(normal: 0.1, idling: 0.1, idleSeconds: 60);
      expect(engine.tipsFor(t).single.text, contains('about 1 minute with'));
    });

    test('a small share of the fuel is not worth a word', () {
      expect(
        engine.tipsFor(trip(normal: 1, idling: 0.1, idleSeconds: 300)),
        isEmpty,
      );
    });

    test('nor is under a minute of it', () {
      expect(
        engine.tipsFor(trip(normal: 0.05, idling: 0.1, idleSeconds: 40)),
        isEmpty,
      );
    });

    test('with no price it says litres, not rupees', () {
      final t = trip(normal: 0.2, idling: 0.4, idleSeconds: 300, price: null);
      expect(
        engine.tipsFor(t).single.text,
        '0.4 L of this trip went on idling — about 5 minutes with the engine on.',
      );
      expect(engine.tipsFor(t).single.impactCost, isNull);
    });
  });

  group('the others', () {
    test('hard acceleration says how many times', () {
      final t = trip(normal: 1, hard: 0.18, hardAccelerations: 6);
      expect(
        engine.tipsFor(t).single.text,
        '₹18 went on hard acceleration this trip — 6 times.',
      );
    });

    test('and never says wasted', () {
      final t = trip(
        normal: 1,
        hard: 0.5,
        idling: 0.5,
        idleSeconds: 600,
        fast: 0.5,
        hardAccelerations: 1,
      );
      for (final tip in engine.tipsFor(t)) {
        expect(tip.text.toLowerCase(), isNot(contains('wast')));
      }
    });

    test('high speed names the threshold', () {
      final t = trip(normal: 1, fast: 0.4);
      expect(
        engine.tipsFor(t).single.text,
        '₹40 went on driving above 100 km/h.',
      );
    });

    test(
      'revs and hard stops have no fuel figure, and come after the money',
      () {
        final t = trip(
          normal: 1,
          hard: 0.2,
          highRpmSeconds: 40,
          hardBrakings: 5,
          hardAccelerations: 2,
        );
        final tips = engine.tipsFor(t);
        expect(tips.length, 2);
        expect(tips[0].kind, TipKind.hardAcceleration);
        expect(tips[1].impactLitres, 0);
      },
    );

    test('revs alone are mentioned with the threshold', () {
      final t = trip(normal: 1, highRpmSeconds: 40);
      expect(
        engine.tipsFor(t).single.text,
        'The engine spent 40 seconds above 3,500 rpm this trip.',
      );
    });
  });

  test('at most two, the costliest first', () {
    final t = trip(
      normal: 1,
      idling: 0.5,
      idleSeconds: 600,
      hard: 0.3,
      fast: 0.4,
      hardAccelerations: 3,
    );
    final tips = engine.tipsFor(t);
    expect(tips.length, 2);
    expect(tips[0].kind, TipKind.idling);
    expect(tips[1].kind, TipKind.highSpeed);
  });

  test('the maximum is configurable', () {
    const one = TipEngine(thresholds: TipThresholds(maxTips: 1));
    final t = trip(normal: 1, idling: 0.5, idleSeconds: 600, hard: 0.3);
    expect(one.tipsFor(t).length, 1);
  });
}
