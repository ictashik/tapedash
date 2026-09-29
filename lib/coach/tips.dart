import '../money/spend_bucket.dart';
import '../trips/trip.dart';
import 'coach_thresholds.dart';

/// What a tip is about.
enum TipKind { idling, hardAcceleration, highSpeed, highRpm, hardBraking }

/// One tip: a plain sentence about a trip, with what it cost (CLAUDE.md 8.9).
class Tip {
  const Tip({
    required this.kind,
    required this.text,
    required this.impactLitres,
    this.impactCost,
  });

  final TipKind kind;

  /// The sentence, in the voice of DESIGN.md 10: facts with money, never shame.
  final String text;

  /// The fuel the thing took, in litres; 0 for what has no fuel figure of its
  /// own (revs, braking).
  final double impactLitres;

  /// The same in money, or null when no price was set.
  final double? impactCost;
}

/// The numbers the tip rules use.
class TipThresholds {
  const TipThresholds({
    this.minIdleSeconds = 60,
    this.minIdleShare = 0.2,
    this.minHardAccelShare = 0.06,
    this.minHighSpeedShare = 0.15,
    this.minLitres = 0.03,
    this.minHighRpmSeconds = 15,
    this.minHardBrakings = 3,
    this.maxTips = 2,
  });

  /// An idling tip needs at least this long stopped with the engine on...
  final double minIdleSeconds;

  /// ...and that much of the trip's fuel (a signal or two is not worth a word).
  final double minIdleShare;
  final double minHardAccelShare;
  final double minHighSpeedShare;

  /// A bucket of fuel smaller than this is not worth mentioning.
  final double minLitres;
  final double minHighRpmSeconds;
  final int minHardBrakings;

  /// At most this many tips a trip (CLAUDE.md 8.9).
  final int maxTips;
}

/// Turns a finished trip into at most two tips, by what they cost (CLAUDE.md
/// 8.9). The rules are templates; there is nothing clever, and no tip is ever
/// made for a trip that has no fuel figure.
///
/// **When tips are shown is not decided here:** tips appear only when the car is
/// stopped or the trip has ended. The screens that show them (Review, Coach,
/// the Debrief) are reachable only then, and they show nothing while moving.
class TipEngine {
  const TipEngine({
    this.thresholds = const TipThresholds(),
    this.coach = CoachThresholds.normal,
    this.currencySymbol = '₹',
  });

  final TipThresholds thresholds;
  final CoachThresholds coach;
  final String currencySymbol;

  /// The tips for [trip], the costliest first.
  List<Tip> tipsFor(Trip trip) {
    final total = trip.bucketLitres.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const [];
    final price = trip.pricePerLitre;
    final tips = <Tip>[];

    double litres(SpendBucket b) => trip.bucketLitres[b] ?? 0;
    String what(double l) => price == null
        ? '${l.toStringAsFixed(1)} L'
        : '$currencySymbol${(l * price).round()}';
    double? cost(double l) => price == null ? null : l * price;

    final idle = litres(SpendBucket.idling);
    if (trip.idleSeconds >= thresholds.minIdleSeconds &&
        idle >= thresholds.minLitres &&
        idle / total >= thresholds.minIdleShare) {
      final minutes = (trip.idleSeconds / 60).round();
      tips.add(
        Tip(
          kind: TipKind.idling,
          text:
              '${what(idle)} of this trip went on idling — about '
              '$minutes ${minutes == 1 ? 'minute' : 'minutes'} with the engine on.',
          impactLitres: idle,
          impactCost: cost(idle),
        ),
      );
    }

    final hard = litres(SpendBucket.hardAcceleration);
    if (hard >= thresholds.minLitres &&
        hard / total >= thresholds.minHardAccelShare) {
      final n = trip.hardAccelerations;
      tips.add(
        Tip(
          kind: TipKind.hardAcceleration,
          text:
              '${what(hard)} went on hard acceleration this trip'
              '${n > 0 ? ' — $n ${n == 1 ? 'time' : 'times'}' : ''}.',
          impactLitres: hard,
          impactCost: cost(hard),
        ),
      );
    }

    final fast = litres(SpendBucket.highSpeed);
    if (fast >= thresholds.minLitres &&
        fast / total >= thresholds.minHighSpeedShare) {
      tips.add(
        Tip(
          kind: TipKind.highSpeed,
          text:
              '${what(fast)} went on driving above '
              '${coach.speedLimitKmh.round()} km/h.',
          impactLitres: fast,
          impactCost: cost(fast),
        ),
      );
    }

    if (trip.highRpmSeconds >= thresholds.minHighRpmSeconds) {
      tips.add(
        Tip(
          kind: TipKind.highRpm,
          text:
              'The engine spent ${trip.highRpmSeconds.round()} seconds above '
              '${_thousands(coach.highRpm.round())} rpm this trip.',
          impactLitres: 0,
        ),
      );
    }

    if (trip.hardBrakings >= thresholds.minHardBrakings) {
      tips.add(
        Tip(
          kind: TipKind.hardBraking,
          text: 'There were ${trip.hardBrakings} hard stops this trip.',
          impactLitres: 0,
        ),
      );
    }

    tips.sort((a, b) => b.impactLitres.compareTo(a.impactLitres));
    return tips.take(thresholds.maxTips).toList();
  }

  static String _thousands(int n) {
    final s = n.toString();
    return s.length > 3
        ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}'
        : s;
  }
}
